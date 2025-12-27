/// PIVX Sapling shielded transaction support.
/// 
/// This library provides full Sapling protocol support for PIVX including:
/// - Shielded addresses (ps1... format)
/// - Shielded transactions (z-to-z, t-to-z, z-to-t)
/// - Note scanning and balance tracking
/// - Privacy-preserving payments
/// 
/// ## Overview
/// 
/// PIVX implemented the Zcash Sapling protocol to provide optional privacy
/// for transactions. Sapling uses zk-SNARKs (Zero-Knowledge Succinct 
/// Non-Interactive Arguments of Knowledge) to prove transaction validity
/// without revealing sender, recipient, or amount.
/// 
/// ## Key Concepts
/// 
/// ### Shielded Pool
/// The shielded pool is a separate value pool from transparent PIV. Value
/// can be moved between pools through shielding (t→z) and deshielding (z→t)
/// transactions.
/// 
/// ### Notes
/// In Sapling, value is held in "notes" rather than UTXOs. Each note:
/// - Is encrypted to a specific payment address
/// - Contains a value and optional memo
/// - Has a unique nullifier that's revealed when spent
/// - Requires the spending key to spend
/// 
/// ### Keys
/// Sapling uses a hierarchy of keys:
/// - Spending Key: Full control (can spend notes)
/// - Full Viewing Key: Can see incoming and outgoing transactions
/// - Incoming Viewing Key: Can only see incoming transactions
/// - Payment Addresses: Can receive notes (unlimited addresses from one key)
/// 
/// ### Proofs
/// Sapling transactions include zero-knowledge proofs:
/// - Spend Proof: Proves authority to spend without revealing the note
/// - Output Proof: Proves the output is correctly constructed
/// 
/// ## Usage
/// 
/// ```dart
/// import 'package:cw_pivx/src/sapling/sapling.dart';
/// 
/// // Create a Sapling wallet from BIP39 seed
/// final seed = bip39.mnemonicToSeed(mnemonic);
/// final saplingWallet = await PivxSaplingWallet.create(
///   seed: Uint8List.fromList(seed),
///   isTestnet: false,
/// );
/// 
/// // Get a shielded address
/// final address = await saplingWallet.getAddress();
/// print('Send shielded PIV to: ${address.encoded}');
/// 
/// // Sync and check balance
/// await saplingWallet.sync();
/// print('Shielded balance: ${saplingWallet.balance} PIV');
/// 
/// // Send a shielded transaction
/// final tx = await saplingWallet.createTransaction(
///   toAddress: 'ps1...',
///   amount: 10 * 100000000, // 10 PIV in zatoshis
///   memo: 'Private payment',
/// );
/// await broadcastTransaction(tx.txHex);
/// ```
/// 
/// ## Implementation Notes
/// 
/// This library requires native cryptographic implementations for:
/// - Jubjub curve operations (for key derivation)
/// - Blake2b/Blake2s hashing (for commitments)
/// - Groth16 proof generation (for zk-SNARKs)
/// - ChaCha20-Poly1305 encryption (for note encryption)
/// 
/// These are provided through FFI bindings to:
/// - pivx-shield (Rust library, WASM for web)
/// - librustpivx (Fork of librustzcash with PIVX parameters)
library sapling;

// Core constants and interfaces
export 'sapling_constants.dart';
export 'sapling_key_manager.dart';
export 'sapling_note.dart';
export 'sapling_transaction_builder.dart';
export 'shield_sync_engine.dart' hide CommitmentInfo;

// Native FFI implementations
export 'sapling_ffi.dart';
export 'native_sapling_key_manager.dart';
export 'native_shield_sync_engine.dart';
export 'native_sapling_transaction_builder.dart';

// ElectrumX Sapling API client
export 'pivx_sapling_electrumx.dart';

// Note: sapling_factories.dart provides wallet-level wrappers
// and should be imported directly where needed to avoid conflicts
