# Stage 2 - Sapling Receive Audit

Status: Complete.

Verdict: NOT READY for external APK or TestFlight shielded receiving.

The receive path has a workable skeleton: PIVX derives Sapling addresses from the BIP39 seed, displays a default address, fetches Sapling block ranges from ElectrumX, trial-decrypts outputs through Rust FFI, persists notes, and maps shielded balance into the wallet's secondary balance fields. However, the current implementation has receive-side blockers that can miss incoming notes, compute wrong note positions/nullifiers after restart or resumed sync, expose shielded receive metadata in plaintext, and omit shielded receive history.

## Audited Paths

- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `cw_pivx/lib/src/pivx_wallet_addresses.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/lib/src/sapling/native_sapling_key_manager.dart`
- `cw_pivx/lib/src/sapling/native_shield_sync_engine.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/keys.rs`
- `lib/pivx/cw_pivx.dart`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart`
- `cw_core/lib/utils/print_verbose.dart`

## Receive Flow Observed

1. Wallet init calls `tryInitializeSapling()` after transparent wallet init.
   - `cw_pivx/lib/src/pivx_wallet.dart:117-120`
   - `cw_pivx/lib/src/pivx_wallet.dart:262-281`

2. Sapling key manager derives seed bytes from the mnemonic and initializes native keys.
   - `cw_pivx/lib/src/pivx_wallet.dart:206-258`
   - `cw_pivx/lib/src/sapling/native_sapling_key_manager.dart:22-39`
   - `cw_pivx/rust/src/keys.rs:70-98`

3. Default shielded address is set in memory as `currentShieldedAddress`.
   - `cw_pivx/lib/src/pivx_wallet.dart:230-236`
   - `cw_pivx/rust/src/ffi.rs:324-342`

4. Receive UI adds a shielded section, default shielded address, and additional stored shielded addresses.
   - `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:199-250`
   - `lib/pivx/cw_pivx.dart:57-88`

5. Shield sync uses stored `lastSyncedHeight` or activation height, fetches Sapling block ranges, trial-decrypts outputs, and stores notes.
   - `cw_pivx/lib/src/pivx_wallet.dart:473-532`
   - `cw_pivx/lib/src/sapling/sapling_factories.dart:248-389`
   - `cw_pivx/lib/src/sapling/sapling_factories.dart:395-502`
   - `cw_pivx/rust/src/ffi.rs:512-630`

6. Notes are persisted as JSON in the app documents directory.
   - `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`
   - `cw_pivx/lib/src/sapling/sapling_note_storage.dart:300-324`

## Findings

### PIVX-REC-001: Sapling tree position is not persisted globally, causing wrong nullifiers after restart/resume

Severity: Critical
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/rust/src/ffi.rs`
Code references:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:313-318`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:157-164`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:261-278`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:412-414`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:475-491`
- `cw_pivx/lib/src/pivx_wallet.dart:290-299`
- `cw_pivx/rust/src/ffi.rs:603-604`
Area: shielded receive scanning, app restart, note/nullifier handling
What is wrong:
The storage file persists notes, addresses, and `lastSyncedHeight`, but not the global Sapling commitment tree position / next output position. On sync engine initialization, `_treePosition` is reconstructed from the highest owned note position plus one. That is not the global Sapling output position because it ignores all non-owned outputs and all outputs after the last owned note. Worse, `PivxWallet._restoreNotesToNativeEngine()` creates `_shieldSyncEngine` and calls `restoreNotesFromStorage()` without calling `ShieldSyncEngineWrapper.initialize()`, so after app startup `_treePosition` can remain at its default `0` while sync resumes from `lastSyncedHeight + 1`.

Why it matters:
Sapling nullifiers depend on the note position. Rust computes `note.nf(..., position)` at receive time. If the Dart scanner supplies the wrong position, the stored nullifier and future witness/spend data can be wrong. That can make received shielded notes appear in the wallet but become unspendable or incorrectly tracked after restart/resume.

How to reproduce or verify:
1. Use a wallet with no owned notes or with an owned note before later non-owned Sapling outputs.
2. Sync to height N and restart the app.
3. Receive a new shielded note at height N+k.
4. Observe that `_treePosition` resumes from `0` or `max(ownedNote.treePosition) + 1`, not the global Sapling output count at height N.
5. Compare the wallet-computed nullifier for the received note against PIVX Core/librustpivx or a known-good wallet.

Recommended fix:
Persist and restore the global Sapling tree state/next output position independently of owned notes. On every scanned Sapling block/range, advance the global position by every Sapling output, not only owned outputs. Store that value transactionally with `lastSyncedHeight`. Always call a single initialization routine for the sync engine that restores notes and initializes the tree position before any resumed sync. Add restart/resume tests where many non-owned Sapling outputs occur between owned notes.

Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-002: Sapling RPC failures are treated as empty ranges and marked scanned

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:427-458`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:623-637`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:611-617`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:346-360`
Area: shielded receive scanning, scan ranges, server failure handling
What is wrong:
`getBlockRange()` catches all exceptions and returns an empty list. `_fetchBatchWithRetry()` can only retry thrown errors, so swallowed failures are treated as successful empty ranges. `syncBlocks()` then calls `onRangeComplete` for that range, and `startSync()` advances `lastSyncedHeight` to `rangeEnd`. A temporary server failure, unsupported method, malformed response, or timeout can therefore become a permanent scan gap.

Why it matters:
The wallet can miss incoming shielded notes and later believe those blocks were scanned. Users may see a zero or stale shielded balance even though funds were received. Recovery would require a manual rescan from before the missed range, but the app does not surface the gap.

How to reproduce or verify:
1. Mock or use an ElectrumX server where `blockchain.sapling.get_block_range` throws for a range containing a wallet note.
2. Run `syncShielded()`.
3. Confirm `SaplingNoteStorage.lastSyncedHeight` advances past the failed range.
4. Restore normal server behavior and run `syncShielded()` again.
5. Confirm the missed note is not discovered unless a rescan is manually forced from before the failed range.

Recommended fix:
Do not return `[]` for transport/protocol errors. Differentiate "valid empty range" from "failed range". Let failures throw into retry logic and fail the sync without advancing `lastSyncedHeight`. Store per-range success only after the range was fetched and processed. Add tests for transient RPC failure, unsupported Sapling RPC, malformed JSON, and empty-but-successful ranges.

Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-003: Shielded receive metadata and note plaintext are stored unencrypted in a separate JSON file

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:50-64`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:112-131`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:313-320`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:475-491`
Area: receive metadata privacy, local wallet database state, app restart behavior
What is wrong:
Received note metadata is written as plaintext JSON under `getApplicationDocumentsDirectory()`. The JSON includes value, height, txid, output index, tree position, cmu, nullifier, rseed, diversifier, pk_d, recipient address bytes, and labels/addresses. This storage path is separate from the encrypted wallet file flow used elsewhere in the wallet.

Why it matters:
Sapling receive privacy is materially weakened if local files reveal shielded receive amounts, note identifiers, wallet-owned nullifiers, and recipient metadata. Device backups, filesystem extraction, app support bundles, or malware with app data access could deanonymize shielded activity. This is not a spending-key leak by itself, but it is a serious privacy leak for a shielded wallet.

How to reproduce or verify:
1. Receive a shielded note.
2. Inspect the app documents directory for `pivx_sapling_<walletId>_mainnet.json` or `pivx_sapling_<walletId>_testnet.json`.
3. Confirm the JSON contains note plaintext fields listed above.

Recommended fix:
Store Sapling note data using the same encrypted wallet storage model as other sensitive wallet state, or encrypt the Sapling note file with a key derived from the wallet password/secure storage. Minimize persisted fields where possible. Avoid exposing nullifiers and note plaintext in backups unless encrypted. Add migration handling for existing plaintext files before external testing.

Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-004: Shielded receives are not added to transaction history

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:475-491`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:12-64`
- `cw_pivx/lib/src/pivx_wallet.dart:932-1037`
Area: receive transaction history, UI receive flow
What is wrong:
When a shielded note is found, the scanner persists a `StoredSaplingNote`, but it does not create or add a transaction-history entry. PIVX transaction history fetching is overridden only for transparent address histories using transparent script hashes. There is no parallel shielded history path from stored notes into `transactionHistory`.

Why it matters:
Users can receive shielded funds and see balance changes without a corresponding receive transaction in wallet history. Testers cannot confirm incoming shielded txid, height, confirmation status, or amount from the normal history UI. This is especially risky during APK/TestFlight testing because apparent "missing transactions" can mask scan and balance defects.

How to reproduce or verify:
1. Receive a shielded note.
2. Let shield sync complete.
3. Observe shielded balance increases.
4. Check transaction list and transaction details; the shielded receive is absent because only transparent Electrum history is fetched.

Recommended fix:
Create a PIVX shielded transaction info model or extend existing transaction history to include Sapling notes. On note discovery, persist a receive history item with txid, height, confirmations, amount, direction, pool/type, and pending/confirmed state. Ensure history survives restart and updates confirmation counts on later sync.

Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-005: Shielded receive confirmation and reorg state are not modeled

Severity: Medium
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:223-230`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:416-422`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:475-491`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:242-248`
- `cw_pivx/lib/src/pivx_wallet.dart:513-515`
- `cw_pivx/lib/src/pivx_wallet.dart:867-876`
Area: confirmation handling, pending/confirmed/spendable balances, reorg behavior
What is wrong:
The shielded balance is the sum of all unspent stored notes. `pendingBalance` always returns `0`. A found note is counted as balance as soon as it appears in scanned block data, and there is no receive-side confirmation policy, maturity/spendability threshold, rollback, or reorg invalidation. Spends/nullifiers are processed and persisted similarly without rollback support.

Why it matters:
The wallet can display shielded funds as available without indicating confirmation depth, and it has no path to remove or reclassify notes if a block is reorganized out. Testers may believe funds are final or spendable when they are not. Reorgs can leave stale notes or stale spent marks.

How to reproduce or verify:
1. Receive a shielded note in a low-confirmation block.
2. Observe `pendingShieldedBalance` remains `0` while `shieldedBalance` includes the note.
3. If test infrastructure permits, invalidate/reorg the receive block.
4. Observe no rollback path clears or reclassifies the note from storage.

Recommended fix:
Define PIVX shielded confirmation policy. Store note confirmation metadata and expose pending, confirmed, and spendable shielded balances separately. Track scanned block hashes, detect reorgs, and roll back note/nullifier state to a safe height before rescanning.

Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-REC-006: Additional shielded receive addresses can crash the receive list

Severity: Medium
Status: Confirmed
Files:
- `lib/pivx/cw_pivx.dart`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart`
Code references:
- `lib/pivx/cw_pivx.dart:80-88`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:233-245`
Area: shielded address persistence, receive UI
What is wrong:
`CWPivx.getShieldedAddresses()` returns `diversifierIndex` as an `int`, but the receive address list casts `addr['diversifierIndex'] as String` and then calls `int.parse(divIndex)`. Once a user has any stored additional shielded address, building the receive list can throw a type cast exception.

Why it matters:
Default shielded receiving may still show, but generated diversified receive addresses are a natural Sapling receive workflow. A tester who creates an additional shielded address can break the receive address list and lose access to copied addresses/labels in the UI.

How to reproduce or verify:
1. Create a PIVX wallet.
2. Generate an additional shielded address.
3. Reopen the receive address list.
4. Observe the cast from `int` to `String` at `wallet_address_list_view_model.dart:237`.

Recommended fix:
Keep `diversifierIndex` typed consistently. Either return a string from `CWPivx.getShieldedAddresses()` or read it as `int` in the receive view model. Add a widget/view-model test with at least one stored shielded address.

Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-007: Receive scan logs leak shielded metadata through unconditional logging

Severity: Medium
Status: Confirmed
Files:
- `cw_core/lib/utils/print_verbose.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_core/lib/utils/print_verbose.dart:8-18`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:178-212`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:374-377`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:444-464`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:875-896`
Area: privacy of receive metadata, logging
What is wrong:
`printV()` always prints. The Sapling receive path logs note counts, balances, found note value, height, tree position, storage note count, and partial cmu/witness metadata. These are shielded receive metadata and should not appear in release logs.

Why it matters:
Shielded receive privacy can be compromised through device logs, crash captures, support logs, or tester screenshots. Even partial identifiers plus amount/height can link wallet activity to on-chain Sapling events.

How to reproduce or verify:
1. Run a PIVX wallet with shield sync enabled.
2. Receive a shielded note.
3. Inspect app logs for `[PIVX Sapling] Found note`, storage balance, note restore, or witness messages.

Recommended fix:
Remove receive-sensitive logs or gate them behind debug-only builds and explicit opt-in redaction. Never log note amounts, nullifiers, cmu values, txids, recipient metadata, or wallet balances in release builds.

Blocks APK testing: No
Blocks TestFlight: Yes

## Non-Finding Notes

- Default shielded address derivation is deterministic from the seed and PIVX Sapling ZIP-32 path in Rust.
  - `cw_pivx/rust/src/keys.rs:70-98`
  - `cw_pivx/rust/src/keys.rs:117-120`
- Additional shielded addresses are persisted in the Sapling JSON storage, but the current-address selection is not persisted. On restart the wallet resets `currentShieldedAddress` to the default address. This is not a fund-loss issue because all diversified addresses are scanned with the same incoming viewing key, but it should be revisited in UI/UX audit.
- `PIVX-REC-001` is the most important receive-side issue because it affects note/nullifier correctness even if scanning successfully finds the note.

## Stage 2 Summary

Findings by severity:

- Critical: 1
- High: 3
- Medium: 3
- Low: 0

Top blockers:

- `PIVX-REC-001`: global tree position is not persisted/restored correctly.
- `PIVX-REC-002`: failed Sapling RPC ranges can be marked scanned.
- `PIVX-REC-003`: shielded receive metadata is persisted unencrypted.
- `PIVX-REC-004`: shielded receives are absent from transaction history.

