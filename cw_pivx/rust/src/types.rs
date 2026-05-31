//! Common types used across the library.

use serde::{Deserialize, Serialize};

/// Network type for PIVX
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(C)]
pub enum Network {
    Mainnet = 0,
    Testnet = 1,
}

impl Network {
    pub fn coin_type(&self) -> u32 {
        match self {
            Network::Mainnet => 119,
            Network::Testnet => 1,
        }
    }

    pub fn hrp_sapling_payment_address(&self) -> &'static str {
        match self {
            Network::Mainnet => "ps",
            Network::Testnet => "ptestsapling",
        }
    }

    pub fn hrp_sapling_extended_spending_key(&self) -> &'static str {
        match self {
            Network::Mainnet => "p-secret-extended-key-main",
            Network::Testnet => "p-secret-extended-key-test",
        }
    }

    pub fn hrp_sapling_extended_full_viewing_key(&self) -> &'static str {
        match self {
            Network::Mainnet => "pviews",
            Network::Testnet => "pviewtestsapling",
        }
    }

    pub fn hrp_sapling_incoming_viewing_key(&self) -> &'static str {
        match self {
            Network::Mainnet => "pivks",
            Network::Testnet => "pivktestsapling",
        }
    }

    pub fn sapling_activation_height(&self) -> u32 {
        match self {
            Network::Mainnet => 2_700_500,
            Network::Testnet => 201,
        }
    }
}

impl From<bool> for Network {
    fn from(is_testnet: bool) -> Self {
        if is_testnet {
            Network::Testnet
        } else {
            Network::Mainnet
        }
    }
}

/// Represents a spendable note with all required data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpendableNoteData {
    /// Diversifier (11 bytes, hex encoded)
    pub diversifier: String,
    /// Diversified transmission key pk_d (32 bytes, hex encoded)
    pub pk_d: String,
    /// Note value in zatoshis
    pub value: u64,
    /// Commitment randomness (32 bytes, hex encoded)
    pub rcm: String,
    /// Note randomness seed (32 bytes, hex encoded)
    pub rseed: String,
    /// Incremental witness path (hex encoded concatenated 32-byte hashes)
    pub witness: String,
    /// Position in the commitment tree (from witness response)
    #[serde(default)]
    pub witness_position: u64,
    /// Nullifier (32 bytes, hex encoded)
    pub nullifier: String,
    /// Note commitment (cmu) for validation
    #[serde(default)]
    pub cmu: Option<String>,
    /// Optional memo
    pub memo: Option<String>,
}

/// Result of creating a transaction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionResult {
    /// Transaction ID
    pub txid: String,
    /// Signed transaction as hex
    pub tx_hex: String,
    /// Nullifiers of spent notes
    pub nullifiers: Vec<String>,
    /// Transaction fee in zatoshis
    pub fee: u64,
}

/// Transparent UTXO for shielding transactions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransparentUtxoData {
    /// Transaction ID
    pub txid: String,
    /// Output index
    pub vout: u32,
    /// Value in zatoshis
    pub value: u64,
    /// Script pubkey (hex encoded)
    pub script_pubkey: String,
    /// Private key (WIF or hex)
    pub private_key: String,
}

/// Options for creating a transaction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionOptions {
    /// Destination address (shielded or transparent)
    pub to_address: String,
    /// Amount in zatoshis
    pub amount: u64,
    /// Optional memo (max 512 bytes)
    pub memo: Option<String>,
    /// Change address (defaults to own shielded address)
    pub change_address: Option<String>,
    /// Current block height
    pub block_height: u32,
}

/// Sync status information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStatus {
    /// Last synced block height
    pub last_synced_block: u32,
    /// Current chain tip
    pub current_block: u32,
    /// Sync progress (0.0 to 1.0)
    pub progress: f32,
    /// Whether sync is in progress
    pub is_syncing: bool,
    /// Error message if any
    pub error: Option<String>,
}
