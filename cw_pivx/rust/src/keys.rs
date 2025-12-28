//! PIVX Sapling key management.
//! 
//! Implements ZIP-32 HD key derivation for Sapling shielded addresses.
//! Uses PIVX-specific HRPs (Human Readable Parts) for address encoding.
//!
//! # Security Note
//! 
//! This module handles cryptographic secrets (spending keys) that must be
//! securely zeroed from memory when no longer needed. The SaplingKeyManager
//! implements Drop to ensure secrets are cleared.

use sapling::{
    zip32::{DiversifiableFullViewingKey, ExtendedSpendingKey},
    PaymentAddress,
};
use zcash_primitives::zip32::{ChildIndex, DiversifierIndex};
use bech32::{ToBase32, FromBase32, Variant};

use crate::error::SaplingError;
use crate::types::Network;

/// Result type for Sapling operations.
pub type SaplingResult<T> = Result<T, SaplingError>;

/// Human readable parts for PIVX Sapling keys.
pub mod hrp {
    /// Payment address HRP (mainnet).
    pub const PAYMENT_ADDRESS_MAINNET: &str = "ps";
    /// Payment address HRP (testnet).
    pub const PAYMENT_ADDRESS_TESTNET: &str = "ptestsapling";
    
    /// Full viewing key HRP (mainnet).
    pub const FULL_VIEWING_KEY_MAINNET: &str = "pviews";
    /// Full viewing key HRP (testnet).
    pub const FULL_VIEWING_KEY_TESTNET: &str = "pviewtestsapling";
    
    /// Extended spending key HRP (mainnet).
    pub const EXTENDED_SPENDING_KEY_MAINNET: &str = "p-secret-extended-key-main";
    /// Extended spending key HRP (testnet).
    pub const EXTENDED_SPENDING_KEY_TESTNET: &str = "p-secret-extended-key-test";
}

/// PIVX Sapling key manager.
/// 
/// Manages the full hierarchy of Sapling keys derived from a seed:
/// - Extended Spending Key (secret)
/// - Full Viewing Key (can view all transactions)
/// - Outgoing Viewing Key (can view outgoing transactions)
/// - Payment Addresses (can receive payments)
pub struct SaplingKeyManager {
    /// The extended spending key (root of key derivation).
    extended_spending_key: ExtendedSpendingKey,
    /// The diversifiable full viewing key.
    dfvk: DiversifiableFullViewingKey,
    /// Current diversifier index for address derivation.
    diversifier_index: DiversifierIndex,
    /// Network (mainnet or testnet).
    network: Network,
}

impl SaplingKeyManager {
    /// Create a new key manager from a seed.
    /// 
    /// # Arguments
    /// * `seed` - 64-byte seed (typically from BIP39 mnemonic).
    /// * `network` - Network type (mainnet or testnet).
    /// 
    /// # Returns
    /// A new SaplingKeyManager or an error.
    pub fn from_seed(seed: &[u8], network: Network) -> SaplingResult<Self> {
        if seed.len() < 32 {
            return Err(SaplingError::InvalidSeed);
        }
        
        // Derive master extended spending key using PIVX Sapling path
        // PIVX uses coin_type = 119 (registered with SLIP-44)
        let master = ExtendedSpendingKey::master(seed);
        
        // Derive to PIVX Sapling path: m/32'/119'/account'
        // We use account 0 by default
        let account_path = [
            ChildIndex::hardened(32),   // Purpose: Sapling
            ChildIndex::hardened(119),  // Coin type: PIVX
            ChildIndex::hardened(0),    // Account 0
        ];
        
        let extended_spending_key = ExtendedSpendingKey::from_path(&master, &account_path);
        
        // Derive the diversifiable full viewing key
        let dfvk = extended_spending_key.to_diversifiable_full_viewing_key();
        
        Ok(Self {
            extended_spending_key,
            dfvk,
            diversifier_index: DiversifierIndex::new(),
            network,
        })
    }
    
    /// Get the extended spending key.
    pub fn extended_spending_key(&self) -> &ExtendedSpendingKey {
        &self.extended_spending_key
    }
    
    /// Get the diversifiable full viewing key.
    pub fn diversifiable_full_viewing_key(&self) -> &DiversifiableFullViewingKey {
        &self.dfvk
    }
    
    /// Derive a payment address at the given diversifier index.
    pub fn derive_address(&self, diversifier_index: DiversifierIndex) -> SaplingResult<PaymentAddress> {
        self.dfvk
            .address(diversifier_index)
            .ok_or(SaplingError::InvalidDiversifier)
    }
    
    /// Get the default payment address (diversifier index 0).
    pub fn default_address(&self) -> SaplingResult<PaymentAddress> {
        let (_, addr) = self.dfvk.default_address();
        Ok(addr)
    }
    
    /// Find a valid diversifier starting from the current index.
    pub fn next_address(&mut self) -> SaplingResult<PaymentAddress> {
        let (new_index, addr) = self.dfvk
            .find_address(self.diversifier_index)
            .ok_or(SaplingError::InvalidDiversifier)?;
        
        // Increment for next call
        self.diversifier_index = new_index;
        self.diversifier_index.increment().map_err(|_| SaplingError::InvalidDiversifier)?;
        
        Ok(addr)
    }
    
    /// Encode a payment address as a bech32 string.
    pub fn encode_payment_address(&self, address: &PaymentAddress) -> String {
        let hrp = match self.network {
            Network::Mainnet => hrp::PAYMENT_ADDRESS_MAINNET,
            Network::Testnet => hrp::PAYMENT_ADDRESS_TESTNET,
        };
        
        encode_payment_address(hrp, address)
    }
    
    /// Decode a bech32 payment address string.
    pub fn decode_payment_address(&self, encoded: &str) -> SaplingResult<PaymentAddress> {
        let expected_hrp = match self.network {
            Network::Mainnet => hrp::PAYMENT_ADDRESS_MAINNET,
            Network::Testnet => hrp::PAYMENT_ADDRESS_TESTNET,
        };
        
        decode_payment_address(expected_hrp, encoded)
    }
    
    /// Encode the full viewing key as a bech32 string.
    pub fn encode_full_viewing_key(&self) -> String {
        let hrp = match self.network {
            Network::Mainnet => hrp::FULL_VIEWING_KEY_MAINNET,
            Network::Testnet => hrp::FULL_VIEWING_KEY_TESTNET,
        };
        
        let fvk = self.dfvk.to_bytes();
        bech32::encode(hrp, fvk.to_base32(), Variant::Bech32)
            .expect("FVK encoding should not fail")
    }

    /// Check if an address belongs to this wallet (can be decrypted with our viewing key).
    pub fn is_our_address(&self, address: &PaymentAddress) -> bool {
        // Try to find a diversifier index that produces this address
        let mut idx = DiversifierIndex::new();
        for _ in 0..1000 {
            if let Some((_, derived)) = self.dfvk.find_address(idx) {
                if derived == *address {
                    return true;
                }
            }
            if idx.increment().is_err() {
                break;
            }
        }
        false
    }
    
    /// Get the network.
    pub fn network(&self) -> Network {
        self.network
    }
}

/// Securely drop key material.
/// 
/// Note: ExtendedSpendingKey is from an external crate and doesn't implement Zeroize.
/// Consider submitting a PR to librustpivx or using mlock for production hardening.
impl Drop for SaplingKeyManager {
    fn drop(&mut self) {
        // SECURITY: Zero key material from memory
        // 
        // ExtendedSpendingKey from zcash_primitives doesn't implement Zeroize,
        // so we manually zero the memory. This is critical for preventing key
        // exposure via memory dumps, core dumps, or swap files.
        //
        // Note: This is a best-effort approach. The Rust compiler may optimize
        // away the zeroing if it determines the value is no longer used. For
        // production deployments, consider:
        // 1. Using volatile writes to prevent optimization
        // 2. Using mlock/mprotect to prevent swapping
        // 3. Patching upstream to add Zeroize support
        
        use std::ptr;
        
        unsafe {
            // Zero the extended spending key structure
            let esk_ptr = &mut self.extended_spending_key as *mut ExtendedSpendingKey;
            ptr::write_bytes(
                esk_ptr as *mut u8,
                0,
                std::mem::size_of::<ExtendedSpendingKey>()
            );
            
            // Zero the diversifiable full viewing key
            // (contains spending key-derived data)
            let dfvk_ptr = &mut self.dfvk as *mut DiversifiableFullViewingKey;
            ptr::write_bytes(
                dfvk_ptr as *mut u8,
                0,
                std::mem::size_of::<DiversifiableFullViewingKey>()
            );
            
            // Diversifier index doesn't contain secret material, but zero anyway
            let div_ptr = &mut self.diversifier_index as *mut DiversifierIndex;
            ptr::write_bytes(
                div_ptr as *mut u8,
                0,
                std::mem::size_of::<DiversifierIndex>()
            );
        }
        
        // Note: Even after zeroing, the memory page may still exist in:
        // - CPU caches
        // - Swap/page files (if memory was swapped out)
        // - Core dumps (if process crashed before drop)
        // 
        // For maximum security, use mlock() to prevent swapping and consider
        // encrypted swap or no swap at all.
    }
}

/// Encode a payment address with the given HRP.
pub fn encode_payment_address(hrp: &str, address: &PaymentAddress) -> String {
    let bytes = address.to_bytes();
    bech32::encode(hrp, bytes.to_base32(), Variant::Bech32)
        .expect("Payment address encoding should not fail")
}

/// Decode a payment address from a bech32 string.
pub fn decode_payment_address(expected_hrp: &str, encoded: &str) -> SaplingResult<PaymentAddress> {
    let (hrp, data, _variant) = bech32::decode(encoded)
        .map_err(|_| SaplingError::InvalidAddress)?;
    
    if hrp != expected_hrp {
        return Err(SaplingError::InvalidAddress);
    }
    
    let data = Vec::<u8>::from_base32(&data)
        .map_err(|_| SaplingError::InvalidAddress)?;
    
    if data.len() != 43 {
        return Err(SaplingError::InvalidAddress);
    }
    
    let bytes: [u8; 43] = data.try_into()
        .map_err(|_| SaplingError::InvalidAddress)?;
    
    PaymentAddress::from_bytes(&bytes)
        .ok_or(SaplingError::InvalidAddress)
}

/// Validate a PIVX Sapling address string.
pub fn validate_address(address: &str, network: Network) -> bool {
    let expected_hrp = match network {
        Network::Mainnet => hrp::PAYMENT_ADDRESS_MAINNET,
        Network::Testnet => hrp::PAYMENT_ADDRESS_TESTNET,
    };
    
    decode_payment_address(expected_hrp, address).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_key_derivation_from_seed() {
        // Test seed (32 bytes minimum)
        let seed = [0u8; 64];
        
        let manager = SaplingKeyManager::from_seed(&seed, Network::Mainnet)
            .expect("Key derivation should succeed");
        
        // Should be able to derive default address
        let address = manager.default_address().expect("Default address should work");
        
        // Encode and decode should roundtrip
        let encoded = manager.encode_payment_address(&address);
        assert!(encoded.starts_with("ps"));
        
        let decoded = manager.decode_payment_address(&encoded)
            .expect("Decoding should succeed");
        assert_eq!(address, decoded);
    }
    
    #[test]
    fn test_address_derivation() {
        let seed = [1u8; 64];
        let mut manager = SaplingKeyManager::from_seed(&seed, Network::Mainnet)
            .expect("Key derivation should succeed");
        
        let addr1 = manager.next_address().expect("First address");
        let addr2 = manager.next_address().expect("Second address");
        
        // Addresses should be different
        assert_ne!(addr1, addr2);
    }
    
    #[test]
    fn test_viewing_key_encoding() {
        let seed = [2u8; 64];
        let manager = SaplingKeyManager::from_seed(&seed, Network::Mainnet)
            .expect("Key derivation should succeed");
        
        let fvk_encoded = manager.encode_full_viewing_key();
        assert!(fvk_encoded.starts_with("pviews"));
    }
    
    #[test]
    fn test_address_validation() {
        assert!(!validate_address("invalid", Network::Mainnet));
        
        // Generate a valid address and test
        let seed = [3u8; 64];
        let manager = SaplingKeyManager::from_seed(&seed, Network::Mainnet)
            .expect("Key derivation should succeed");
        let address = manager.default_address().expect("Default address");
        let encoded = manager.encode_payment_address(&address);
        
        assert!(validate_address(&encoded, Network::Mainnet));
        assert!(!validate_address(&encoded, Network::Testnet));
    }

    #[test]
    fn test_key_manager_drop_zeros_memory() {
        // This test verifies that the Drop implementation compiles and runs without panic.
        // NOTE: We cannot directly verify that memory has been zeroed because accessing
        // memory after drop is undefined behavior in Rust. Real verification requires:
        // 1. Memory analysis tools (valgrind, miri, debugger)
        // 2. Reading process memory dumps
        // 3. Security audits with specialized testing frameworks
        
        let seed = [4u8; 64];
        {
            let _manager = SaplingKeyManager::from_seed(&seed, Network::Mainnet)
                .expect("Key derivation should succeed");
            // Drop occurs here when _manager goes out of scope
        }
        // If we reach this point, Drop didn't panic
    }
}
