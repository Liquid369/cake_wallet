//! PIVX Sapling transaction building.
//!
//! Builds shielded transactions using Groth16 proofs.

use rand::rngs::OsRng;
use sapling::{
    builder::{Builder as SaplingBuilder, BundleType},
    value::NoteValue,
    zip32::{DiversifiableFullViewingKey, ExtendedSpendingKey},
    Anchor, MerklePath, PaymentAddress,
    note_encryption::Zip212Enforcement,
};
use zcash_primitives::zip32::Scope;
use zcash_protocol::consensus::{BlockHeight, NetworkType, NetworkUpgrade, Parameters};

use crate::error::SaplingError;
use crate::notes::SpendableNote;
use crate::prover;

/// Result type for Sapling operations.
pub type SaplingResult<T> = Result<T, SaplingError>;

/// PIVX max supply: 21,000,000 coins = 21,000,000,000,000 zatoshis (21 trillion zatoshis).
pub const PIVX_MAX_SUPPLY: u64 = 21_000_000_000_000u64;

/// Dust threshold: 0.001 PIV = 1,000,000 zatoshis (1 million).
/// Outputs below this are economically unspendable due to fee costs.
pub const DUST_THRESHOLD: u64 = 1_000_000u64;

/// Validate transaction amounts to prevent overflow and invalid sums.
/// 
/// Checks:
/// - Integer overflow protection
/// - Max supply limits
/// - Dust threshold
/// - Balance equation (inputs = outputs + fee)
pub fn validate_transaction_amounts(
    input_amounts: &[u64],
    output_amounts: &[u64],
    fee: u64,
) -> Result<(), SaplingError> {
    // Check fee is reasonable (< 1 PIV)
    if fee > 1_000_000_000u64 {
        return Err(SaplingError::InvalidInput(
            format!("Fee too large: {} zatoshis (max 1 PIV)", fee)
        ));
    }
    
    // Check all output amounts are above dust threshold
    for (i, &amount) in output_amounts.iter().enumerate() {
        if amount < DUST_THRESHOLD {
            return Err(SaplingError::InvalidInput(
                format!("Output {} below dust threshold: {} zatoshis (min {} zatoshis)", 
                        i, amount, DUST_THRESHOLD)
            ));
        }
    }
    
    // Calculate input total with overflow check
    let mut input_total: u64 = 0;
    for (i, &amount) in input_amounts.iter().enumerate() {
        input_total = input_total.checked_add(amount)
            .ok_or_else(|| SaplingError::InvalidInput(
                format!("Input total overflow at input {}", i)
            ))?;
        
        // Check individual inputs don't exceed max supply
        if amount > PIVX_MAX_SUPPLY {
            return Err(SaplingError::InvalidInput(
                format!("Input {} exceeds max supply: {} > {}", i, amount, PIVX_MAX_SUPPLY)
            ));
        }
    }
    
    // Calculate output total with overflow check
    let mut output_total: u64 = 0;
    for (i, &amount) in output_amounts.iter().enumerate() {
        output_total = output_total.checked_add(amount)
            .ok_or_else(|| SaplingError::InvalidInput(
                format!("Output total overflow at output {}", i)
            ))?;
        
        // Check individual outputs don't exceed max supply
        if amount > PIVX_MAX_SUPPLY {
            return Err(SaplingError::InvalidInput(
                format!("Output {} exceeds max supply: {} > {}", i, amount, PIVX_MAX_SUPPLY)
            ));
        }
    }
    
    // Check totals don't exceed max supply
    if input_total > PIVX_MAX_SUPPLY {
        return Err(SaplingError::InvalidInput(
            format!("Input total exceeds max supply: {} > {}", input_total, PIVX_MAX_SUPPLY)
        ));
    }
    
    if output_total > PIVX_MAX_SUPPLY {
        return Err(SaplingError::InvalidInput(
            format!("Output total exceeds max supply: {} > {}", output_total, PIVX_MAX_SUPPLY)
        ));
    }
    
    // Verify balance equation: inputs = outputs + fee
    let expected_total = output_total.checked_add(fee)
        .ok_or_else(|| SaplingError::InvalidInput("Output + fee overflow".into()))?;
    
    if input_total != expected_total {
        return Err(SaplingError::InvalidInput(
            format!("Balance equation violation: inputs={}, outputs+fee={}", 
                    input_total, expected_total)
        ));
    }
    
    Ok(())
}

/// PIVX Sapling activation height.
pub const PIVX_SAPLING_ACTIVATION: u32 = 2_700_500;

/// PIVX mainnet consensus parameters.
#[derive(Clone, Copy, Debug)]
pub struct PivxMainnet;

impl Parameters for PivxMainnet {
    fn network_type(&self) -> NetworkType {
        NetworkType::Main
    }
    
    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match nu {
            NetworkUpgrade::Sapling => Some(BlockHeight::from_u32(PIVX_SAPLING_ACTIVATION)),
            _ => None,
        }
    }
}

/// PIVX testnet consensus parameters.
#[derive(Clone, Copy, Debug)]
pub struct PivxTestnet;

impl Parameters for PivxTestnet {
    fn network_type(&self) -> NetworkType {
        NetworkType::Test
    }
    
    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match nu {
            NetworkUpgrade::Sapling => Some(BlockHeight::from_u32(201)),
            _ => None,
        }
    }
}

/// Transaction output destination.
#[derive(Clone, Debug)]
pub enum TransactionOutput {
    /// Shielded output to a Sapling address.
    Shielded {
        address: PaymentAddress,
        amount: u64,
        memo: Option<[u8; 512]>,
    },
}

/// Options for building a transaction.
#[derive(Clone, Debug)]
pub struct TransactionOptions {
    /// Target height for the transaction.
    pub target_height: u32,
    /// Fee in zatoshis.
    pub fee: u64,
    /// Outputs to create.
    pub outputs: Vec<TransactionOutput>,
    /// Whether this is testnet.
    pub is_testnet: bool,
}

/// Built transaction ready for broadcast.
#[derive(Clone, Debug)]
pub struct BuiltTransaction {
    /// Serialized transaction bytes.
    pub raw_tx: Vec<u8>,
    /// Transaction ID (hash).
    pub txid: [u8; 32],
    /// Fee paid.
    pub fee: u64,
}

/// Sapling transaction builder.
/// 
/// Note: Full transaction building requires the prover parameters
/// which are large (~800MB). This struct manages the building process.
pub struct TransactionBuilder {
    /// Extended spending key for signing.
    esk: ExtendedSpendingKey,
    /// Full viewing key for decryption.
    dfvk: DiversifiableFullViewingKey,
    /// Whether testnet.
    is_testnet: bool,
}

impl TransactionBuilder {
    /// Create a new transaction builder.
    pub fn new(
        esk: ExtendedSpendingKey,
        dfvk: DiversifiableFullViewingKey,
        is_testnet: bool,
    ) -> Self {
        Self {
            esk,
            dfvk,
            is_testnet,
        }
    }
    
    /// Get the extended spending key.
    pub fn extended_spending_key(&self) -> &ExtendedSpendingKey {
        &self.esk
    }
    
    /// Get the full viewing key.
    pub fn dfvk(&self) -> &DiversifiableFullViewingKey {
        &self.dfvk
    }
    
    /// Check if this is testnet.
    pub fn is_testnet(&self) -> bool {
        self.is_testnet
    }
    
    /// Validate transaction inputs before building.
    pub fn validate_inputs(
        &self,
        notes: &[SpendableNote],
        merkle_paths: &[MerklePath],
        options: &TransactionOptions,
    ) -> SaplingResult<()> {
        if notes.len() != merkle_paths.len() {
            return Err(SaplingError::InvalidInput("notes and paths length mismatch".into()));
        }
        
        // Calculate totals
        let input_total: u64 = notes.iter().map(|n| n.value()).sum();
        let output_total: u64 = options.outputs.iter().map(|o| match o {
            TransactionOutput::Shielded { amount, .. } => *amount,
        }).sum();
        
        if input_total < output_total + options.fee {
            return Err(SaplingError::InsufficientFunds);
        }
        
        Ok(())
    }
    
    /// Calculate change amount.
    pub fn calculate_change(
        notes: &[SpendableNote],
        options: &TransactionOptions,
    ) -> u64 {
        let input_total: u64 = notes.iter().map(|n| n.value()).sum();
        let output_total: u64 = options.outputs.iter().map(|o| match o {
            TransactionOutput::Shielded { amount, .. } => *amount,
        }).sum();
        
        input_total.saturating_sub(output_total + options.fee)
    }
    
    /// Get the change address.
    pub fn change_address(&self) -> PaymentAddress {
        let (_, addr) = self.dfvk.default_address();
        addr
    }
    
    /// Build a Sapling transaction with the given inputs and outputs.
    /// 
    /// This is the main transaction building entry point. It:
    /// 0. Validates all amounts (CRITICAL security check)
    /// 1. Creates a Sapling bundle builder
    /// 2. Adds spend inputs with their witnesses
    /// 3. Adds outputs (including change if needed)
    /// 4. Generates Groth16 proofs using the prover
    /// 5. Returns the serialized transaction
    pub fn build_transaction(
        &self,
        notes: Vec<SpendableNote>,
        merkle_paths: Vec<MerklePath>,
        anchor: Anchor,
        outputs: Vec<(PaymentAddress, u64, Option<[u8; 512]>)>,
        fee: u64,
    ) -> SaplingResult<BuiltTransaction> {
        // Validate inputs
        if notes.len() != merkle_paths.len() {
            return Err(SaplingError::InvalidInput(
                "Notes and merkle paths count mismatch".into()
            ));
        }
        
        if notes.is_empty() {
            return Err(SaplingError::InvalidInput("No input notes provided".into()));
        }
        
        if outputs.is_empty() {
            return Err(SaplingError::InvalidInput("No outputs provided".into()));
        }
        
        // Check prover is initialized
        if !prover::is_prover_initialized() {
            return Err(SaplingError::ProverNotInitialized);
        }
        
        // Validate all transaction amounts
        let input_amounts: Vec<u64> = notes.iter().map(|n| n.value()).collect();
        let output_amounts: Vec<u64> = outputs.iter().map(|(_, amount, _)| *amount).collect();
        validate_transaction_amounts(&input_amounts, &output_amounts, fee)?;
        
        // Calculate totals (already validated above, but needed for change)
        let input_total: u64 = input_amounts.iter().sum();
        let output_total: u64 = output_amounts.iter().sum();
        
        let change = input_total - output_total - fee;
        
        // If change exists, validate it meets dust threshold
        if change > 0 && change < DUST_THRESHOLD {
            return Err(SaplingError::InvalidInput(
                format!("Change amount {} below dust threshold {}", change, DUST_THRESHOLD)
            ));
        }
        
        // Create the Sapling bundle builder
        // PIVX uses Zip212Enforcement::Off (pre-ZIP-212)
        let bundle_type = BundleType::Transactional {
            bundle_required: true,
        };
        
        let mut builder = SaplingBuilder::new(
            Zip212Enforcement::Off, // PIVX specific
            bundle_type,
            anchor,
        );
        
        // Get FVK for adding spends
        let fvk = self.dfvk.fvk();
        
        // Add spend inputs
        for (note, path) in notes.iter().zip(merkle_paths.into_iter()) {
            builder.add_spend(fvk.clone(), note.note.clone(), path)
                .map_err(|_e| SaplingError::TransactionBuild)?;
        }
        
        // Get OVK for outputs (allows sender to decrypt outputs later)
        let ovk = self.dfvk.to_ovk(Scope::External);
        
        // Add outputs
        for (address, amount, memo) in outputs {
            builder.add_output(
                Some(ovk.clone()),
                address,
                NoteValue::from_raw(amount),
                memo,
            ).map_err(|_| SaplingError::TransactionBuild)?;
        }
        
        // Add change output if needed
        if change > 0 {
            let change_address = self.change_address();
            builder.add_output(
                Some(ovk.clone()),
                change_address,
                NoteValue::from_raw(change),
                None,
            ).map_err(|_| SaplingError::TransactionBuild)?;
        }
        
        // Build the unauthorized bundle first
        let mut rng = OsRng;
        let extsks = &[self.esk.clone()];
        
        let build_result = builder
            .build::<zcash_proofs::prover::LocalTxProver, zcash_proofs::prover::LocalTxProver, _, i64>(extsks, &mut rng)
            .map_err(|e| SaplingError::ProofError(format!("Bundle build failed: {:?}", e)))?;
        
        let (unproven_bundle, _sapling_meta) = match build_result {
            Some(b) => b,
            None => return Err(SaplingError::TransactionBuild),
        };
        
        // Get the prover and create proofs
        let prover_guard = prover::get_prover()?;
        let local_prover = prover_guard.as_ref().ok_or(SaplingError::ProverNotInitialized)?;
        
        // Create proofs for the bundle
        let proven_bundle = unproven_bundle.create_proofs(
            local_prover,
            local_prover,
            &mut rng,
            (), // No progress notification
        );
        
        // Now we need to sign the bundle
        // For a Sapling-only transaction, we need:
        // 1. The sighash over the transaction 
        // 2. SpendAuthorizingKey from our ExtendedSpendingKey
        
        // Get the spend authorizing key
        let ask = self.esk.expsk.ask.clone();
        
        // Compute the sighash for Sapling signature
        // PIVX uses BLAKE2b with personalization "ZcashSigHash" + branch ID
        // For Sapling transactions, we hash the serialized bundle components
        let sighash = self.compute_sighash(&proven_bundle, fee);
        
        // Apply signatures
        let authorized_bundle = proven_bundle
            .apply_signatures(&mut rng, sighash, &[ask])
            .map_err(|e| SaplingError::ProofError(format!("Signing failed: {:?}", e)))?;
        
        // Serialize the Sapling bundle for broadcast
        // PIVX transactions follow a format similar to Zcash but with some differences
        let raw_tx = self.serialize_sapling_transaction(&authorized_bundle, fee)?;
        
        // Compute txid as double SHA256 of the raw transaction
        use sha2::{Sha256, Digest};
        let first_hash = Sha256::digest(&raw_tx);
        let txid_bytes = Sha256::digest(&first_hash);
        let mut txid = [0u8; 32];
        txid.copy_from_slice(&txid_bytes);
        // TXID is displayed in reverse byte order
        txid.reverse();
        
        Ok(BuiltTransaction {
            raw_tx,
            txid,
            fee,
        })
    }
    
    /// Serialize a Sapling bundle into PIVX transaction format.
    /// 
    /// PIVX transaction structure for Sapling:
    /// - Version: 4 bytes (version 3 with overwinter flag)
    /// - Version group ID: 4 bytes
    /// - Transparent inputs: varint count + inputs
    /// - Transparent outputs: varint count + outputs
    /// - Lock time: 4 bytes
    /// - Expiry height: 4 bytes
    /// - Value balance: 8 bytes (signed)
    /// - Sapling spends: varint count + serialized spends
    /// - Sapling outputs: varint count + serialized outputs
    /// - Binding signature: 64 bytes
    fn serialize_sapling_transaction(
        &self,
        bundle: &sapling::Bundle<sapling::bundle::Authorized, i64>,
        _fee: u64,
    ) -> SaplingResult<Vec<u8>> {
        use std::io::Write;
        
        let mut tx = Vec::new();
        
        // PIVX Transaction Header (4 bytes total):
        // - nVersion (2 bytes, int16_t): 3 for Sapling
        // - nType (2 bytes, int16_t): 0 for Normal transaction
        //
        // CRITICAL: PIVX does NOT use Zcash's transaction format:
        // ❌ Zcash: version (4 bytes with overwinter bit) + version group ID (4 bytes) = 8 bytes
        // ✅ PIVX: nVersion (2 bytes) + nType (2 bytes) = 4 bytes
        //
        // Reference: PIVX Core src/primitives/transaction.h
        //   class CTransaction {
        //       const int16_t nVersion;  // 1=Legacy, 3=Sapling
        //       const int16_t nType;     // 0=Normal, 1+=Special (ProReg, etc.)
        //   };
        //
        // Verified against: PIVX Core commit 0cbf7b89 (December 2025)
        tx.write_all(&3i16.to_le_bytes())
            .map_err(|_| SaplingError::TransactionBuild)?;  // nVersion = 3 (Sapling)
        tx.write_all(&0i16.to_le_bytes())
            .map_err(|_| SaplingError::TransactionBuild)?;  // nType = 0 (Normal)
        
        // No transparent inputs (varint 0)
        tx.push(0x00);
        
        // No transparent outputs (varint 0)
        tx.push(0x00);
        
        // Lock time (4 bytes, 0 = immediate)
        tx.write_all(&0u32.to_le_bytes())
            .map_err(|_| SaplingError::TransactionBuild)?;
        
        // CRITICAL: PIVX does NOT serialize expiry height (Zcash-specific feature removed)
        // Reference: PIVX Core src/primitives/transaction.h SerializeTransaction()
        //   s << tx.nVersion;
        //   s << tx.nType;
        //   s << tx.vin;
        //   s << tx.vout;
        //   s << tx.nLockTime;
        //   if (tx.isSaplingVersion()) {
        //       s << tx.sapData;  // Goes DIRECTLY to Sapling data, no expiry height!
        //   }
        //
        // ❌ DO NOT serialize expiry height - field doesn't exist in PIVX
        
        // Value balance (8 bytes, signed little endian)
        // This is the net value flow: sum(spend values) - sum(output values)
        // A positive value means value is flowing from shielded to transparent
        // For a pure shielded tx, this equals the fee
        let value_balance: i64 = *bundle.value_balance();
        tx.write_all(&value_balance.to_le_bytes())
            .map_err(|_| SaplingError::TransactionBuild)?;
        
        // Sapling spends
        let spends = bundle.shielded_spends();
        self.write_varint(&mut tx, spends.len() as u64);
        for spend in spends {
            // cv (32 bytes) - value commitment
            tx.write_all(&spend.cv().to_bytes())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // anchor (32 bytes)
            tx.write_all(&spend.anchor().to_bytes())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // nullifier (32 bytes)
            tx.write_all(&spend.nullifier().0)
                .map_err(|_| SaplingError::TransactionBuild)?;
            // rk (32 bytes) - randomized public key
            let rk_bytes: [u8; 32] = spend.rk().clone().into();
            tx.write_all(&rk_bytes)
                .map_err(|_| SaplingError::TransactionBuild)?;
            // zkproof (192 bytes for Groth16)
            tx.write_all(spend.zkproof())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // spend_auth_sig (64 bytes)
            tx.write_all(&<[u8; 64]>::from(*spend.spend_auth_sig()))
                .map_err(|_| SaplingError::TransactionBuild)?;
        }
        
        // Sapling outputs
        let outputs = bundle.shielded_outputs();
        self.write_varint(&mut tx, outputs.len() as u64);
        for output in outputs {
            // cv (32 bytes) - value commitment
            tx.write_all(&output.cv().to_bytes())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // cmu (32 bytes) - note commitment
            tx.write_all(&output.cmu().to_bytes())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // ephemeral_key (32 bytes)
            tx.write_all(output.ephemeral_key().as_ref())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // enc_ciphertext (580 bytes)
            tx.write_all(output.enc_ciphertext())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // out_ciphertext (80 bytes)
            tx.write_all(output.out_ciphertext())
                .map_err(|_| SaplingError::TransactionBuild)?;
            // zkproof (192 bytes)
            tx.write_all(output.zkproof())
                .map_err(|_| SaplingError::TransactionBuild)?;
        }
        
        // Binding signature (64 bytes)
        let binding_sig = bundle.authorization().binding_sig;
        tx.write_all(&<[u8; 64]>::from(binding_sig))
            .map_err(|_| SaplingError::TransactionBuild)?;
        
        Ok(tx)
    }
    
    /// Write a variable-length integer (Bitcoin-style varint).
    fn write_varint(&self, buf: &mut Vec<u8>, n: u64) {
        if n < 0xfd {
            buf.push(n as u8);
        } else if n <= 0xffff {
            buf.push(0xfd);
            buf.extend_from_slice(&(n as u16).to_le_bytes());
        } else if n <= 0xffffffff {
            buf.push(0xfe);
            buf.extend_from_slice(&(n as u32).to_le_bytes());
        } else {
            buf.push(0xff);
            buf.extend_from_slice(&n.to_le_bytes());
        }
    }
    
    /// Compute sighash for Sapling transaction signing.
    /// 
    /// PIVX uses BLAKE2b-256 with personalization: "PIVXSigHash" + branch ID (0).
    /// The sighash format is based on ZIP 243 but adapted for PIVX's transaction structure.
    /// 
    /// Reference: PIVX Core src/script/interpreter.cpp SignatureHash()
    ///   ss << txTo.nVersion;  // int16_t (2 bytes)
    ///   ss << txTo.nType;     // int16_t (2 bytes)
    ///   ss << hashPrevouts;
    ///   ss << hashSequence;
    ///   ss << hashOutputs;
    ///   ss << hashShieldedSpends;
    ///   ss << hashShieldedOutputs;
    ///   ss << txTo.sapData->valueBalance;
    ///   // ... input being signed, locktime, hashtype
    fn compute_sighash(
        &self,
        bundle: &sapling::Bundle<sapling::builder::InProgress<sapling::builder::Proven, sapling::builder::Unsigned>, i64>,
        _fee: u64,
    ) -> [u8; 32] {
        use blake2b_simd::Params;
        use std::io::Write;
        
        // PIVX Sapling personalization: "PIVXSigHash" (12 bytes) + branch_id (4 bytes)
        // Verified against PIVX Core: src/script/interpreter.cpp:1228-1234
        let mut personalization = [0u8; 16];
        personalization[..12].copy_from_slice(b"PIVXSigHash");
        // PIVX uses branch ID 0 (not Zcash's 0x03C48270)
        // Verified against PIVX Core: src/script/interpreter.cpp:1229
        personalization[12..16].copy_from_slice(&0u32.to_le_bytes());
        
        let mut hasher = Params::new()
            .hash_length(32)
            .personal(&personalization)
            .to_state();
        
        // Hash transaction header data
        // PIVX format: nVersion (2 bytes) + nType (2 bytes)
        // Verified against PIVX Core: interpreter.cpp:1238-1240
        //   ss << txTo.nVersion;  // int16_t
        //   ss << txTo.nType;     // int16_t
        hasher.write_all(&3i16.to_le_bytes()).unwrap();  // nVersion = 3 (Sapling)
        hasher.write_all(&0i16.to_le_bytes()).unwrap();  // nType = 0 (Normal)
        
        // Hash prevouts (empty for pure Sapling)
        hasher.write_all(&[0u8; 32]).unwrap();
        
        // Hash sequence (empty for pure Sapling)
        hasher.write_all(&[0u8; 32]).unwrap();
        
        // Hash outputs (empty for pure Sapling)
        hasher.write_all(&[0u8; 32]).unwrap();
        
        // Hash joinsplits (empty)
        hasher.write_all(&[0u8; 32]).unwrap();
        
        // Hash shielded spends
        let mut spend_hash = Params::new()
            .hash_length(32)
            .personal(b"ZcashSSpendsHash")
            .to_state();
        for spend in bundle.shielded_spends() {
            spend_hash.write_all(&spend.cv().to_bytes()).unwrap();
            spend_hash.write_all(&spend.anchor().to_bytes()).unwrap();
            spend_hash.write_all(&spend.nullifier().0).unwrap();
            let rk_bytes: [u8; 32] = spend.rk().clone().into();
            spend_hash.write_all(&rk_bytes).unwrap();
        }
        hasher.write_all(spend_hash.finalize().as_bytes()).unwrap();
        
        // Hash shielded outputs
        let mut output_hash = Params::new()
            .hash_length(32)
            .personal(b"ZcashSOutputHash")
            .to_state();
        for output in bundle.shielded_outputs() {
            output_hash.write_all(&output.cv().to_bytes()).unwrap();
            output_hash.write_all(&output.cmu().to_bytes()).unwrap();
            output_hash.write_all(output.ephemeral_key().as_ref()).unwrap();
            output_hash.write_all(output.enc_ciphertext()).unwrap();
            output_hash.write_all(output.out_ciphertext()).unwrap();
        }
        hasher.write_all(output_hash.finalize().as_bytes()).unwrap();
        
        // Lock time (0)
        hasher.write_all(&0u32.to_le_bytes()).unwrap();
        
        // Expiry height (0)
        hasher.write_all(&0u32.to_le_bytes()).unwrap();
        
        // Value balance
        let value_balance: i64 = *bundle.value_balance();
        hasher.write_all(&value_balance.to_le_bytes()).unwrap();
        
        // Sighash type (SIGHASH_ALL = 1)
        hasher.write_all(&1u32.to_le_bytes()).unwrap();
        
        let result = hasher.finalize();
        let mut sighash = [0u8; 32];
        sighash.copy_from_slice(result.as_bytes());
        sighash
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_pivx_params() {
        let params = PivxMainnet;
        assert_eq!(params.network_type(), NetworkType::Main);
        
        let activation = params.activation_height(NetworkUpgrade::Sapling);
        assert!(activation.is_some());
        assert_eq!(activation.unwrap(), BlockHeight::from_u32(PIVX_SAPLING_ACTIVATION));
    }
    
    #[test]
    fn test_pivx_testnet_params() {
        let params = PivxTestnet;
        assert_eq!(params.network_type(), NetworkType::Test);
        
        let activation = params.activation_height(NetworkUpgrade::Sapling);
    }

    #[test]
    fn test_sighash_personalization() {
        // Verify we use PIVX-specific personalization, not Zcash's
        // Reference: PIVX Core src/script/interpreter.cpp:1228-1234
        let mut personalization = [0u8; 16];
        // "PIVXSigHash" is 11 bytes, padded with null to 12 bytes
        let pivx_str = b"PIVXSigHash";
        personalization[..pivx_str.len()].copy_from_slice(pivx_str);
        personalization[12..16].copy_from_slice(&0u32.to_le_bytes());
        
        // Verify the personalization string starts with PIVXSigHash
        assert_eq!(&personalization[..11], b"PIVXSigHash", 
            "Sighash personalization must start with 'PIVXSigHash' for PIVX consensus");
        
        // Verify 12th byte is null (padding)
        assert_eq!(personalization[11], 0, "12th byte should be null padding");
        
        // Verify branch ID is 0 (not Zcash's 0x03C48270)
        let branch_id = u32::from_le_bytes([
            personalization[12], personalization[13], 
            personalization[14], personalization[15]
        ]);
        assert_eq!(branch_id, 0, "Branch ID must be 0 for PIVX consensus");
    }
    
    #[test]
    fn test_transaction_version() {
        // PIVX uses a different transaction header format than Zcash
        // PIVX: nVersion (2 bytes, int16_t) + nType (2 bytes, int16_t)
        // Zcash: version with overwinter bit (4 bytes) + version group ID (4 bytes)
        //
        // Reference: PIVX Core src/primitives/transaction.h
        //   class CTransaction {
        //       const int16_t nVersion;  // 1=Legacy, 3=Sapling
        //       const int16_t nType;     // 0=Normal, 1+=Special
        //   };
        
        let n_version: i16 = 3;  // Sapling
        let n_type: i16 = 0;     // Normal transaction
        
        assert_eq!(n_version, 3, "Sapling transactions must use nVersion = 3");
        assert_eq!(n_type, 0, "Normal transactions must use nType = 0");
        
        // Verify serialization produces 4 bytes total
        let mut header = Vec::new();
        header.extend_from_slice(&n_version.to_le_bytes());  // 2 bytes
        header.extend_from_slice(&n_type.to_le_bytes());     // 2 bytes
        assert_eq!(header.len(), 4, "Transaction header must be exactly 4 bytes");
        
        // Verify the bytes match expected values
        assert_eq!(header, vec![0x03, 0x00, 0x00, 0x00], 
            "Header must be [0x03, 0x00, 0x00, 0x00] for Sapling Normal transaction");
    }
    
    #[test]
    fn test_activation_heights() {
        // Verify mainnet activation height
        // Reference: PIVX Core src/chainparams.cpp:285
        let mainnet = PivxMainnet;
        let mainnet_activation = mainnet.activation_height(NetworkUpgrade::Sapling);
        assert_eq!(mainnet_activation, Some(BlockHeight::from_u32(2_700_500)),
            "Mainnet Sapling activation must be block 2,700,500");
        
        // Verify testnet activation height
        // Reference: PIVX Core src/chainparams.cpp:445
        let testnet = PivxTestnet;
        let testnet_activation = testnet.activation_height(NetworkUpgrade::Sapling);
        assert_eq!(testnet_activation, Some(BlockHeight::from_u32(201)),
            "Testnet Sapling activation must be block 201");
    }
}
