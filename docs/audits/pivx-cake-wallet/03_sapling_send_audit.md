# Stage 3 - Sapling Send Audit

Status: Complete.

Date: 2026-05-27

Scope: shielded sending and related transaction construction/broadcast state only. This pass did not audit general balance correctness beyond send-specific implications, and did not modify production code.

## Verdict

Shielded sending is NOT READY for external APK or TestFlight testing.

Only shielded-to-shielded has a concrete transaction-building path, and even that path is blocked by critical spendability risks inherited from receive-state handling plus multiple send-specific issues. Transparent-to-shielded and shielded-to-transparent are explicitly unimplemented. The current send flow also lacks local nullifier reservation/pending state, has broken send-all behavior for shielded mode, can mismatch anchors and witnesses, and has no repository evidence that the custom PIVX Sapling serialization/sighash is accepted by PIVX Core/testnet.

## Findings Summary

- Critical: 1
- High: 6
- Medium: 2
- Low: 0

## Audited Files

- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/transaction.rs`
- `cw_pivx/rust/tests/testnet_integration.rs`
- `lib/view_model/send/send_view_model.dart`
- `lib/view_model/send/output.dart`
- `lib/src/screens/send/widgets/send_card.dart`
- `lib/bitcoin/cw_bitcoin.dart`

## Send Flow Map

High-level UI flow:

- `lib/src/screens/send/widgets/send_card.dart:763-789` exposes a PIVX "Send from shielded balance" checkbox.
- `lib/view_model/send/send_view_model.dart:172-180` stores shielded mode as `UnspentCoinType.sapling`.
- `lib/view_model/send/send_view_model.dart:918-924` passes `coinTypeToSpendFrom` into Bitcoin transaction credentials for PIVX.
- `cw_pivx/lib/src/pivx_wallet.dart:1191-1205` routes to Sapling only when any destination address looks shielded.
- `cw_pivx/lib/src/pivx_wallet.dart:1213-1275` builds a Sapling pending transaction only for one shielded output.

Concrete z-to-z path:

- `cw_pivx/lib/src/pivx_wallet.dart:620-653` creates a shielded transaction under `_balanceLock`.
- `cw_pivx/lib/src/sapling/sapling_factories.dart:717-808` selects notes, estimates fee, fetches witnesses, gets an anchor, and calls FFI.
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:454-514` calls `cw_pivx_build_shielded_tx`.
- `cw_pivx/rust/src/ffi.rs:1123-1395` parses note JSON, witness paths, recipient, anchor, memo, and builds the transaction.
- `cw_pivx/rust/src/transaction.rs:284-435` builds and signs the Sapling bundle.
- `cw_pivx/rust/src/transaction.rs:451-565` manually serializes the PIVX Sapling transaction.
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:61-86` broadcasts the raw hex through Electrum.

Unsupported paths:

- `cw_pivx/lib/src/sapling/sapling_factories.dart:910-930` throws `UnimplementedError` for shielding and deshielding.
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart:57-127` also throws `UnimplementedError` for shielding and deshielding.
- `cw_pivx/lib/src/pivx_wallet.dart:1263-1275` rejects direct transparent-to-external-shielded sends.

## Findings

### PIVX-SEND-001: Shielded spend construction depends on unverified note positions/nullifiers from receive state

Severity: Critical
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/transaction.rs`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:158-166`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:140-152`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:736-745`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:831-907`
- `cw_pivx/rust/src/ffi.rs:1284-1327`
- `cw_pivx/rust/src/transaction.rs:345-349`
Area: note/nullifier handling, witness handling, spend authorization
What is wrong:
The z-to-z send path spends notes restored from local receive storage and accepts the stored note/nullifier data plus ElectrumX witness position without an independent local commitment tree verification step. This compounds Stage 2 finding `PIVX-REC-001`: if receive scanning persisted the wrong global tree position, the restored nullifier and witness context can be wrong. The Rust spend builder then reconstructs notes, uses `witness_position`, parses the witness, and signs spends from that data.
Why it matters:
A shielded wallet can show funds that cannot be spent after restart/resume, or build transactions that fail proof/signature/consensus validation. For users, this is likely stuck or unrecoverable shielded funds until a corrected rescan/reindex path exists.
How to reproduce or verify:
Receive multiple shielded notes across blocks containing unrelated Sapling outputs, restart the app, restore notes from storage, then attempt a z-to-z spend. Compare the wallet's stored `treePosition` and nullifier against a PIVX Core/indexer-derived global note position and nullifier.
Recommended fix:
Fix receive-side global commitment tree position tracking first. Before signing, validate every selected note against an authenticated anchor/witness source and recompute/verify nullifiers from canonical note position. Add spend tests using known notes, anchors, witnesses, and expected nullifiers.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-002: Transparent-to-shielded and shielded-to-transparent sends are not implemented

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart`
- `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:663-727`
- `cw_pivx/lib/src/pivx_wallet.dart:737-759`
- `cw_pivx/lib/src/pivx_wallet.dart:1263-1275`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:910-930`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart:57-127`
- `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart:214-236`
Area: transaction construction, transparent-to-shielded, shielded-to-transparent, unsupported flow blocking
What is wrong:
The public wallet comments and builder interfaces describe shielding and deshielding, but both concrete builders throw `UnimplementedError`. The normal send route also rejects direct transparent-to-external-shielded sends.
Why it matters:
Users cannot reliably enter or exit the shielded pool through the app. Shielded funds received into the wallet may be impossible to move back to a transparent address, and transparent users cannot send directly to a shielded recipient.
How to reproduce or verify:
Call `shieldFunds`, `deshieldFunds`, or attempt to send to a shielded recipient with only transparent balance. The code reaches explicit unsupported exceptions.
Recommended fix:
Either implement and test t-to-z and z-to-t transaction construction, or remove/block those flows in UI and release notes until implemented. Do not advertise shield/deshield support until raw transactions are accepted on PIVX testnet.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-003: Shielded mode with a transparent destination falls through to transparent sending

Severity: High
Status: Confirmed
Files:
- `lib/src/screens/send/widgets/send_card.dart`
- `lib/view_model/send/send_view_model.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `lib/bitcoin/cw_bitcoin.dart`
Code references:
- `lib/src/screens/send/widgets/send_card.dart:763-789`
- `lib/view_model/send/send_view_model.dart:172-180`
- `lib/view_model/send/send_view_model.dart:918-924`
- `cw_pivx/lib/src/pivx_wallet.dart:1191-1205`
- `lib/bitcoin/cw_bitcoin.dart:268-284`
Area: shielded-to-transparent, UI send flow, unsupported flow blocking
What is wrong:
The routing decision checks only whether the destination address is shielded. If the user enables "Send from shielded balance" and enters a transparent PIVX address, `PivxWallet.createTransaction` falls back to the parent transparent transaction builder. `coinTypeToSpendFrom == sapling` is not used to select a z-to-t path.
Why it matters:
The UI can imply a shielded spend while the wallet attempts a transparent spend. Depending on UTXO availability and validation behavior, this can fail confusingly or spend from the wrong pool.
How to reproduce or verify:
Open a PIVX wallet with shielded balance, enable "Send from shielded balance", enter a transparent address, and create the transaction. The PIVX Sapling builder is not selected unless the output address itself is shielded.
Recommended fix:
Route on both source pool and destination type. Explicitly block z-to-t until implemented, and show a clear user-facing unsupported-flow error before transaction creation.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-004: Broadcast does not reserve or mark spent shielded notes locally

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `lib/view_model/send/send_view_model.dart`
Code references:
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:61-86`
- `cw_pivx/lib/src/pivx_wallet.dart:1252-1260`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:351-377`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:416-422`
- `lib/view_model/send/send_view_model.dart:822-840`
Area: local pending state, duplicate send prevention, app killed/backgrounded during send
What is wrong:
After broadcast, the pending transaction wrapper only calls `updateBalance()` and `syncShielded()`. It does not persist a pending outgoing shielded transaction, reserve selected nullifiers, or mark selected notes as pending spent. Notes are marked spent only when a later scanned block reveals a matching nullifier.
Why it matters:
Until the spend is mined and rescanned, the wallet can continue showing the spent notes as available and can build another transaction from the same notes. If the app is killed after broadcast but before a confirming scan, there is no durable pending outgoing state.
How to reproduce or verify:
Create and broadcast a z-to-z transaction, then immediately inspect `SaplingNoteStorage` or attempt another shielded spend before the spending nullifier appears in scanned blocks.
Recommended fix:
Return selected nullifiers from the builder, persist an outgoing pending transaction record before broadcast, mark selected notes as pending spent on successful broadcast, and reconcile them to confirmed spent or available based on later chain state/broadcast failure.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-005: Shielded send-max is broken and fee-aware note selection is incomplete

Severity: High
Status: Confirmed
Files:
- `lib/src/screens/send/widgets/send_card.dart`
- `lib/view_model/send/output.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/transaction.rs`
Code references:
- `lib/src/screens/send/widgets/send_card.dart:522-523`
- `lib/src/screens/send/widgets/send_card.dart:849-850`
- `lib/view_model/send/output.dart:101-158`
- `cw_pivx/lib/src/pivx_wallet.dart:1221-1224`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:744-760`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:810-829`
- `cw_pivx/rust/src/ffi.rs:170-178`
- `cw_pivx/rust/src/transaction.rs:321-327`
Area: fee calculation, send max, insufficient funds, note selection
What is wrong:
The send-all button sets the visible crypto amount to localized text (`S.current.all`), but PIVX amount parsing catches parse failures and returns `0`. That zero amount is then used by the PIVX send path and rejected by FFI. Separately, note selection selects notes until `total >= amount`, calculates the fee afterward, and fails if `total < amount + fee` instead of selecting more notes. It also does not proactively handle change below the Rust dust threshold.
Why it matters:
Shielded send-max is not usable, and valid sends can fail with "Insufficient balance after fee" even when additional notes are available. Users may be unable to spend exact or near-full shielded balances.
How to reproduce or verify:
Use PIVX shielded mode, press Send all, and attempt to create a z-to-z transaction. Also test notes `[100, 20]`, amount `100`, fee `30`: selection can choose only the 100 note and fail even though total wallet balance can cover amount plus fee.
Recommended fix:
Implement a PIVX Sapling-specific send-max calculation that subtracts the actual selected-note fee and handles dust/change. Make note selection fee-aware and iterative: select notes for amount plus estimated fee, recompute fee when note/output counts change, and either absorb dust into fee or select/change according to protocol policy.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-006: Witnesses and anchor can be fetched from different chain states

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/rust/src/ffi.rs`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:764-772`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:831-907`
- `cw_pivx/rust/src/ffi.rs:1261-1278`
- `cw_pivx/rust/src/ffi.rs:1323-1327`
Area: witness handling, anchor handling, transaction construction
What is wrong:
`buildTransaction` calls `_fetchWitnesses`, and `_fetchWitnesses` calls `getBestAnchor()` internally. After witnesses are fetched, `buildTransaction` calls `getBestAnchor()` a second time and passes that later anchor into FFI. There is no check that the witness response anchor matches the anchor used for signing.
Why it matters:
Sapling spend proofs require the witness path to correspond to the transaction anchor. If the best anchor changes or the server returns a witness for a different root, transaction creation or consensus validation can fail.
How to reproduce or verify:
Attempt to build a shielded transaction while new blocks are arriving, or mock `getBestAnchor()` to return different heights between witness fetching and transaction building.
Recommended fix:
Fetch a single anchor once, pass its height into witness fetching, require the witness response root/anchor to match, and pass the same anchor into FFI. Consider using a recent-but-stable anchor with a configured confirmation depth.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-007: Custom PIVX Sapling serialization and sighash lack acceptance tests

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/rust/src/transaction.rs`
- `cw_pivx/rust/tests/testnet_integration.rs`
Code references:
- `cw_pivx/rust/src/transaction.rs:451-565`
- `cw_pivx/rust/src/transaction.rs:599-679`
- `cw_pivx/rust/tests/testnet_integration.rs:17-34`
- `cw_pivx/rust/tests/testnet_integration.rs:36-60`
Area: spend authorization, transaction serialization, consensus branch/sighash, broadcast failure
What is wrong:
The Rust builder manually serializes a PIVX Sapling transaction and computes a custom sighash. The repository test covering testnet transaction creation is a TODO/ignored placeholder. The serialization-format test still asserts a Zcash-style overwinter bit/version assumption that conflicts with the current implementation comments.
Why it matters:
Even if proofs are generated, a wrong serialization or sighash makes every shielded transaction invalid at broadcast or consensus. This is a release blocker until validated against PIVX Core/testnet vectors.
How to reproduce or verify:
Create a known testnet z-to-z spend with fixed notes/witnesses and broadcast to a PIVX testnet node. Also compare tx hex, txid, value balance, sighash, and signatures against PIVX Core or known-good vectors.
Recommended fix:
Add deterministic transaction builder tests with fixed fixtures and a manual/CI test that submits shielded transactions to a PIVX testnet/regtest node. Remove or update stale tests that encode contradictory format assumptions.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-008: Shielded spend maturity/min-confirmation options are not enforced

Severity: Medium
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/rust/src/ffi.rs`
Code references:
- `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart:74-105`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:736-760`
- `cw_pivx/rust/src/ffi.rs:817-820`
Area: note selection, pending/confirmed/spendable balances
What is wrong:
`SaplingTransactionOptions` defines `minConfirmations`, `changeAddress`, `useShieldedInputs`, and `useShieldedChange`, but the concrete z-to-z builder does not enforce minimum confirmations and uses all spendable notes returned from the native sync state. Stage 2 also found no modeled pending/confirmed shielded note state.
Why it matters:
The wallet may attempt to spend notes before the intended confirmation depth, creating failures during normal testing and increasing reorg risk.
How to reproduce or verify:
Receive a shielded note and try to spend it before the intended confirmation threshold. Inspect note selection to confirm no height/depth filter is applied.
Recommended fix:
Define the PIVX shielded spend confirmation policy, persist note confirmation state, and filter selected notes by spendable depth. Wire or remove unused transaction options.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-SEND-009: Shielded send logs leak transaction metadata

Severity: Medium
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
- `cw_core/lib/utils/print_verbose.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:762-793`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:875-900`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:69-72`
- `cw_core/lib/utils/print_verbose.dart:8-18`
Area: logging/privacy leaks, transaction construction, broadcast state
What is wrong:
The send path logs selected note count, total selected value, anchor height/prefix, witness cmu prefix, witness path length, FFI status, and broadcast txid mismatch. `printV()` is unconditional in the current codebase.
Why it matters:
Device logs or support captures can reveal shielded spend metadata and timing, weakening privacy guarantees.
How to reproduce or verify:
Build and broadcast a shielded transaction, then inspect app logs for `[PIVX Sapling] Selected`, witness, anchor, and FFI messages.
Recommended fix:
Remove shielded send metadata logs from release builds. Gate sanitized diagnostics behind explicit debug-only opt-in.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 3 Stop Point

Per staged workflow, this pass stops after shielded sending. Next stage should audit balance and wallet state using Stage 2 and Stage 3 findings as context.
