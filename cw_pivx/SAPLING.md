# PIVX Sapling Integration for Cake Wallet

## Overview

This document describes the Sapling shielded transaction support for PIVX in Cake Wallet. PIVX implemented the Zcash Sapling protocol to provide optional transaction privacy.

## Implementation Status

### ✅ Completed

- **Rust Native Library** (`rust/`) - Full implementation using Duddino/librustpivx
  - Key derivation (ZIP-32 HD keys)
  - Address generation and validation
  - Full viewing key export
  - FFI bindings for Dart (`cw_pivx_*` function prefix)
  - Fee estimation
  - All tests passing (16/16)

- **Dart FFI Bindings** (`lib/src/sapling/`)
  - `sapling_ffi.dart` - Complete FFI bindings to native library
  - `native_sapling_key_manager.dart` - Key management wrapper
  - `native_shield_sync_engine.dart` - Sync engine wrapper
  - `native_sapling_transaction_builder.dart` - Transaction builder wrapper
  - `sapling_factories.dart` - Factory classes for wallet integration

- **Data Models** (`lib/src/sapling/`)
  - `sapling_note.dart` - Note structures with Hive adapters
  - `sapling_constants.dart` - Network constants
  - `sapling_transaction_builder.dart` - Transaction result/option types

- **Wallet Integration** (`lib/src/pivx_wallet.dart`)
  - `shieldFunds()` - Shield transparent UTXOs to shielded address
  - `deshieldFunds()` - Deshield notes to transparent address
  - Private key retrieval for UTXO signing
  - WIF import support in wallet service

### 🔄 In Progress

- Build scripts for all platforms (iOS, Android, macOS, Linux)
- Proving parameter download mechanism

### 📋 Pending

- Full ElectrumX Sapling RPC integration for note scanning
- Commitment tree synchronization with native library
- Complete transaction building with Groth16 proofs
- Proving parameter download (sapling-spend.params, sapling-output.params)

## Architecture

### Sapling Protocol

PIVX Sapling is based on Zcash Sapling with PIVX-specific network parameters. It provides:

- **Shielded addresses**: Start with `ps` on mainnet, `ptestsapling` on testnet
- **Shielded transactions**: Zero-knowledge proofs hide sender, recipient, and amount
- **Note-based value**: Instead of UTXOs, shielded value is held in encrypted "notes"
- **Dual pools**: Transparent (like Bitcoin) and shielded pools can interoperate

### Key Hierarchy (ZIP-32)

```
BIP39 Seed (64 bytes)
└── Sapling Master Key
    └── Purpose: 32' (Sapling)
        └── Coin Type: 119' (PIVX mainnet) or 1' (testnet)
            └── Account: 0'
                ├── Extended Spending Key (can spend notes)
                └── Extended Full Viewing Key (can view transactions)
                    ├── Incoming Viewing Key (trial decryption)
                    └── Diversified Payment Addresses
```

### Network Constants

| Parameter | Mainnet | Testnet |
|-----------|---------|---------|
| Payment Address HRP | `ps` | `ptestsapling` |
| Full Viewing Key HRP | `pviews` | `pviewtestsapling` |
| Spending Key HRP | `p-secret-extended-key-main` | `p-secret-extended-key-test` |
| Sapling Activation Height | 2,700,500 | 1,164,637 |
| BIP44 Coin Type | 119 | 1 |

## Components

### 1. SaplingKeyManager (`sapling_key_manager.dart`)

Handles key derivation following ZIP-32:
- Derives spending keys from BIP39 seed
- Generates viewing keys for note scanning
- Creates diversified payment addresses

### 2. ShieldSyncEngine (`shield_sync_engine.dart`)

Manages blockchain scanning:
- Trial decryption of shielded outputs
- Commitment tree management (32-level Merkle tree)
- Incremental witness updates for spendable notes
- Nullifier tracking for spent detection

### 3. SaplingTransactionBuilder (`sapling_transaction_builder.dart`)

Builds shielded transactions:
- Selects notes to spend
- Computes anchors and witnesses
- Generates Groth16 zk-SNARK proofs
- Signs and serializes transactions

### 4. SaplingNote (`sapling_note.dart`)

Data models for notes:
- `SaplingNote`: Basic note structure (diversifier, pk_d, value, rcm)
- `SpendableNote`: Note with witness and nullifier for spending

## ElectrumX Sapling APIs

The ShieldSyncEngine uses the versioned PIVX Sapling ElectrumX v1 contract via
`PIVXSaplingElectrumX`. The reported primary contract id is
`pivx.sapling.electrumx.v1`, discovered through:

| RPC Method | Description |
|------------|-------------|
| `blockchain.sapling.capabilities` | Primary v1 capability probe for network, activation height, contract/server/Core versions, supported methods, max range, block-hash support, and structured-error support |
| `blockchain.sapling.get_block_range` | Returns a v1 envelope with `complete`, requested range metadata, `block_hashes`, and Sapling transaction blocks |
| `blockchain.sapling.get_nullifier_status` | Check if a nullifier is spent |
| `blockchain.sapling.get_commitment_info` | Get commitment details, including canonical global Sapling output position when available |
| `blockchain.sapling.get_best_anchor` | Get current anchor metadata for shielded spending |
| `blockchain.sapling.get_witness` | Get anchor-bound witness data with anchor/root, anchor height, note position, path, and commitment |

The Dart client still contains compatibility fallbacks for older method names
such as `blockchain.sapling.get_capabilities`,
`blockchain.nullifier.get_spend`, `blockchain.commitment.get_info`,
`blockchain.sapling.get_outputs_by_height`, `blockchain.sapling.get_outputs`,
`blockchain.sapling.get_anchor_height`, `blockchain.anchor.get_height`, and
`blockchain.sapling.get_tree_state`. These are compatibility paths only; they
are not sufficient release evidence for PIVX shielded support unless the node
also satisfies the v1 capability/envelope/global-position/anchor-bound witness
contract.

### Rate Limits

- `get_block_range`: Max 100 blocks per request under the reported v1 contract.
- Legacy output-range methods may advertise their own output/range limits and
  must not be treated as full v1 release readiness.

### Sync Flow

1. **Capability and checkpoint setup:**
   - Probe `blockchain.sapling.capabilities`, falling back only for legacy compatibility
   - Validate network and Sapling activation height
   - Client loads trusted local `nextTreePosition` or requires explicit server global positions

2. **Process blocks:**
   - Call `getBlockRange(checkpoint_height + 1, current_height)` in batches
   - Require complete v1 envelopes for v1 nodes and reject failed/partial ranges
   - Persist returned block hashes for the scanned range
   - Pass returned blocks to native engine for trial decryption
   - Native engine builds commitment tree and witnesses using canonical global output positions

3. **Check for spent notes:**
   - Call `getNullifierStatus(nullifier)` for each owned note

4. **Get current state:**
   - Call `getBestAnchor()` for spending proofs
   - Fetch witnesses bound to that anchor and verify returned root/height/commitment/position metadata

5. **Reorg detection:**
   - On resume, compare the last 100 scanned shielded heights against v1 `block_hashes`
   - Rewind to the last matching height and rescan when a mismatch is detected

## Native Library Requirements

Sapling cryptography requires native implementations for:

1. **Jubjub Curve Operations**: Ed25519-like curve for key operations
2. **Blake2b/Blake2s Hashing**: For commitments and nullifiers
3. **Groth16 Proving**: Zero-knowledge proof generation (~47MB spend params, ~3.5MB output params)
4. **ChaCha20-Poly1305**: Note encryption/decryption

### Recommended Approach

Use the existing [pivx-shield](https://github.com/PIVX-Labs/pivx-shield) Rust library:

```rust
// Cargo.toml dependencies
pivx_primitives = { package = "zcash_primitives", git = "...", features = [...] }
pivx_proofs = { package = "zcash_proofs", git = "..." }
sapling = { git = "..." }
```

Build native libraries using:
- **iOS/macOS**: Rust → static library → Xcode framework
- **Android**: Rust → JNI → .so library
- **Linux/Windows**: Rust → dynamic library

Dart FFI bindings via `flutter_rust_bridge` or manual `dart:ffi`.

## Usage

### Getting a Shielded Address

```dart
final wallet = PivxWallet.open(...);
await wallet.initializeSapling();
final address = await wallet.getShieldedAddress();
print('Send shielded PIV to: $address');
// Output: ps1...
```

### Checking Shielded Balance

```dart
await wallet.syncShielded(
  onProgress: (status) {
    print('Sync: ${(status.progress * 100).toInt()}%');
  },
);
print('Shielded balance: ${wallet.shieldedBalancePivx} PIV');
print('Total balance: ${wallet.totalBalancePivx} PIV');
```

### Creating a Shielded Transaction

```dart
final tx = await wallet.createShieldedTransaction(
  toAddress: 'ps1...',
  amount: 10 * 100000000, // 10 PIV in zatoshis
  memo: 'Private payment',
);
// Broadcast tx.txHex to the network
```

### Shielding Transparent Funds

```dart
// Move transparent PIV to the shielded pool
final tx = await wallet.shieldFunds(amount: 5 * 100000000);
```

### Deshielding to Transparent

```dart
// Move shielded PIV back to transparent
final tx = await wallet.deshieldFunds(
  amount: 3 * 100000000,
  toAddress: 'D...', // Optional, defaults to own address
);
```

## Transaction Types

| Type | Description | Privacy |
|------|-------------|---------|
| t→t | Transparent to transparent | None (all public) |
| t→z | Shield (transparent to shielded) | Hides recipient and amount |
| z→z | Fully shielded | Full privacy |
| z→t | Deshield (shielded to transparent) | Reveals amount |

## Fee Calculation

Sapling transactions use size-based fees:

```dart
fee = feePerByte * (
  txOverhead +
  (saplingInputs * 384) +  // Spend size
  (saplingOutputs * 948) + // Output size
  (transparentInputs * 150) +
  (transparentOutputs * 34)
)
```

Default fee rate: 1000 satoshis/byte

## Proving Parameters

Sapling proofs require two parameter files:

| File | Size | Hash (SHA256) |
|------|------|---------------|
| sapling-spend.params | 47,958,396 bytes | `8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13` |
| sapling-output.params | 3,592,860 bytes | `2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4` |

Downloaded from the configured PIVX-hosted URLs:
- `https://duddino.com/sapling-spend.params`
- `https://duddino.com/sapling-output.params`

## Security Considerations

1. **Spending Key Protection**: The extended spending key must be stored encrypted
2. **Witness Updates**: Witnesses must be kept updated with new blocks
3. **Nullifier Privacy**: Nullifiers reveal which notes are spent (but not to whom)
4. **Anchor Selection**: Use recent anchors (within ~100 blocks) for transactions
5. **Memo Privacy**: Memos are encrypted but recipients can see them

## Implementation Status

| Component | Status |
|-----------|--------|
| Sapling Constants | ✅ Complete |
| Data Models (Hive) | ✅ Complete |
| Key Manager Interface | ✅ Complete |
| Sync Engine Interface | ✅ Complete |
| Transaction Builder Interface | ✅ Complete |
| PivxWallet Integration | ✅ Complete |
| Native Rust Library | ✅ Complete |
| FFI Bindings (Dart) | ✅ Complete |
| Build Scripts (iOS) | ✅ Complete |
| Build Scripts (Android) | ✅ Complete |
| Build Scripts (macOS/Linux) | ✅ Complete |
| Native Impl: Key Manager | ✅ Complete |
| Native Impl: Sync Engine | 🔲 Partial |
| Native Impl: Tx Builder | 🔲 Partial |

## Building the Native Library

### Prerequisites

1. **Rust toolchain**: Install via [rustup](https://rustup.rs/)
2. **Platform-specific tools**:
   - iOS: Xcode Command Line Tools
   - Android: Android NDK (set `ANDROID_NDK_HOME`)
   - macOS: Xcode
   - Linux: gcc/clang

### Build Commands

```bash
# Navigate to cw_pivx
cd cw_pivx

# Build for all platforms (on macOS)
bash scripts/build_all.sh

# Or build for specific platforms
bash scripts/build_ios.sh
bash scripts/build_android.sh
bash scripts/build_macos.sh
bash scripts/build_linux.sh
```

### Output Locations

| Platform | Output |
|----------|--------|
| iOS | `ios/Frameworks/cw_pivx_sapling.xcframework` |
| Android | `android/src/main/jniLibs/{arch}/libcw_pivx_sapling.so` |
| macOS | `macos/Frameworks/libcw_pivx_sapling.dylib` |
| Linux | `linux/libcw_pivx_sapling.so` |

### Runtime Native Self-Test

Run the Dart native self-test after rebuilding artifacts and before packaging:

```bash
fvm dart run tool/pivx_sapling_native_self_test.dart
```

To verify a specific rebuilt artifact:

```bash
PIVX_SAPLING_LIBRARY_PATH=/absolute/path/to/libcw_pivx_sapling.dylib \
  fvm dart run tool/pivx_sapling_native_self_test.dart
```

Expected result: `passed: true`, `loaded: true`, `symbols_ready: true`,
and `fee_matches_policy: true`. A fee mismatch means the native artifact is
stale relative to the Core-derived Dart/Rust fee policy and must be rebuilt.

## References

- [PIVX Sapling Documentation](https://docs.pivx.org/)
- [Zcash Sapling Protocol](https://zips.z.cash/protocol/sapling.pdf)
- [ZIP-32: Shielded Hierarchical Deterministic Wallets](https://zips.z.cash/zip-0032)
- [pivx-shield Library](https://github.com/PIVX-Labs/pivx-shield)
- [MyPIVXWallet (Reference)](https://github.com/PIVX-Labs/MyPIVXWallet)
