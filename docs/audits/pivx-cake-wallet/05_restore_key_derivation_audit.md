# Stage 5 - Restore And Key Derivation Audit

Status: Complete.

Verdict: NOT READY for external APK or TestFlight PIVX restore/key-derivation coverage.

PIVX seed creation and seed restore use BIP39 seed material consistently for both transparent and Sapling account-0 derivation. Transparent addresses are derived as P2PKH from `m/44'/119'/0'/change/index`, and Sapling keys are derived from the same BIP39 seed through Rust ZIP-32 at `m/32'/119'/0'`. The default shielded address is deterministic across create/open/restore when the same seed and passphrase are used.

The release-blocking concerns are around recovery coverage and secret handling: invalid seed restore can log and surface the full mnemonic, WIF/private-key recovery for old transparent funds is unavailable, transparent gap discovery can stop too early, PIVX has no restore birthday/height UX, derivation/account choice is hard-coded, seed restore does not reconstruct prior diversified shielded address state, and one FFI seed copy is freed without being wiped.

## Files Reviewed

- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pivx_wallet_addresses.dart`
- `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart`
- `cw_pivx/lib/src/pivx_network.dart`
- `cw_pivx/lib/src/sapling/native_sapling_key_manager.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/rust/src/keys.rs`
- `cw_pivx/rust/src/ffi.rs`
- `cw_bitcoin/lib/electrum_wallet.dart`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart`
- `cw_core/lib/wallet_keys_file.dart`
- `cw_core/lib/encryption_file_utils.dart`
- `lib/pivx/cw_pivx.dart`
- `lib/view_model/wallet_creation_vm.dart`
- `lib/view_model/wallet_new_vm.dart`
- `lib/view_model/wallet_restore_view_model.dart`
- `lib/src/screens/restore/wallet_restore_page.dart`

## Audited Flow Summary

1. New PIVX wallets are created from a caller-supplied mnemonic or a generated BIP39 mnemonic.
   - `cw_pivx/lib/src/pivx_wallet_service.dart:34-49`
   - `lib/view_model/wallet_new_vm.dart:123-129`

2. Wallet keys are saved through the shared encrypted `.keys` file path, while transaction/address state is saved through the encrypted wallet snapshot path.
   - `cw_bitcoin/lib/electrum_wallet.dart:1539-1547`
   - `cw_core/lib/wallet_keys_file.dart:23-48`
   - `cw_core/lib/encryption_file_utils.dart:6-41`

3. Transparent PIVX derivation is hard-coded to BIP44 account 0.
   - `cw_bitcoin/lib/electrum_wallet.dart:119-163`
   - `cw_pivx/lib/src/pivx_wallet_addresses.dart:38-44`

4. Seed restore validates BIP39, creates a wallet from the same seed/passphrase path, and initializes transparent plus Sapling state.
   - `cw_pivx/lib/src/pivx_wallet_service.dart:163-182`
   - `cw_pivx/lib/src/pivx_wallet.dart:1067-1097`
   - `cw_pivx/lib/src/pivx_wallet.dart:202-258`

5. Sapling keys are derived from the BIP39 seed in Dart, passed to Rust over FFI, and used to derive account-0 extended spending/viewing keys and payment addresses.
   - `cw_pivx/lib/src/pivx_wallet.dart:215-227`
   - `cw_pivx/lib/src/sapling/sapling_ffi.dart:525-545`
   - `cw_pivx/rust/src/ffi.rs:261-305`
   - `cw_pivx/rust/src/keys.rs:70-98`

6. Shielded restore scans Sapling blocks from stored `lastSyncedHeight` or activation height, trial-decrypts outputs, stores found notes, and restores stored notes into the native engine on startup.
   - `cw_pivx/lib/src/sapling/sapling_factories.dart:248-389`
   - `cw_pivx/lib/src/sapling/sapling_factories.dart:391-502`
   - `cw_pivx/lib/src/pivx_wallet.dart:260-305`

## Findings

### PIVX-KEY-001: Invalid mnemonic handling leaks the full seed phrase

Severity: Critical
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `lib/view_model/wallet_creation_vm.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet_service.dart:167-169`
- `lib/view_model/wallet_creation_vm.dart:137-145`
Area: seed restore, key leakage in logs/errors
What is wrong:
PIVX seed restore throws `Exception('Invalid mnemonic: ${credentials.mnemonic}')` when BIP39 validation fails. The shared wallet creation flow catches the exception, logs `error: $e`, and stores the exception string in `FailureState`.
Why it matters:
An incorrectly entered seed can be written to device logs and surfaced through UI/error plumbing. A near-correct seed is still sensitive key material; logging it materially compromises the wallet if logs, crash reports, support bundles, or screen captures are exposed.
How to reproduce or verify:
Enter an invalid PIVX seed phrase during restore and inspect app logs for `error: Invalid mnemonic: ...`.
Recommended fix:
Never interpolate seed text into exceptions. Throw a typed/sanitized invalid-mnemonic error and ensure restore UI/logging displays only generic validation failure text.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-002: WIF/private-key restore is unavailable for old transparent funds

Severity: High
Status: Confirmed
Files:
- `lib/view_model/wallet_restore_view_model.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart`
Code references:
- `lib/view_model/wallet_restore_view_model.dart:63-69`
- `cw_pivx/lib/src/pivx_wallet_service.dart:134-159`
- `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart:40-53`
Area: recovery of old transparent funds, seed restore, restore from keys
What is wrong:
The restore UI exposes only seed mode for PIVX, and the PIVX service's WIF restore method validates prefixes but then throws `UnimplementedError`.
Why it matters:
Users with old transparent PIVX funds controlled by standalone WIF/private keys cannot recover or sweep those funds in the app. This is a direct recovery gap for pre-HD, imported-key, or exported-key users.
How to reproduce or verify:
Open PIVX restore and observe that only seed restore is available. Calling `restoreFromKeys` with a valid PIVX WIF reaches the unimplemented error.
Recommended fix:
Add an explicit WIF sweep/import flow or clearly block it with migration guidance. Prefer sweeping into the deterministic wallet so restored funds become part of the seed-backed address set.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-003: Transparent restore discovery can stop after one extra gap batch

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:940-981`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart:612-624`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart:627-655`
Area: transparent derivation, address discovery, recovery of old transparent funds
What is wrong:
PIVX transparent restore starts with 22 receive and 17 change P2PKH addresses, then asks the shared discovery helper for another gap batch when a used address appears near the tail. The helper checks `addressesWithHistory.last == addressList.last.address`, comparing the last newly checked result to the previous address list tail instead of the last newly generated address. This prevents recursive extension beyond one added batch.
Why it matters:
Transparent funds beyond the initial window plus one extra batch can be missed during seed restore. Heavy users, migrated wallets, or wallets with many generated/unused addresses can restore a seed and see an incomplete balance/history.
How to reproduce or verify:
Create PIVX activity beyond the first generated recovery window, especially past the first added discovery batch, then restore from seed and compare recovered addresses/history to a full derivation scan.
Recommended fix:
Fix the discovery termination condition to test whether the last newly generated address has history, and keep extending until a full unused gap is proven. Add PIVX restore tests for receive and change addresses beyond multiple gap windows.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-004: PIVX derivation is hard-coded to account 0 with no derivation/account recovery choice

Severity: High
Status: Confirmed
Files:
- `cw_bitcoin/lib/electrum_wallet.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/rust/src/keys.rs`
- `lib/view_model/wallet_creation_vm.dart`
Code references:
- `cw_bitcoin/lib/electrum_wallet.dart:119-163`
- `cw_pivx/lib/src/pivx_wallet.dart:1067-1097`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:23-33`
- `cw_pivx/rust/src/keys.rs:75-88`
- `lib/view_model/wallet_creation_vm.dart:148-179`
Area: transparent derivation, shielded derivation, address determinism, old-funds recovery
What is wrong:
Transparent PIVX uses `m/44'/119'/0'` unconditionally, and Sapling uses `m/32'/119'/0'` unconditionally. `SaplingKeyManagerFactory.create()` accepts `accountIndex` but ignores it, while the restore/create derivation model falls back to `DerivationType.unknown` for PIVX and offers no PIVX derivation chooser.
Why it matters:
Funds in non-zero accounts, alternate legacy paths, or another wallet's PIVX-compatible path will not be found from seed. The UI also cannot detect or explain this, so users may believe their seed is empty.
How to reproduce or verify:
Put funds on PIVX account 1 or a legacy/imported derivation path, restore the seed in Cake Wallet, and observe that only account 0 addresses are derived/scanned.
Recommended fix:
Define the supported PIVX derivation matrix, persist explicit PIVX derivation metadata, implement account/path selection or detection, and make the Sapling `accountIndex` parameter functional if multiple shielded accounts are supported.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-005: PIVX seed restore has no restore birthday/height control

Severity: Medium
Status: Confirmed
Files:
- `lib/view_model/wallet_restore_view_model.dart`
- `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart`
- `lib/view_model/wallet_creation_vm.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `lib/view_model/wallet_restore_view_model.dart:89-93`
- `lib/view_model/wallet_restore_view_model.dart:168-174`
- `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart:23-38`
- `lib/view_model/wallet_creation_vm.dart:111-123`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:261-278`
Area: seed restore, restore scan behavior, old shielded funds recovery
What is wrong:
The restore height selector is not enabled for PIVX, and PIVX restore credentials do not carry a height/birthday. On a fresh restore, shielded scanning falls back to Sapling activation height; transparent recovery uses address-history queries but no user-selected restore birthday.
Why it matters:
For modern wallets, restore can require an unnecessarily large shielded scan. For future birthday support, a wrong height could miss old shielded funds unless the UI and scanner clearly distinguish "wallet creation birthday" from "rescan from activation".
How to reproduce or verify:
Open the PIVX seed restore flow and confirm there is no height/date field. Restore a seed with no existing Sapling storage and observe shield sync starting from activation height.
Recommended fix:
Add PIVX-specific restore birthday UX with safe defaults. For shielded restores, never start after the wallet's first possible shielded receive unless the user explicitly accepts the risk. Persist and display the chosen restore height.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-KEY-006: Seed restore can reuse prior diversified shielded addresses

Severity: Medium
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:230-236`
- `cw_pivx/lib/src/pivx_wallet.dart:411-455`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:221-240`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:396-418`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:116-129`
Area: shielded derivation, address determinism, seed restore, recovery of old shielded funds
What is wrong:
Additional diversified shielded addresses and `nextDiversifierIndex` are local storage state, not seed-reconstructed restore state. A seed-only restore initializes the default address and an empty Sapling storage file with `nextDiversifierIndex = 1`, so the first newly generated shielded address can repeat an address that was generated in the old wallet.
Why it matters:
Funds sent to old diversified addresses can still be found by scanning with the viewing key, but the restored receive UI loses address labels/current address state and may reuse old diversified addresses, weakening address hygiene and user expectations around "new" receive addresses.
How to reproduce or verify:
Generate shielded address index 1, back up only the seed, restore into a fresh wallet, then generate a new shielded address. It will derive index 1 again.
Recommended fix:
On restore, reconstruct or advance shielded address state from discovered note diversifiers where possible, let users set/advance the next diversifier index, and avoid labeling repeated diversified addresses as new.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-KEY-007: Sapling FFI seed copy is freed without being zeroed

Severity: Medium
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/keys.rs`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:220-256`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:525-545`
- `cw_pivx/rust/src/ffi.rs:261-305`
- `cw_pivx/rust/src/keys.rs:191-246`
Area: seed phrase creation, spending keys, secure storage, key material in memory
What is wrong:
`PivxWallet.initializeSapling()` zeroes the Dart `saplingSeeds` buffer after FFI initialization, but `SaplingKeys.fromSeed()` copies the same seed into a `malloc` buffer and frees that pointer without overwriting it. Rust also keeps the derived Sapling key manager in global process state until disposed, with best-effort zeroing only on drop.
Why it matters:
The BIP39 seed can remain in freed native heap memory until overwritten. This is not a normal application-level leak, but it weakens key-handling guarantees for a wallet handling spending keys.
How to reproduce or verify:
Inspect `SaplingKeys.fromSeed()` and confirm `seedPtr.asTypedList(...).setAll(...)` is followed by `malloc.free(seedPtr)` without a wipe. Memory-forensics verification would require a specialized test harness.
Recommended fix:
Overwrite the native seed buffer before `malloc.free`, use zeroizing/secure allocation helpers for seed material, and audit Rust key-drop behavior with `zeroize`/volatile writes where compatible.
Blocks APK testing: No
Blocks TestFlight: Yes

## Cross-Stage Recovery Dependencies

Stage 5 recovery depends on several earlier blockers:

- `PIVX-REC-001`: restored shielded notes require correct global positions/nullifiers.
- `PIVX-REC-002`: failed shielded scan ranges must not be marked scanned during restore.
- `PIVX-REC-003`: shielded restore state is currently plaintext local JSON, including note data needed after restart.
- `PIVX-BAL-002`: restarted/restored balances can include notes that were not restored into the native engine for spending.
- `PIVX-BAL-006`: stale shielded balance can survive failed sync/rescan paths.

## Required Test Coverage Before External Builds

- Invalid PIVX seed restore must not log or display entered seed text.
- Same seed/passphrase must reproduce transparent address index 0 and default shielded address exactly.
- Different passphrases must produce different transparent and shielded addresses.
- Transparent restore must recover receive/change funds across multiple address-gap windows.
- WIF/private-key recovery must be implemented as sweep/import or explicitly unavailable with user-safe migration guidance.
- Shielded restore must recover old received and later-spent notes from activation/birthday scan with correct nullifiers.
- Seed-only restore after prior diversified shielded address generation must not silently reuse "new" receive addresses.
- Sapling seed buffers must be wiped on Dart and FFI allocation paths.
