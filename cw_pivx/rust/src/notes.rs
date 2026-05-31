//! PIVX Sapling note management.
//!
//! Handles Sapling notes (the fundamental unit of shielded value)
//! including decryption, nullifier computation, and spending.

use sapling::{Note, Nullifier, PaymentAddress};

use crate::error::SaplingError;

/// Result type for Sapling operations.
pub type SaplingResult<T> = Result<T, SaplingError>;

/// A decrypted Sapling note that can be spent.
#[derive(Clone, Debug)]
pub struct SpendableNote {
    /// The note itself.
    pub note: Note,
    /// The address that received this note.
    pub address: PaymentAddress,
    /// The position of this note's commitment in the tree.
    pub position: u64,
    /// The nullifier for this note (computed when needed for spending).
    pub nullifier: Nullifier,
    /// The block height at which this note was mined.
    pub height: u32,
    /// The transaction index within the block.
    pub tx_index: u32,
    /// The output index within the transaction.
    pub output_index: u32,
    /// Whether this note has been spent.
    pub is_spent: bool,
}

impl SpendableNote {
    /// Get the value of this note in zatoshis.
    pub fn value(&self) -> u64 {
        self.note.value().inner()
    }

    /// Mark this note as spent.
    pub fn mark_spent(&mut self) {
        self.is_spent = true;
    }

    /// Create a new spendable note.
    pub fn new(
        note: Note,
        address: PaymentAddress,
        position: u64,
        nullifier: Nullifier,
        height: u32,
        tx_index: u32,
        output_index: u32,
    ) -> Self {
        Self {
            note,
            address,
            position,
            nullifier,
            height,
            tx_index,
            output_index,
            is_spent: false,
        }
    }
}

/// A compact note for efficient sync (subset of full note data).
#[derive(Clone, Debug)]
pub struct CompactNote {
    /// Commitment to the note.
    pub cmu: [u8; 32],
    /// Ephemeral public key.
    pub epk: [u8; 32],
    /// Encrypted ciphertext (first 52 bytes only).
    pub enc_ciphertext: [u8; 52],
}

/// Note selection for transaction building.
/// Selects notes to meet a target amount plus fee.
pub fn select_notes_for_amount(
    notes: &[SpendableNote],
    target_amount: u64,
    fee: u64,
) -> SaplingResult<Vec<SpendableNote>> {
    let total_needed = target_amount + fee;

    // Filter unspent notes and sort by value (largest first)
    let mut available: Vec<_> = notes.iter().filter(|n| !n.is_spent).cloned().collect();

    available.sort_by(|a, b| b.value().cmp(&a.value()));

    // Greedy selection
    let mut selected = Vec::new();
    let mut selected_total = 0u64;

    for note in available {
        if selected_total >= total_needed {
            break;
        }
        selected_total += note.value();
        selected.push(note);
    }

    if selected_total < total_needed {
        return Err(SaplingError::InsufficientFunds);
    }

    Ok(selected)
}

/// Parse a merkle path from hex-encoded witness data.
///
/// The witness format from ElectrumX is typically:
/// - 32 sibling hashes (32 bytes each, 1024 bytes total)
/// - Optionally preceded by the position
///
/// # Arguments
/// * `witness_hex` - Hex-encoded witness data
/// * `position` - Position of the note in the tree
///
/// # Returns
/// A MerklePath suitable for spending, or an error.
pub fn parse_merkle_path(witness_hex: &str, position: u64) -> SaplingResult<sapling::MerklePath> {
    use incrementalmerkletree::Position;
    use sapling::Node;

    const SAPLING_TREE_DEPTH: usize = 32;
    const NODE_SIZE: usize = 32;

    let witness_bytes = hex::decode(witness_hex).map_err(|_| SaplingError::InvalidWitness)?;

    // Witness should be 32 * 32 = 1024 bytes (32 sibling hashes)
    if witness_bytes.len() != SAPLING_TREE_DEPTH * NODE_SIZE {
        return Err(SaplingError::InvalidWitness);
    }

    // Parse sibling hashes
    let mut path_elems = Vec::with_capacity(SAPLING_TREE_DEPTH);
    for i in 0..SAPLING_TREE_DEPTH {
        let start = i * NODE_SIZE;
        let end = start + NODE_SIZE;
        let node_bytes: [u8; 32] = witness_bytes[start..end]
            .try_into()
            .map_err(|_| SaplingError::InvalidWitness)?;

        let node_opt = Node::from_bytes(node_bytes);
        if bool::from(node_opt.is_none()) {
            return Err(SaplingError::InvalidWitness);
        }
        path_elems.push(node_opt.unwrap()); // Safe: just checked is_none()
    }

    // Create the MerklePath
    let pos = Position::from(position);
    sapling::MerklePath::from_parts(path_elems, pos).map_err(|_| SaplingError::InvalidWitness)
}

/// Reconstruct a Note from serialized data.
///
/// This is used when loading saved notes from storage for spending.
pub fn note_from_parts(
    diversifier_hex: &str,
    pk_d_hex: &str,
    value: u64,
    rseed_hex: &str,
) -> SaplingResult<(Note, PaymentAddress)> {
    use sapling::{value::NoteValue, Rseed};

    // Parse diversifier (11 bytes)
    let diversifier_bytes: [u8; 11] = hex::decode(diversifier_hex)
        .map_err(|_| SaplingError::InvalidInput("invalid diversifier hex".into()))?
        .try_into()
        .map_err(|_| SaplingError::InvalidInput("diversifier must be 11 bytes".into()))?;

    // Parse pk_d (32 bytes)
    let pk_d_bytes: [u8; 32] = hex::decode(pk_d_hex)
        .map_err(|_| SaplingError::InvalidInput("invalid pk_d hex".into()))?
        .try_into()
        .map_err(|_| SaplingError::InvalidInput("pk_d must be 32 bytes".into()))?;

    // Construct the 43-byte payment address: diversifier (11) + pk_d (32)
    let mut addr_bytes = [0u8; 43];
    addr_bytes[..11].copy_from_slice(&diversifier_bytes);
    addr_bytes[11..].copy_from_slice(&pk_d_bytes);

    let address = PaymentAddress::from_bytes(&addr_bytes).ok_or(SaplingError::InvalidAddress)?;

    // Parse rseed (32 bytes) - for pre-ZIP-212 this is rcm
    let rseed_bytes: [u8; 32] = hex::decode(rseed_hex)
        .map_err(|_| SaplingError::InvalidInput("invalid rseed hex".into()))?
        .try_into()
        .map_err(|_| SaplingError::InvalidInput("rseed must be 32 bytes".into()))?;

    // For PIVX (pre-ZIP-212), rseed is the commitment randomness directly
    let fr_opt = jubjub::Fr::from_bytes(&rseed_bytes);
    if bool::from(fr_opt.is_none()) {
        return Err(SaplingError::InvalidInput("invalid rseed scalar".into()));
    }
    let rseed = Rseed::BeforeZip212(fr_opt.unwrap()); // Safe: just checked is_none()

    // Create the note
    let note = Note::from_parts(address.clone(), NoteValue::from_raw(value), rseed);

    Ok((note, address))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_note_selection_insufficient() {
        let notes: Vec<SpendableNote> = vec![];
        let result = select_notes_for_amount(&notes, 1000, 100);
        assert!(result.is_err());
    }
}
