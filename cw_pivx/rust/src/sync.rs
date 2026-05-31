//! PIVX Sapling blockchain synchronization.
//!
//! Manages sync state including the commitment tree and note witnesses.

use sapling::Nullifier;

use crate::error::SaplingError;
use crate::notes::SpendableNote;

/// Result type for Sapling operations.
pub type SaplingResult<T> = Result<T, SaplingError>;

/// Sapling tree depth constant.
pub const SAPLING_TREE_DEPTH: u8 = 32;

/// Manages synchronization state for Sapling.
pub struct SyncState {
    /// Current sync height.
    sync_height: u32,
    /// Set of known nullifiers (spent notes).
    nullifier_set: Vec<Nullifier>,
    /// Spendable notes.
    notes: Vec<SpendableNote>,
    /// Commitment count.
    commitment_count: u64,
}

impl SyncState {
    /// Create a new sync state.
    pub fn new() -> Self {
        Self {
            sync_height: 0,
            nullifier_set: Vec::new(),
            notes: Vec::new(),
            commitment_count: 0,
        }
    }

    /// Create sync state from a specific block height.
    pub fn from_height(height: u32) -> Self {
        let mut state = Self::new();
        state.sync_height = height;
        state
    }

    /// Get the current sync height.
    pub fn sync_height(&self) -> u32 {
        self.sync_height
    }

    /// Get the current tree position.
    pub fn tree_position(&self) -> u64 {
        self.commitment_count
    }

    /// Increment commitment count (called when new commitment is added).
    pub fn increment_commitment_count(&mut self) {
        self.commitment_count += 1;
    }

    /// Record a note we can spend.
    pub fn add_note(&mut self, note: SpendableNote) -> SaplingResult<()> {
        self.notes.push(note);
        Ok(())
    }

    /// Check if a nullifier is in our spent set.
    pub fn is_nullifier_spent(&self, nullifier: &Nullifier) -> bool {
        self.nullifier_set.iter().any(|n| n == nullifier)
    }

    /// Add a nullifier to the spent set.
    pub fn add_spent_nullifier(&mut self, nullifier: Nullifier) {
        if !self.is_nullifier_spent(&nullifier) {
            self.nullifier_set.push(nullifier);

            // Mark matching notes as spent
            for note in &mut self.notes {
                if note.nullifier == nullifier {
                    note.is_spent = true;
                }
            }
        }
    }

    /// Get unspent notes.
    pub fn unspent_notes(&self) -> Vec<&SpendableNote> {
        self.notes.iter().filter(|n| !n.is_spent).collect()
    }

    /// Get total shielded balance.
    pub fn shielded_balance(&self) -> u64 {
        self.notes
            .iter()
            .filter(|n| !n.is_spent)
            .map(|n| n.value())
            .sum()
    }

    /// Update sync height.
    pub fn set_sync_height(&mut self, height: u32) {
        self.sync_height = height;
    }
}

impl Default for SyncState {
    fn default() -> Self {
        Self::new()
    }
}

/// Sync progress information.
#[derive(Clone, Debug)]
pub struct SyncProgress {
    /// Current block being processed.
    pub current_block: u32,
    /// Target block to sync to.
    pub target_block: u32,
    /// Number of notes found.
    pub notes_found: usize,
    /// Estimated time remaining in seconds.
    pub eta_seconds: Option<u32>,
}

impl SyncProgress {
    /// Calculate sync progress as a percentage.
    pub fn progress_percent(&self) -> f64 {
        if self.target_block == 0 {
            return 100.0;
        }
        (self.current_block as f64 / self.target_block as f64) * 100.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sync_state_new() {
        let state = SyncState::new();
        assert_eq!(state.sync_height(), 0);
        assert_eq!(state.shielded_balance(), 0);
    }

    #[test]
    fn test_sync_progress() {
        let progress = SyncProgress {
            current_block: 50,
            target_block: 100,
            notes_found: 5,
            eta_seconds: Some(60),
        };

        assert!((progress.progress_percent() - 50.0).abs() < 0.01);
    }
}
