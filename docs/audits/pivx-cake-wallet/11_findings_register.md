# PIVX Audit Findings Register

Status: Stage 8 findings recorded; implementation tracking in progress.

Stage 1 was repository discovery only. Behavioral findings began in Stage 2.

## Current Blocker Tracking Checkpoint

Last updated: 2026-06-11

The first wallet-side implementation pass has started against the highest-risk Critical/High release blockers identified in `09_release_gate_checklist.md`. The following findings are no longer untouched audit findings; they have local wallet-side mitigations and remain `Needs Verification` until automated checks, canonical PIVX Core/ElectrumX verification, and manual tests pass:

- `PIVX-REC-001` / `PIVX-SEND-001`: global Sapling output position/nullifier correctness.
- `PIVX-REC-002`: failed Sapling range handling.
- `PIVX-REC-003` / `PIVX-MOB-001`: encrypted Sapling sidecar storage.
- `PIVX-KEY-001` / `PIVX-REC-007` / `PIVX-SEND-009` / `PIVX-MOB-003`: seed and shielded metadata redaction.
- `PIVX-SEND-002` / `PIVX-SEND-003`: unsupported route blocking before transaction construction.
- `PIVX-NET-001` / `PIVX-NET-002` / `PIVX-NET-003`: mainnet/testnet wiring and Sapling RPC capability policy.
- `PIVX-SEND-006`: anchor-bound witness validation.
- `PIVX-BAL-002`: notes missing spending data are excluded from z-to-z spend selection.
- `PIVX-BAL-001`: shielded pending/confirmed/spendable balance separation.
- `PIVX-SEND-004` / `PIVX-BAL-003`: outgoing shielded pending/nullifier reservation after successful broadcast.
- `PIVX-BAL-006`: zero shielded sidecar balance now clears startup display state.
- `PIVX-REC-006`: generated shielded receive address list/current-address persistence.
- `PIVX-KEY-007` / `PIVX-MOB-004`: native seed-copy, Dart FFI input, and returned-allocation FFI memory hygiene.

Additional hardening on 2026-05-28 tightened these same mitigations: legacy inferred Sapling tree cursors are no longer trusted as persisted state or auto-promoted by empty ranges, trusted sync height and tree cursor completion use a single storage write, explicit server positions are checked against persisted cursor expectations, `get_block_range` v1 envelopes reject range mismatches, PIVX auto-switch candidates require Sapling block-range capability, and shared Electrum debug logging no longer prints raw Sapling RPC params or response snippets. `dart analyze` passes on the touched files. Focused Flutter tests were added but still cannot execute because dependency resolution fails before test startup.

Release posture is unchanged: PIVX remains blocked for external APK and TestFlight. Items marked `Needs Verification` are not closed; they identify code paths that have been changed and now need proof.

Additional send/balance hardening on 2026-05-28 added an anchor-bound witness parser and made z-to-z construction fetch one anchor, validate every witness against that exact root/height/commitment/position, and sign with that same anchor. Shielded transaction results now carry selected nullifiers, successful broadcast reserves those nullifiers in encrypted Sapling storage as pending spends, and reserved notes are excluded from later spend selection until the chain spend is observed. Startup shielded balance loading now writes zero sidecar balance into the displayed balance map instead of preserving stale shielded values. `dart analyze` passes on the touched files with only pre-existing deprecation infos in `pivx_wallet.dart`; focused Flutter tests still cannot execute because package resolution fails on the `mockito`/`hive_generator`/SDK `_macros` conflict.

Additional log-redaction hardening on 2026-05-28 added static regression coverage for interpolated sensitive PIVX/Sapling logging statements, stopped the shared send OpenCryptoPay catch path from printing raw PIVX exceptions, and stopped the shared Electrum client from printing raw server error message text. The new focused Flutter test still cannot execute because package resolution fails on the same dependency solver conflict.

Additional balance hardening on 2026-05-28 added wallet-side shielded note confirmation helpers. Stored notes now expose confirmation counts by chain height, pending received balance, confirmed balance, and spendable balance. PIVX wallet display uses confirmed spendable shielded balance for `secondConfirmed` and pending shielded receives for `secondUnconfirmed`; z-to-z note selection filters candidates through the same confirmed spendable set. The current 6-confirmation receive/spend threshold is provisional and remains a release-owner/canonical Core policy gate. Focused Flutter test execution is still blocked by dependency resolution.

Additional node/detail hardening on 2026-05-28 aligned the wallet client with the ElectrumX agent's reported v1 capability probe name `blockchain.sapling.capabilities`, retained the old `get_capabilities` fallback, and preserved advertised contract/server/Core version, network, activation, block-hash, structured-error, and range metadata. PIVX `Node` records now persist Sapling capability/version fields, and the node list displays cached Sapling readiness/version status after probing. Shielded PIVX transaction detail rows now show pool, route, and shielded confirmation/spendability status. Dart/Rust testnet Sapling activation constants were aligned to block `201` from the reported PIVX Core v5.6.1 evidence. These remain `Needs Verification` until capable/non-capable node tests, default-node v1 metadata evidence, independent Core source confirmation, and manual transaction-detail/restart checks pass.

Additional reorg hardening on 2026-05-31 added wallet-side parsing and persistence of v1 Sapling `block_hashes`, comparison of the last 100 scanned shielded heights on resume when the node advertises block-hash support, sidecar rewind of notes and mined-spend markers after a detected mismatch, and stale shielded receive history cleanup after rewind. This moves `PIVX-REC-005` / `PIVX-BAL-009` to `Needs Verification`, not fixed, until the v1 ElectrumX server/default nodes are verified, Flutter tests can run, and manual reorg/restart tests pass.

Additional dashboard UI hardening on 2026-06-01 gates Litecoin MWEB branding and Peg In/Peg Out controls to Litecoin/LTC rows only. This moves `PIVX-UX-003` to `Needs Verification`, not fixed, until Android/iOS PIVX dashboard evidence confirms the shielded balance card no longer exposes Litecoin MWEB actions and product accepts hiding PIVX shield/deshield controls until those routes are implemented.

Additional dashboard MWEB-gating coverage on 2026-06-02 exposes the second-balance card's Litecoin MWEB-control predicate through a testable helper used by the widget build path. Focused local tests verify the predicate is true only for Litecoin/LTC and false for PIVX/PIVX and non-Litecoin/LTC combinations. This keeps `PIVX-UX-003` at `Needs Verification`, not fixed, until Android/iOS dashboard evidence and product acceptance pass.

Additional send-balance UI hardening on 2026-06-01 makes the PIVX send view's synchronous displayed-balance fallback source-pool aware and forces the send-balance FutureBuilder to recompute for PIVX transparent/shielded source changes. This moves `PIVX-BAL-008` to `Needs Verification`, not fixed, until mixed transparent/shielded manual send-screen tests confirm displayed balance, send-all, and final route behavior remain aligned.

Additional send-balance fallback coverage on 2026-06-02 exposes the PIVX displayed-balance source-pool decision through a small helper used by `SendViewModel.balance`. Focused local tests verify transparent/non-Sapling modes return the transparent available balance, Sapling mode returns the shielded `secondAvailable` balance, and missing PIVX balance data falls back to `0`. This keeps `PIVX-BAL-008` at `Needs Verification`, not fixed, until manual mixed-pool send-screen tests confirm displayed balance, send-all, unsupported-route errors, and final transaction creation remain aligned.

Additional transparent-balance failure hardening on 2026-06-01 ports the parent Electrum null-balance guard into the PIVX balance override. Malformed transparent balance responses now set lost-connection sync state and return the previous transparent balance with current shielded secondary values instead of overwriting transparent balance with zero. Focused local regression coverage added on 2026-06-02 drives `PivxWallet.fetchBalances()` with stubbed missing-`confirmed` and missing-`unconfirmed` Electrum responses and verifies the preserved transparent balance, preserved shielded secondary balances, and `LostConnectionSyncStatus`. This keeps `PIVX-BAL-007` at `Needs Verification`, not fixed, until malformed-node/manual recovery behavior is verified.

Additional shielded transaction-detail coverage on 2026-06-02 exposes the PIVX detail status/pool/route formatting through testable helpers and pins pending receive, spendable receive, outgoing broadcast, mined-but-not-final outgoing send, confirmed outgoing send, negative-confirmation clamping, and route/pool labels. This keeps `PIVX-REC-004` / `PIVX-UX-006` at `Needs Verification`, not fixed, until restart/history persistence and manual Android/iOS detail checks pass against Sapling-capable nodes.

Additional shielded-sync observability hardening on 2026-06-04 adds sanitized height-only logs for PIVX Sapling sync start, first completed range, coarse 10,000-block checkpoints, and final completed range. The ElectrumX sync callback now exposes range start and end to the wallet-side sync wrapper, and focused coverage verifies failed ranges still do not report completion while checkpoint selection remains bounded. This keeps `PIVX-NET-002`, `PIVX-NET-003`, `PIVX-KEY-005`, and `PIVX-UX-007` at `Needs Verification`, not fixed, until device/simulator logs prove the intended start height and sync completion against upgraded default nodes.

Additional simulator verification on 2026-06-04 installed the current workspace build on the iPhone 16e iOS 26.1 simulator over the existing PIVX wallet data. The app restored spendable notes from encrypted storage, completed height-aware Sapling sync from `5440418` to `5440973`, updated encrypted storage, and displayed transparent `0.0` PIVX plus shielded `0.1` PIVX without Litecoin MWEB actions. That run exposed a stale generic sync-status bug where the dashboard pill stayed at `56 Blocks Remaining` after the final shielded range. `PivxWalletBase.syncShielded()` now maps final Sapling progress back to `SyncedSyncStatus`, and focused coverage pins progress-to-synced behavior. A hot-restart simulator rerun completed the follow-up range `5440974-5440976`, logged `SYNC_STATUS_CHANGE: Synced` after the `0 blocks remaining` range, and the dashboard showed `Shielded synced 5440976`. This keeps release closure open for physical-device runs, capable/non-capable node evidence, route/actionable-state checks, and default-node live helper readiness.

Additional default-node probe evidence on 2026-06-04 adds `tool/pivx_sapling_default_node_probe.dart`, a wallet-secret-free JSON-RPC probe for bundled PIVX Electrum nodes. `fvm dart analyze tool/pivx_sapling_default_node_probe.dart` exits 0. A targeted run against `electrum01.chainster.org:50002` and `:50001` showed both endpoints reachable with `ElectrumX 1.19.0`, `blockchain.sapling.capabilities`, contract `pivx.sapling.electrumx.v1`, `release_contract_ready: true`, mainnet activation `2700500`, block hashes, global output positions, all required v1 methods, and complete sampled `get_block_range` envelopes with `height_count=100` and `block_hash_count=100`. The expanded live helper-method probe then found both `electrum01` endpoints returning RPC `-32603` internal server error for `blockchain.sapling.get_best_anchor`; dummy nullifier status returns `spent=false`, while dummy commitment-info currently returns `null` and still needs contract/client-shape confirmation. A same-day full default-node retest at `2026-06-04T01:23:31Z` showed the same electrum01 helper failure and found both `electrum02` ports still refusing connections. A targeted electrum01 retest at `2026-06-04T01:28:32Z` remained unchanged: complete v1 metadata/ranges, `get_best_anchor` RPC `-32603`, dummy nullifier `spent=false`, dummy commitment-info `null`, and `live_helper_methods_ready=false`. Cake Wallet now fails closed during advertised-v1 validation if best-anchor, nullifier-status, or commitment-info cannot be parsed through the live v1 helpers. This keeps `PIVX-NET-002`, `PIVX-NET-003`, `PIVX-SEND-001`, and `PIVX-UX-008` at `Needs Verification`, not fixed, until `electrum01` passes live helper validation, `electrum02` completes reindexing and passes the same probe, and node-list/device sync evidence is captured.

## Finding Format

### FINDING-ID: Short title

Severity:
Status: Open / Needs Verification / Confirmed / Fixed
Files:
Code references:
Area:
What is wrong:
Why it matters:
How to reproduce or verify:
Recommended fix:
Blocks APK testing: Yes/No
Blocks TestFlight: Yes/No

## Stage 2 - Sapling Receive Findings

### PIVX-REC-001: Sapling tree position is not persisted globally, causing wrong nullifiers after restart/resume

Severity: Critical
Status: Needs Verification
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
The wallet persists `lastSyncedHeight` but not the global Sapling output position/tree state. On initialization it reconstructs `_treePosition` from owned notes only, and one startup path restores notes without initializing `_treePosition` at all.
Why it matters:
Sapling nullifiers depend on the note position. Wrong positions can make received shielded notes appear in balance but become unspendable or incorrectly tracked.
How to reproduce or verify:
Sync, restart, then receive after non-owned Sapling outputs have occurred. Compare stored note positions/nullifiers against PIVX Core/librustpivx.
Recommended fix:
Persist global next Sapling output position/tree state transactionally with sync height, initialize it before resumed sync, and test restart/resume with non-owned outputs between wallet notes.
Implementation update, 2026-05-27:
Wallet-side storage now persists `nextTreePosition`, restores it into the sync engine, accepts explicit global output positions from `get_block_range`, and blocks post-activation/birthday shielded sync unless a persisted cursor or server-advertised global output positions are available. This still needs canonical PIVX Core/ElectrumX verification and restart/resume manual tests before the release gate can close.
Implementation update, 2026-05-28:
Legacy sidecars without a real `nextTreePosition` field now expose only an untrusted inferred cursor and cannot resume post-activation sync unless the server advertises global output positions. Sync completion writes `lastSyncedHeight` and `nextTreePosition` together, and explicit server positions must be complete, contiguous, and consistent with any trusted local cursor.
Implementation update, 2026-05-28:
Empty successful ranges no longer promote an untrusted legacy cursor to trusted persisted state. Rescan/clear removes the trusted cursor flag so post-activation rescans still require either activation-height scanning or server global positions.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-002: Sapling RPC failures are treated as empty ranges and marked scanned

Severity: High
Status: Needs Verification
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
`getBlockRange()` swallows all exceptions and returns `[]`, so retry logic is bypassed and `lastSyncedHeight` advances for failed ranges.
Why it matters:
Incoming shielded notes can be missed while the wallet records the affected blocks as scanned.
How to reproduce or verify:
Make `blockchain.sapling.get_block_range` fail for a range containing a note, sync, restore server behavior, then sync again. The note is skipped unless manually rescanned.
Recommended fix:
Differentiate valid empty ranges from failed ranges. Throw/retry failures and do not advance sync height until a range is successfully fetched and processed.
Implementation update, 2026-05-27:
`get_block_range` now treats null, malformed, incomplete-envelope, and exhausted retry responses as `SaplingRpcException`s. Range completion only advances storage height after a successful range fetch. Needs a failing-range integration/manual test against the Sapling ElectrumX fork before closure.
Implementation update, 2026-05-28:
The v1 range envelope parser now also rejects mismatched start/end metadata. Focused test coverage was added for failed-range non-completion and empty complete envelopes, but Flutter test execution is still blocked by dependency resolution.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-003: Shielded receive metadata and note plaintext are stored unencrypted in a separate JSON file

Severity: High
Status: Needs Verification
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
Received notes are saved as plaintext JSON in the app documents directory, including value, txid, output index, tree position, cmu, nullifier, rseed, diversifier, pk_d, and recipient address bytes.
Why it matters:
This leaks shielded receive metadata and materially weakens Sapling privacy on a compromised, backed-up, or inspected device.
How to reproduce or verify:
Receive a shielded note and inspect `pivx_sapling_<walletId>_<network>.json` in the app documents directory.
Recommended fix:
Encrypt Sapling note storage with the wallet storage/encryption model, minimize persisted plaintext, and migrate existing plaintext files.
Implementation update, 2026-05-27:
Sapling sidecar storage now requires Cake wallet file encryption outside explicit test-only storage, writes to `.json.enc`, and migrates legacy plaintext files only when wallet encryption utilities/password are available. Flutter storage tests are still blocked by the repo dependency solver conflict, so device verification and backup-policy confirmation remain open.
Implementation update, 2026-05-28:
Added targeted storage coverage for legacy plaintext sidecar migration: the test writes the old `.json` format, loads storage with wallet encryption utilities, expects the plaintext file to be deleted, verifies `.json.enc` exists without raw JSON keys, and reloads encrypted sync/tree-position state. Test execution is still blocked by the repository dependency solver conflict.
Implementation update, 2026-05-28:
Legacy migration now preserves whether `nextTreePosition` was genuinely present. A sidecar inferred from owned notes is re-saved without converting that inferred value into trusted cursor state.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-004: Shielded receives are not added to transaction history

Severity: High
Status: Needs Verification
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
Shielded note discovery stores a note but does not create a transaction-history item. PIVX history fetching is transparent-address-only.
Why it matters:
Users can receive shielded funds without seeing a corresponding receive transaction, txid, amount, or confirmation status in normal history UI.
How to reproduce or verify:
Receive a shielded note, let sync complete, then inspect transaction list/history.
Recommended fix:
Create shielded receive transaction-history entries from stored notes and update confirmations on later syncs.
Implementation update, 2026-05-28:
PIVX shielded sync now groups stored Sapling notes by txid and writes encrypted `ElectrumTransactionInfo` history entries with shielded pool metadata, amount, height, confirmation count, and pending state. Locally broadcast z-to-z sends now create pending outgoing shielded history entries on successful broadcast. Closure still requires automated history persistence coverage plus manual receive/send/restart evidence against a Sapling-capable node.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-005: Shielded receive confirmation and reorg state are not modeled

Severity: Medium
Status: Needs Verification
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
All unspent stored notes are counted as shielded balance, `pendingBalance` is always `0`, and there is no receive-side rollback/reorg handling.
Why it matters:
The UI cannot distinguish pending, confirmed, and spendable shielded funds, and reorgs can leave stale notes or stale spent state.
How to reproduce or verify:
Receive a low-confirmation shielded note and observe pending balance remains zero while confirmed shielded balance includes the note.
Recommended fix:
Track confirmation depth, pending/confirmed/spendable states, scanned block hashes, and rollback to a safe height on reorg.
Implementation update, 2026-05-31:
Wallet-side storage now persists scanned Sapling block hashes in the encrypted sidecar. When the active node advertises v1 block-hash support, resume sync compares the last 100 scanned heights, rewinds to the last matching height on mismatch, removes notes created after the rewind point, clears mined-spend markers observed after the rewind point, marks the tree cursor untrusted, restores retained spendable notes into the native engine, and rescans forward using explicit server global positions. Shielded receive history refresh removes stale z-receive rows whose notes were removed by rewind. This still requires v1 ElectrumX/default-node verification, focused test execution after the local Flutter/Dart SDK mismatch is resolved, and manual restart/reorg evidence.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 6 - Network And Configuration Findings

### PIVX-NET-001: PIVX mainnet is hard-coded while testnet/build selection parameters are ignored

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:86-99`
- `cw_pivx/lib/src/pivx_wallet.dart:1111-1118`
- `cw_pivx/lib/src/pivx_wallet_service.dart:34-45`
- `cw_pivx/lib/src/pivx_wallet_service.dart:163-179`
Area: mainnet/testnet selection, build variants, release configuration
What is wrong:
PIVX wallet construction always passes `PivxNetwork.mainnet` to the shared Electrum wallet. The service APIs accept `isTestnet`, and the Sapling stack contains testnet branches, but normal create/open/restore flows never pass a testnet network through.
Why it matters:
Testnet validation cannot exercise the same wallet path users will run, and any future test APK/build-flavor policy can silently use mainnet. This also masks testnet activation-height and HRP bugs.
How to reproduce or verify:
Call PIVX create or restore with `isTestnet: true`, then inspect `wallet.network`, generated transparent address prefixes, and Sapling `isTestnet` inputs.
Recommended fix:
Define PIVX network as persisted wallet metadata/build-flavor policy, pass it through create/open/restore/snapshot load, and add tests that testnet wallets generate testnet transparent and Sapling addresses.
Implementation update, 2026-05-27:
PIVX create, open, restore, and snapshot load now pass persisted `mainnet`/`testnet` wallet metadata into `PivxNetwork`, Sapling HRP validation, and native Sapling initialization. Product policy, default node selection, and canonical testnet activation-height confirmation remain release gates.
Implementation update, 2026-05-28:
Dart and Rust testnet Sapling activation constants now use block `201`, matching the ElectrumX agent's reported PIVX Core v5.6.1 `src/chainparams.cpp` evidence. This is not a closed release gate until the release owner records the canonical Core tag/commit evidence and runs testnet wallet/node validation.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-002: Sapling ElectrumX RPC method names do not match the documented supported server contract

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/SAPLING.md`
- `docs/audits/pivx-cake-wallet/12_open_questions.md`
Code references:
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:6-20`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:378-417`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:467-469`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:533-562`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:831-900`
- `cw_pivx/SAPLING.md:117-131`
Area: ElectrumX Sapling RPC compatibility, shielded receive/send configuration
What is wrong:
The active Dart client calls methods such as `blockchain.nullifier.get_spend`, `blockchain.commitment.get_info`, `blockchain.sapling.get_outputs`, `blockchain.anchor.get_height`, `blockchain.sapling.get_tree_state`, and `blockchain.sapling.get_witness`. The documented currently supported local `sapling_integration` ElectrumX fork exposes `blockchain.sapling.get_nullifier_status`, `get_commitment_info`, `get_outputs_by_height`, `get_block_range`, `get_anchor_height`, and `get_best_anchor`.
Why it matters:
Shielded scanning may reach `get_block_range`, but nullifier, commitment, anchor, witness, and outputs-by-height flows can fail against the intended server. Sending can fail at witness/anchor fetch, and spent-note checks can be unreliable.
How to reproduce or verify:
Run the PIVX wallet against the intended Sapling ElectrumX fork and call every method in `PIVXSaplingElectrumX`. Compare successful method names with the server's registered methods.
Recommended fix:
Freeze the production Sapling RPC contract, align Dart names and response parsers with that contract, remove stale/planned method names, and add a startup capability/version check.
Implementation update, 2026-05-27:
The Dart client added Sapling capability probing, validates network/activation height when advertised, supports the v1 `get_block_range` completion envelope, and prefers current `sapling_integration` method aliases for nullifier, commitment, outputs-by-height, anchor height, and best anchor. Server-side v1 contract work and witness/tree-state support remain open in `14_electrumx_followups.md`.
Implementation update, 2026-05-28:
The Dart client now tries the ElectrumX agent's reported v1 method name `blockchain.sapling.capabilities` before the previous `blockchain.sapling.get_capabilities` fallback. Capability parsing now preserves advertised contract/server/Core version, network, activation height, max range, block-hash, structured-error, and global-position feature metadata for UI/status use. This still needs live v1 server verification.
Implementation update, 2026-06-01:
`cw_pivx/SAPLING.md` and the `PIVXSaplingElectrumX` header were aligned to the current reported v1 contract from `15_electrumx_update_from_other_agent.md`: contract id `pivx.sapling.electrumx.v1`, primary capability probe `blockchain.sapling.capabilities`, complete `get_block_range` envelopes with `block_hashes`, canonical global output positions, anchor-bound witness metadata, and structured failure semantics. Legacy method names remain compatibility fallbacks only and are not sufficient default-node release evidence. `fvm dart analyze cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart` exits 0. This finding remains `Needs Verification` until Cake Wallet is tested against deployed v1/default nodes.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-003: Node health and automatic switching do not verify Sapling RPC capability

Severity: High
Status: Needs Verification
Files:
- `assets/pivx_electrum_server_list.yml`
- `lib/entities/default_settings_migration.dart`
- `lib/store/settings_store.dart`
- `lib/core/node_switching_service.dart`
- `cw_core/lib/node.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
Code references:
- `assets/pivx_electrum_server_list.yml:1-17`
- `lib/entities/default_settings_migration.dart:53`
- `lib/entities/default_settings_migration.dart:1203-1206`
- `lib/store/settings_store.dart:1181-1182`
- `lib/core/node_switching_service.dart:98-175`
- `cw_core/lib/node.dart:307-318`
- `cw_pivx/lib/src/pivx_wallet.dart:882-898`
Area: node defaults, fallback servers, server failure handling, automatic node switching
What is wrong:
Default PIVX nodes and the migration fallback are not tied to a verified Sapling-capable server list. Node liveness only opens an Electrum socket, and PIVX node health only checks transparent balance RPCs.
Why it matters:
The wallet can connect to or auto-switch to a reachable generic PIVX Electrum server while shielded sync/spend RPCs are unsupported. The UI can show a generally connected/synced state while Sapling is silently broken.
How to reproduce or verify:
Add a reachable non-Sapling PIVX Electrum server with auto-switching enabled, make the current node fail, then observe automatic switching and shielded sync behavior.
Recommended fix:
Add PIVX Sapling capability metadata and runtime probing for required RPCs. Exclude non-capable nodes from shielded wallets or disable shielded features with an explicit user-visible status.
Implementation update, 2026-05-27:
PIVX wallet health and shielded sync now probe Sapling block-range capability, store a sanitized `saplingRpcAvailable`/`lastShieldSyncError` state, and fail shielded sync/send policy checks when the active node cannot provide required RPCs. Shared node auto-switching still needs a PIVX Sapling capability filter/badge before this gate closes.
Implementation update, 2026-05-28:
Automatic node switching now creates a temporary Electrum connection for PIVX candidate nodes and runs the Sapling capability probe before selecting the node. Reachable generic PIVX Electrum nodes no longer qualify as shielded-wallet auto-switch targets. Manual node-list badge/status evidence and device auto-switch tests still remain.
Implementation update, 2026-05-28:
Manual PIVX node testing in the node edit flow now treats a reachable Electrum socket without Sapling block-range capability as a failed PIVX node test. This adds UI/status evidence for capability probing, but the default-node list still needs server-side v1 capability/version evidence and manual device tests before the gate closes.
Implementation update, 2026-05-28:
PIVX node records now persist Sapling capability, contract/server/Core version, network, activation height, and last-check timestamp. The node list probes PIVX nodes, caches the result briefly to avoid repeated probe/save loops, and displays per-node Sapling readiness/version status. Capable/non-capable node device tests and default-node v1 metadata evidence are still required.
Implementation update, 2026-05-31:
`15_electrumx_update_from_other_agent.md` was re-read for current server context: v1 support is reported under contract id `pivx.sapling.electrumx.v1` with primary method `blockchain.sapling.capabilities`. A live probe of shipped defaults in `assets/pivx_electrum_server_list.yml` found `electrum02.chainster.org` and `electrum01.chainster.org` reachable on SSL/plain ports. `electrum02` has partial legacy Sapling RPC support (`get_block_range` returns a bare list and `get_witness` is registered), but lacks the v1 capability probe, v1 envelope/global positions, best-anchor, nullifier-status, and commitment-info methods. `electrum01` still returns `unknown method` for sampled Sapling methods. This confirms the current bundled defaults are not yet default-node v1 evidence.
Implementation update, 2026-06-01:
The wallet-facing Sapling API documentation was updated to match the reported v1 contract and to label legacy aliases as compatibility-only. This reduces tester/server ambiguity, but does not close node readiness: capable/non-capable node device tests, upgraded default-node v1 metadata, and manual auto-switch/status evidence are still required.
Implementation update, 2026-06-02:
Wallet-side node readiness now uses an explicit `supportsV1ReleaseContract` predicate for `pivx.sapling.electrumx.v1`. Manual node testing, node-list status probing, and automatic node switching require that predicate rather than bare block-range support. Nodes that advertise v1 but omit required release features are rejected, and legacy block-range fallback is labeled compatibility-only (`Sapling legacy only`) instead of release-ready. Focused local tests cover complete v1, incomplete v1, legacy fallback, and null malformed capability responses. This remains Needs Verification until deployed capable/non-capable v1 nodes, upgraded default-node metadata, node-list screenshots, and device auto-switch tests pass.
Implementation update, 2026-06-04:
The repeatable `tool/pivx_sapling_default_node_probe.dart` now records default-node v1 capability/range summaries without wallet secrets. A targeted run at `2026-06-04T00:51:09Z` showed both `electrum01.chainster.org:50002` and `:50001` reachable and advertising complete `pivx.sapling.electrumx.v1` metadata, plus complete sampled range envelopes for `2700500-2700599`, `2700900-2700999`, and `2705000-2705099` with `block_hash_count=100`. An expanded run at `2026-06-04T01:08:20Z` found a remaining live helper blocker: both `electrum01` endpoints return RPC `-32603` internal server error for `blockchain.sapling.get_best_anchor`. Dummy nullifier status returns `spent=false`; dummy commitment-info returns `null` and still needs explicit contract/client-shape confirmation. Wallet-side v1 readiness now validates these live helper calls and rejects advertised v1 nodes that fail them, so node-list readiness and auto-switching fail closed instead of showing a false ready state. A same-day bundled-default retest at `2026-06-04T01:23:31Z` confirmed electrum01 remains blocked on best-anchor and `electrum02.chainster.org` still refuses both default ports while reindexing. A targeted electrum01 retest at `2026-06-04T01:28:32Z` was unchanged. Keep this finding open until `electrum01` passes live helper validation, `electrum02` passes after reindexing, and device node-list/auto-switch evidence is captured.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-004: Proving parameter acquisition is not release-safe or proxy/Tor-aware

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_constants.dart`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart`
- `cw_pivx/rust/src/prover.rs`
- `cw_pivx/rust/src/ffi.rs`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:765-793`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:616-795`
- `cw_pivx/lib/src/sapling/sapling_constants.dart:97-118`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart:150-186`
- `cw_pivx/rust/src/prover.rs:21-81`
- `cw_pivx/rust/src/ffi.rs:723-781`
Area: proving parameter acquisition, release configuration, Tor/proxy behavior
What is wrong:
Shielded sends lazily download proving parameters at send time from third-party URLs. The active wallet downloader now uses `ProxyWrapper`, verifies cached and downloaded files by expected size/SHA-256, and renames verified temp files into place, but the release policy is still incomplete: there is no bundled/offline path, no streaming/resume behavior, the release owner has not approved the final canonical PIVX host/mirror policy, and device Tor/interruption/low-storage behavior has not passed.
Why it matters:
Users can be blocked from sending shielded funds if the host is unavailable or blocked. Parameter downloads must not leak outside the selected Tor/proxy policy, and partial or corrupted files must not poison future send attempts.
How to reproduce or verify:
Delete local params, enable built-in Tor, attempt a shielded send, and verify the request uses Cake's proxy/Tor path. Interrupt download mid-file, retry, corrupt cached params, and test low-storage/iOS-background behavior.
Recommended fix:
Choose a release policy: bundle params, ship an app-managed verified downloader, or require first-run prefetch. Use approved redundant hosts, `ProxyWrapper`, atomic temp files, hash/size verification before marking available, and clear UI progress/error states.
Implementation update, 2026-05-28:
The active `SaplingTransactionBuilderWrapper` downloader now routes through `ProxyWrapper`, validates existing files by size and SHA-256 before `initProver`, removes invalid final files, writes downloaded bytes to `.download`, verifies the temp file, and renames only after verification. This is not a release-gate closure because release-owner approval of canonical PIVX-hosted metadata/mirrors, streaming/resume policy, and manual Tor/interruption/low-storage tests remain open.
Implementation update, 2026-05-31:
Live URL/hash/size evidence was recorded for the configured PIVX-hosted parameter URLs: `https://duddino.com/sapling-spend.params` serves `47,958,396` bytes with SHA-256 `8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13`, and `https://duddino.com/sapling-output.params` serves `3,592,860` bytes with SHA-256 `2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4`. Dart constants, Rust prover hash verification, FFI `has_proving_params`, and alternate-builder messaging now use the same metadata. This remains `Needs Verification` until the release owner approves the host/mirror policy and mobile Tor/proxy/interruption/low-storage tests pass.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-005: Fee and dust policies are inconsistent across transparent, Sapling, Dart, and Rust layers

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_network.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pivx_transaction_priority.dart`
- `cw_pivx/lib/src/sapling/sapling_constants.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/transaction.rs`
Code references:
- `cw_pivx/lib/src/pivx_network.dart:136-143`
- `cw_pivx/lib/src/pivx_wallet.dart:1094-1100`
- `cw_pivx/lib/src/pivx_transaction_priority.dart:62-78`
- `cw_pivx/lib/src/sapling/sapling_constants.dart:124-184`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:800-806`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:957-984`
- `cw_pivx/rust/src/ffi.rs:170-204`
- `cw_pivx/rust/src/ffi.rs:684-730`
- `cw_pivx/rust/src/transaction.rs:24-29`
Area: fee policy, dust policy, send-max, transaction acceptance
What is wrong:
Earlier wallet code used inconsistent transparent/Sapling/Rust dust and fee values. Wallet-side code now uses a Core-derived size-based fee table, transparent dust `5,460`, shielded dust `1,446,000`, min relay/min wallet fee of 10,000 zatoshis/kB, dust relay fee of 30,000 zatoshis/kB, and Sapling relay fee factor `100`. Remaining open risk is real PIVX Core mempool acceptance around dust/change/send-max and manual device evidence.
Why it matters:
Send-max/change handling can be wrong, valid sends can be rejected by local validation, invalid/dust sends can reach broadcast, or fees can differ materially from PIVX Core policy.
How to reproduce or verify:
Build transactions around 5,460 transparent dust, 1,446,000 shielded dust, and shielded change equal/above/below the threshold, then compare local validation, UI fee display, serialized transaction fee, and PIVX Core mempool acceptance.
Recommended fix:
Define one PIVX Core-derived policy table for relay fee, dust, minimum shielded output/change, and size estimation. Use it from transparent send, Sapling send, FFI validation, and UI fee display.
Implementation update, 2026-05-28:
Added a shared wallet-side `PivxFeePolicy` for transparent and Sapling size-based fees and send-max planning. This was superseded on 2026-05-31 by separate Core-derived transparent and shielded dust thresholds.
Implementation update, 2026-05-28:
Checked PIVX Core v5.6.1 source: `src/policy/policy.h` defines `DUST_RELAY_TX_FEE = 30000`, `src/policy/policy.cpp` wires `dustRelayFee` and dust checks, `src/validation.cpp` defines `minRelayTxFee = CFeeRate(10000)` and `GetShieldedTxMinFee()` multiplies the serialized-size relay fee by `DEFAULT_SHIELDEDTXFEE_K`/`100`, and `src/wallet/wallet.h` defines `DEFAULT_TRANSACTION_MINFEE = 10000`. Wallet-side Dart and Rust Sapling fee estimation now apply the factor-100 shielded policy.
Implementation update, 2026-05-31:
Checked the remaining PIVX Core v5.6.1 shielded dust constants: `src/validation.h` defines `DEFAULT_SHIELDEDTXFEE_K = 100`; `src/sapling/sapling_transaction.h` defines `SPENDDESCRIPTION_SIZE = 384`, `CTXOUT_REGULAR_SIZE = 34`, and `BINDINGSIG_SIZE = 64`; `src/policy/feerate.cpp` uses integer division in `CFeeRate::GetFee()`. This yields Core shielded dust `100 * floor(30000 * 482 / 1000) = 1,446,000` zatoshis. Dart/Rust now use transparent dust `5,460` and shielded dust `1,446,000`; z-to-z amount validation, send-all minimums, dust-change suppression, FFI validation, and Rust builder validation were aligned. `dart analyze` passes on the focused Dart files, `cargo test --manifest-path cw_pivx/rust/Cargo.toml test_shielded_dust_threshold` passes, and the Flutter test runner is still blocked by the local SDK mismatch.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-006: Native Sapling library loading and build scripts can ship missing or stale artifacts

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt`
- `scripts/build_android_macos.sh`
- `cw_pivx/ios/cw_pivx.podspec`
- `cw_pivx/macos/cw_pivx.podspec`
- `cw_pivx/linux/CMakeLists.txt`
Code references:
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:20-66`
- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt:19-25`
- `scripts/build_android_macos.sh:98-112`
- `scripts/build_android_macos.sh:155-156`
- `cw_pivx/ios/cw_pivx.podspec:23-42`
- `cw_pivx/macos/cw_pivx.podspec:27-29`
- `cw_pivx/linux/CMakeLists.txt:27-38`
Area: native library loading, build flags, release configuration
What is wrong:
Android plugin startup unconditionally calls `System.loadLibrary`. The build helper skips all Android PIVX native rebuilds if only the arm64 `.so` exists. Dart opens `.dylib`/`.so` names on desktop while macOS/Linux plugin configs link/bundle static `.a` libraries.
Why it matters:
Release builds can crash at plugin load or silently disable Sapling depending on platform and artifact state. Stale checked-in/native artifacts can be shipped without rebuilding from source.
How to reproduce or verify:
Remove one Android ABI library and build a universal APK; run macOS/Linux and call `isSaplingFFIAvailable`; compare loaded native version against the Rust source version.
Recommended fix:
Make native build artifacts deterministic per platform/ABI, fail CI if any required artifact is missing/stale, rebuild from Rust for release candidates, and align Dart dynamic loading with the actual platform packaging model.
Implementation update, 2026-05-31:
Android plugin load is now fail-soft instead of process-crashing on missing/blocked `libcw_pivx_sapling.so`, and exposes load state/error over the plugin channel. Dart FFI now has a native self-test covering library load, expected symbol lookup, version callability, and native fee estimation against the Core-derived Dart Sapling fee policy; direct FFI helpers now return false or throw explicit native-unavailable errors instead of late-initialization failures. Android build helpers now require all four APK ABI artifacts and fail if any `libcw_pivx_sapling.so` is missing or empty after build. This remains open for release CI source rebuilds, per-ABI hash/version provenance, iOS packaging evidence, and Android/iOS physical-device self-test results.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-NET-007: PIVX networking bypasses per-node proxy settings and disables TLS certificate validation for Electrum sockets

Severity: Medium
Status: Needs Verification
Files:
- `cw_core/lib/node.dart`
- `cw_core/lib/utils/proxy_socket/abstract.dart`
- `cw_bitcoin/lib/electrum_wallet.dart`
- `cw_bitcoin/lib/electrum.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_core/lib/node.dart:41-49`
- `cw_core/lib/node.dart:288-306`
- `cw_core/lib/utils/proxy_socket/abstract.dart:18-37`
- `cw_bitcoin/lib/electrum_wallet.dart:671-684`
- `cw_bitcoin/lib/electrum.dart:59-81`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:744-795`
Area: Tor/proxy behavior, Electrum security, proving parameter acquisition
What is wrong:
Per-node `socksProxyAddress` is stored on `Node` but not passed into Electrum connection setup. Electrum TLS sockets accept bad certificates. Proving parameter downloads now use `ProxyWrapper`, but still require device proof for the selected Tor/proxy policy.
Why it matters:
Users who configure a node-level proxy may still connect directly. TLS MITM is not rejected for Electrum sockets, and PIVX network operations need proof that no release path leaks outside the expected Tor/proxy policy.
How to reproduce or verify:
Set a PIVX node `socksProxyAddress`, keep built-in Tor off, and observe Electrum connecting directly. Attempt to connect to a TLS endpoint with an invalid certificate and observe acceptance.
Recommended fix:
Pass node proxy settings into Electrum connections, decide whether bad-certificate bypass is acceptable for any production Electrum wallet, and verify all PIVX parameter/network fetches through the same proxy/Tor abstraction.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-BAL-001: Shielded notes are counted as confirmed and spendable immediately

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `lib/view_model/dashboard/balance_view_model.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:242-248`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:223-230`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:475-491`
- `cw_pivx/lib/src/pivx_wallet.dart:511-515`
- `cw_pivx/lib/src/pivx_wallet.dart:867-876`
- `lib/view_model/dashboard/balance_view_model.dart:182-200`
Area: shielded balance, spendable balance, pending/confirmed balances, balance after receive
What is wrong:
Any stored shielded note with `isSpent == false` is included in shielded balance, while pending shielded balance always returns `0`. There is no confirmation depth, spendable depth, locked note state, or pending-receive state.
Why it matters:
New shielded receives can appear as confirmed/spendable too early, and the UI cannot distinguish pending, confirmed, and actually spendable shielded funds.
How to reproduce or verify:
Receive a shielded note and inspect balance immediately after the block is scanned. `secondConfirmed` increases and `secondUnconfirmed` remains zero.
Recommended fix:
Persist note block height, scanned block hash, confirmation depth, and spendability state. Expose pending shielded receives through `secondUnconfirmed`.
Implementation update, 2026-05-28:
Sapling note storage now computes confirmations from note height and chain height, separates pending received notes from confirmed notes, and exposes spendable balance only for unreserved notes with complete spending data that meet the provisional shielded spend confirmation threshold. PIVX wallet balance now maps confirmed spendable shielded balance to `secondConfirmed` and pending received shielded balance to `secondUnconfirmed`; z-to-z send selection uses the same confirmed spendable note set. The finding remains open for canonical confirmation-depth policy, reorg/hash handling, focused test execution, and manual receive/spend verification.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-002: Restart balance can include notes that are not restorable for spending

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:269-274`
- `cw_pivx/lib/src/pivx_wallet.dart:310-344`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:184-212`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:155-160`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:242-248`
Area: balance after restart, spendable balance, local wallet database state
What is wrong:
Startup counts all unspent stored notes in shielded balance, but the native engine restores only notes with all spending data. Notes missing rseed/diversifier/pk_d/nullifier are skipped while still counted in balance.
Why it matters:
Users can see shielded funds as available after restart while transaction creation says no spendable notes or fails during note selection.
How to reproduce or verify:
Create or modify a stored note missing one spending-data field, restart the wallet, and compare displayed shielded balance with native restored spendable notes.
Recommended fix:
Separate observed balance from spendable balance. Exclude missing-spending-data notes from spendable/send-all balances until rescan repairs them.
Implementation update, 2026-05-28:
Sapling storage now exposes spendable notes/balance separately from observed unreserved notes, and the z-to-z builder filters native spend candidates through storage notes that still have complete spending data and are not reserved pending spends. Startup display semantics are not fully redesigned yet, so this remains open for UI/manual verification and send-max integration.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-003: Outgoing shielded sends do not update pending or spendable balance until mined and rescanned

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
Code references:
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:61-86`
- `cw_pivx/lib/src/pivx_wallet.dart:1252-1260`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:416-422`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:351-377`
- `cw_pivx/rust/src/sync.rs:72-98`
Area: balance after send, balance after failed broadcast, local pending state, duplicate send prevention
What is wrong:
Successful shielded broadcast does not mark selected notes pending spent or record an outgoing pending balance. Stored notes are marked spent only when a later scanned block contains their nullifier.
Why it matters:
After a send, the wallet can keep showing spent shielded notes as available and can attempt another send from the same notes.
How to reproduce or verify:
Broadcast a shielded z-to-z transaction, then inspect shielded balance before the spending nullifier is mined/scanned.
Recommended fix:
Persist outgoing pending shielded transactions and selected nullifiers before/at successful broadcast. Move their value out of spendable balance immediately.
Implementation update, 2026-05-28:
The z-to-z builder now returns selected nullifiers in `SaplingTransactionResult`. After a successful Electrum broadcast, `PivxWallet` reserves those nullifiers in encrypted Sapling storage as pending spends, removes them from spendable storage balance/selection, and reconciles shielded balance before attempting post-broadcast shielded sync. Needs focused Flutter test execution, app-kill/restart verification, and chain reconciliation against a mined spend before closure.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-004: Shielded send-max and fee deduction are not balance-correct

Severity: High
Status: Needs Verification
Files:
- `lib/view_model/send/send_view_model.dart`
- `lib/view_model/send/output.dart`
- `lib/src/screens/send/widgets/send_card.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
Code references:
- `lib/view_model/send/send_view_model.dart:302-325`
- `lib/view_model/send/output.dart:101-158`
- `lib/view_model/send/output.dart:296-300`
- `lib/src/screens/send/widgets/send_card.dart:522-523`
- `lib/src/screens/send/widgets/send_card.dart:849-850`
- `cw_pivx/lib/src/pivx_wallet.dart:1221-1230`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:744-760`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:810-829`
Area: send-max behavior, fee deduction, spendable balance, insufficient funds
What is wrong:
PIVX shielded send-all uses `secondAvailable` as the full send amount without subtracting the Sapling fee. The visible amount is changed to localized "all", which parses to `0`. Note selection also selects notes for amount before fee.
Why it matters:
The wallet cannot correctly spend max shielded balance and can reject valid spends when additional notes could cover the fee.
How to reproduce or verify:
Use PIVX shielded mode, press Send all, and try to create a transaction. Also test a note set where amount is covered but amount plus fee requires another note.
Recommended fix:
Implement a PIVX shielded spendable-balance API that calculates send-max after note selection, fees, change, and dust policy.
Implementation update, 2026-05-28:
Shielded z-to-z send-all now computes the send amount from locally spendable notes minus the no-change Sapling fee, and asks the Sapling builder to spend all shielded inputs. Note selection is now fee-aware and can select additional notes when amount-only selection would miss the fee. Closure still requires device/manual send-all evidence and regression tests that can run in the project Flutter SDK.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-005: Combined full balance suggests cross-pool spendability that is not implemented

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_bitcoin/lib/electrum_balance.dart`
- `lib/view_model/send/send_view_model.dart`
- `lib/bitcoin/cw_bitcoin.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:167-180`
- `cw_pivx/lib/src/pivx_wallet.dart:663-759`
- `cw_pivx/lib/src/pivx_wallet.dart:1186-1275`
- `cw_bitcoin/lib/electrum_balance.dart:60-61`
- `lib/view_model/send/send_view_model.dart:272-280`
- `lib/bitcoin/cw_bitcoin.dart:268-286`
Area: total balance, spendable balance, transparent balance, shielded balance
What is wrong:
The wallet exposes total/full available balance as transparent plus shielded, but cross-pool spending is not implemented. t-to-z and z-to-t paths throw or fall through, and shielded notes are not UTXOs.
Why it matters:
The send screen can overstate what is spendable for a given destination/source pool, creating failed sends and tester confusion.
How to reproduce or verify:
Hold both transparent and shielded funds, then attempt to send the combined amount to either a transparent or shielded address.
Recommended fix:
Display pool-specific spendable balances in PIVX send flows. Do not use combined full balance as spendable until cross-pool construction is implemented and tested.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-006: Stale shielded balance can survive zero-balance storage, failed sync, or aborted rescan

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:310-344`
- `cw_pivx/lib/src/pivx_wallet.dart:491-500`
- `cw_pivx/lib/src/pivx_wallet.dart:579-609`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:326-333`
- `cw_bitcoin/lib/electrum_wallet.dart:91-99`
Area: balance after restart, balance after rescan, wallet state, failed sync
What is wrong:
Startup updates the balance map only when stored shielded balance is greater than zero. Shielded rescan clears storage and native state, but if sync aborts due to no connection, previous in-memory/displayed shielded balance is not immediately cleared or marked stale.
Why it matters:
After restart, rescan, or connectivity failure, the UI can show shielded funds that are no longer present in local Sapling storage.
How to reproduce or verify:
Start with nonzero shielded balance, clear/rescan shielded storage while offline, or open a wallet whose encrypted snapshot still has `secondConfirmed` while Sapling storage has zero notes.
Recommended fix:
On startup and rescan, explicitly set shielded confirmed/pending/spendable state from authoritative Sapling storage even when zero. Mark shielded balance stale/unavailable when sync cannot run.
Implementation update, 2026-05-28:
Startup sidecar loading now updates `shieldedBalance`, `pendingShieldedBalance`, and the wallet balance map even when encrypted Sapling storage has zero spendable shielded balance. This mitigates the zero-storage stale display case, but failed-sync/rescan stale-state UX still needs manual/device verification before the finding can close.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-007: PIVX transparent balance can be overwritten to zero on null balance responses

Severity: Medium
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_bitcoin/lib/electrum_wallet.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:848-876`
- `cw_bitcoin/lib/electrum_wallet.dart:2504-2511`
Area: transparent balance, balance after server failure, wallet state
What is wrong:
The parent Electrum wallet preserves last known balance on null balance responses, but the PIVX override treats missing `confirmed` / `unconfirmed` fields as zero.
Why it matters:
A node/API failure can make transparent PIVX balance display as zero instead of stale/unknown, which is confusing and can corrupt saved balance state.
How to reproduce or verify:
Mock `electrumClient.getBalance()` to return a map with null or missing `confirmed` during `PivxWallet.fetchBalances()`.
Recommended fix:
Port the parent null-response handling into the PIVX override and preserve last known balance while setting lost-connection/stale status.
Implementation update, 2026-06-01:
`PivxWallet.fetchBalances()` now treats any transparent Electrum balance response missing `confirmed` or `unconfirmed` as malformed, sets `LostConnectionSyncStatus`, and returns the previous transparent balance instead of summing missing fields as zero. The returned balance keeps current PIVX shielded `secondConfirmed`/`secondUnconfirmed` values so shielded display reconciliation is not rolled back by a transparent node failure. Focused local tests now inject controlled Electrum responses through the real PIVX wallet balance path and cover both missing fields. `fvm dart analyze cw_pivx/lib/src/pivx_wallet.dart cw_pivx/test/cw_pivx_test.dart` exits 0 with only pre-existing snapshot deprecation infos, and `fvm flutter test cw_pivx/test/cw_pivx_test.dart --no-pub` passes all 11 focused restore/balance tests. Closure still requires malformed-node/device evidence and UX acceptance of the lost-connection/stale-balance behavior.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-BAL-008: PIVX send-page displayed balance is not source-pool aware

Severity: Medium
Status: Needs Verification
Files:
- `lib/view_model/send/send_view_model.dart`
- `cw_bitcoin/lib/electrum_balance.dart`
- `lib/view_model/unspent_coins/unspent_coins_list_view_model.dart`
Code references:
- `lib/view_model/send/send_view_model.dart:272-280`
- `lib/view_model/send/send_view_model.dart:302-325`
- `cw_bitcoin/lib/electrum_balance.dart:54-61`
- `lib/view_model/unspent_coins/unspent_coins_list_view_model.dart:194-208`
Area: spendable balance, UI send flow, tester confusion
What is wrong:
For PIVX, the send view `balance` getter displays combined full available balance, while the send-all helper uses pool-specific values.
Why it matters:
Users can believe the selected source pool has more funds than it does, especially when a destination type cannot spend from both pools.
How to reproduce or verify:
Open a PIVX wallet with transparent and shielded funds, toggle "Send from shielded balance", and compare visible balance text with actual source-pool spendable amount.
Recommended fix:
Make the PIVX send-page balance source-pool aware.
Implementation update, 2026-06-01:
The PIVX send view `balance` fallback now returns transparent available balance for transparent source mode and shielded `secondAvailable` balance for Sapling source mode, matching the already pool-aware async `sendingBalance`/send-all helper. `updateSendingBalance()` now also toggles transparent/Sapling source values internally before restoring the selected source so the FutureBuilder refreshes after PIVX source changes and coin-control returns. `fvm dart analyze lib/view_model/send/send_view_model.dart` exits 0. Closure still requires manual mixed-pool send-screen tests on device, including transparent mode, shielded mode, send-all, unsupported route errors, and final transaction creation behavior.
Implementation update, 2026-06-02:
Focused local regression coverage now pins the PIVX displayed-balance fallback used by the send view model: transparent and other non-Sapling modes use the PIVX transparent available balance, Sapling mode uses shielded `secondAvailable`, and missing PIVX balance data returns `0`. `fvm dart analyze lib/view_model/send/send_view_model.dart test/view_model/pivx_send_view_model_test.dart` exits 0, and `fvm flutter test test/view_model/pivx_send_view_model_test.dart --no-pub` passes all 3 focused send-balance fallback tests. Closure still requires manual mixed-pool send-screen evidence.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-BAL-009: Shielded balance has no rollback/reorg model

Severity: Medium
Status: Needs Verification
Files:
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/rust/src/sync.rs`
Code references:
- `cw_pivx/lib/src/sapling/sapling_factories.dart:346-360`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:416-422`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:499-501`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:516-521`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:379-385`
- `cw_pivx/rust/src/sync.rs:72-103`
Area: balance after reorg or rollback, local wallet database state, spent state
What is wrong:
Shielded sync stores a last synced height and mutates notes/spent flags, but does not persist block hashes, detect reorgs, or roll back notes/nullifier spends by block range. The only rescan path clears all notes.
Why it matters:
A reorg can leave shielded balance too high, too low, or notes incorrectly marked spent until the user performs a full rescan.
How to reproduce or verify:
On regtest/testnet, receive or spend a shielded note, then reorg out the block and continue sync. Inspect whether note/spent state rolls back automatically.
Recommended fix:
Persist scanned block hashes and per-block note/nullifier effects. On reorg, roll back to a safe common ancestor and rescan forward.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-SEND-001: Shielded spend construction depends on unverified note positions/nullifiers from receive state

Severity: Critical
Status: Needs Verification
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
The z-to-z send path spends notes restored from local receive storage and accepts the stored note/nullifier data plus ElectrumX witness position without an independent local commitment tree verification step. This compounds Stage 2 finding `PIVX-REC-001`: if receive scanning persisted the wrong global tree position, the restored nullifier and witness context can be wrong.
Why it matters:
A shielded wallet can show funds that cannot be spent after restart/resume, or build transactions that fail proof/signature/consensus validation.
How to reproduce or verify:
Receive multiple shielded notes across blocks containing unrelated Sapling outputs, restart the app, restore notes from storage, then attempt a z-to-z spend. Compare stored `treePosition` and nullifier against a PIVX Core/indexer-derived global note position and nullifier.
Recommended fix:
Fix receive-side global commitment tree position tracking first. Before signing, validate every selected note against an authenticated anchor/witness source and recompute/verify nullifiers from canonical note position.
Implementation update, 2026-05-27:
Receive-side position handling now persists a global cursor and can consume explicit server positions, and shielded send creation now blocks unless the node advertises anchor/witness support. Full closure still requires anchor-bound witness verification and canonical PIVX Core transaction-vector/manual spend tests.
Implementation update, 2026-05-28:
The send-side dependency on receive state is reduced by refusing to trust legacy inferred tree cursors and by checking explicit server positions against any trusted cursor. This does not replace anchor-bound witness verification; the finding remains release-blocking.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-002: Transparent-to-shielded and shielded-to-transparent sends are not implemented

Severity: High
Status: Needs Verification
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
Users cannot reliably enter or exit the shielded pool through the app.
How to reproduce or verify:
Call `shieldFunds`, `deshieldFunds`, or attempt to send to a shielded recipient with only transparent balance. The code reaches explicit unsupported exceptions.
Recommended fix:
Either implement and test t-to-z and z-to-t transaction construction, or remove/block those flows in UI and release notes until implemented.
Implementation update, 2026-05-27:
Unsupported mixed transparent/shielded outputs, shielded-source-to-transparent sends, and direct transparent-to-external-shielded sends are blocked before transaction construction. The actual `t-to-z` and `z-to-t` builders remain unimplemented, so the first external route matrix must keep those routes disabled unless implemented and manually accepted.
Implementation update, 2026-05-28:
Public `shieldFunds` and `deshieldFunds` now throw explicit unsupported-route errors immediately, before Sapling builder/proving-parameter setup. Shielded-address sends with an ambiguous `UnspentCoinType.any` source now fail closed and require an explicit transparent or Sapling source selection; non-Sapling sources to shielded destinations are blocked as unsupported `t-to-z`.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-003: Shielded mode with a transparent destination falls through to transparent sending

Severity: High
Status: Needs Verification
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
The routing decision checks only whether the destination address is shielded. If the user enables shielded mode and enters a transparent PIVX address, the wallet falls back to the parent transparent transaction builder.
Why it matters:
The UI can imply a shielded spend while the wallet attempts a transparent spend, causing confusing failure or a wrong-pool spend.
How to reproduce or verify:
Enable "Send from shielded balance", enter a transparent PIVX address, and create the transaction. The Sapling builder is not selected unless the output address itself is shielded.
Recommended fix:
Route on both source pool and destination type. Explicitly block z-to-t until implemented.
Implementation update, 2026-05-27:
PIVX `createTransaction` now routes on selected source pool and destination address type. Shielded-source sends to transparent destinations throw an explicit unsupported-route error instead of falling through to transparent transaction creation. Needs UI/manual send-flow verification.
Implementation update, 2026-05-28:
Shielded-output sends no longer auto-select shielded funds from `UnspentCoinType.any`; ambiguous source-pool routing now fails before construction so testers cannot accidentally rely on combined/implicit pool behavior.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-004: Broadcast does not reserve or mark spent shielded notes locally

Severity: High
Status: Needs Verification
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
After broadcast, the wallet does not persist a pending outgoing shielded transaction, reserve selected nullifiers, or mark selected notes as pending spent. Notes are marked spent only when a later scanned block reveals a matching nullifier.
Why it matters:
Until the spend is mined and rescanned, the wallet can continue showing spent notes as available and can build another transaction from the same notes.
How to reproduce or verify:
Broadcast a z-to-z transaction, then immediately inspect `SaplingNoteStorage` or attempt another shielded spend before the spending nullifier appears in scanned blocks.
Recommended fix:
Return selected nullifiers from the builder, persist outgoing pending state before broadcast, mark notes pending spent on successful broadcast, and reconcile from chain state later.
Implementation update, 2026-05-28:
`SaplingTransactionResult` now includes selected nullifiers, and successful `PendingPivxShieldedTransaction` commit callbacks reserve matching stored notes as pending spent. Mined nullifier detection clears the pending flag and marks the notes spent. Needs focused test execution, restart-after-broadcast verification, and mined/rejected-broadcast reconciliation evidence before closure.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-005: Shielded send-max is broken and fee-aware note selection is incomplete

Severity: High
Status: Needs Verification
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
The send-all button sets the visible amount to localized text, which PIVX amount parsing turns into `0`. Separately, note selection selects notes for amount before calculating fee, then fails instead of selecting more notes. Dust change is not handled before calling Rust.
Why it matters:
Shielded send-max is not usable, and valid sends can fail even when additional notes are available.
How to reproduce or verify:
Use PIVX shielded mode, press Send all, and attempt to create a z-to-z transaction. Also test a wallet where the first selected note covers amount but not amount plus fee.
Recommended fix:
Implement PIVX Sapling-specific send-max and iterative fee-aware note selection, including dust/change handling.
Implementation update, 2026-05-28:
The Sapling builder now plans spends using amount plus fee, suppresses dust change into the fee instead of sending dust to Rust, and exposes deterministic planning helpers covered by `cw_pivx/test/pivx_fee_policy_test.dart`. The test could not execute in this environment because Flutter package resolution / SDK mismatch blocks the cw_pivx test runner, so this remains Needs Verification.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-SEND-006: Witnesses and anchor can be fetched from different chain states

Severity: High
Status: Needs Verification
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
Witness fetching obtains an anchor internally, then transaction building obtains a second anchor and passes that later anchor into FFI. There is no witness-anchor equality check.
Why it matters:
Sapling spend proofs require the witness path to correspond to the transaction anchor. Mismatch can make the transaction invalid.
How to reproduce or verify:
Attempt to build a shielded transaction while new blocks are arriving, or mock `getBestAnchor()` to return different heights between witness fetching and transaction building.
Recommended fix:
Fetch one anchor once, pass its height into witness fetching, require witness response anchor/root to match, and sign with the same anchor.
Implementation update, 2026-05-28:
The Sapling client now parses anchor-bound witness responses and rejects missing path, missing anchor/root, missing anchor height, missing commitment, missing position, root/height mismatch, or commitment mismatch. The z-to-z builder fetches one best anchor, fetches all witnesses against that anchor, checks witness position against the selected note, and passes the same anchor into FFI signing. Needs server v1 witness metadata support, focused Flutter test execution, and manual build/broadcast testing against canonical PIVX Core/ElectrumX before closure.
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
The Rust builder manually serializes a PIVX Sapling transaction and computes a custom sighash, but the repository has no completed testnet/regtest acceptance test or known-good vector. One existing test encodes assumptions that conflict with current implementation comments.
Why it matters:
A wrong serialization or sighash makes every shielded transaction invalid at broadcast or consensus.
How to reproduce or verify:
Create a known testnet z-to-z spend with fixed notes/witnesses and broadcast to a PIVX testnet node. Compare tx hex, txid, value balance, sighash, and signatures against PIVX Core or known-good vectors.
Recommended fix:
Add deterministic transaction builder tests plus a manual/CI test that submits shielded transactions to a PIVX testnet/regtest node.
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
`SaplingTransactionOptions` defines `minConfirmations`, `changeAddress`, `useShieldedInputs`, and `useShieldedChange`, but the concrete z-to-z builder does not enforce minimum confirmations and uses all spendable notes returned from native sync state.
Why it matters:
The wallet may attempt to spend notes before the intended confirmation depth, creating failures during normal testing and increasing reorg risk.
How to reproduce or verify:
Receive a shielded note and try to spend it before the intended confirmation threshold. Inspect note selection to confirm no height/depth filter is applied.
Recommended fix:
Define the PIVX shielded spend confirmation policy, persist note confirmation state, and filter selected notes by spendable depth.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-SEND-009: Shielded send logs leak transaction metadata

Severity: Medium
Status: Needs Verification
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
Device logs or support captures can reveal shielded spend metadata and timing.
How to reproduce or verify:
Build and broadcast a shielded transaction, then inspect app logs for `[PIVX Sapling] Selected`, witness, anchor, and FFI messages.
Recommended fix:
Remove shielded send metadata logs from release builds. Gate sanitized diagnostics behind explicit debug-only opt-in.
Implementation update, 2026-05-27:
Selected-note count, witness path length, FFI status details, txid mismatch details, and raw build/broadcast errors were redacted. Needs a release-log sweep and automated banned-pattern coverage before closure.
Implementation update, 2026-05-28:
Removed the shared Electrum client's raw Sapling RPC request debug prints and raw response snippets, which could expose nullifier, commitment, witness, or returned shielded metadata.
Implementation update, 2026-05-28:
Added `pivx_log_redaction_test.dart` to scan PIVX/Sapling logging paths for interpolated sensitive seed, note, nullifier, cmu, witness, txid, anchor, balance, address, value, and position terms. The shared PIVX OpenCryptoPay send error path no longer prints raw exceptions, and shared Electrum error logging no longer prints raw server error message text. Needs dependency-unblocked test execution and manual release-log verification before closure.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-REC-006: Additional shielded receive addresses can crash the receive list

Severity: Medium
Status: Needs Verification
Files:
- `lib/pivx/cw_pivx.dart`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
Code references:
- `lib/pivx/cw_pivx.dart:80-88`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:233-245`
- `cw_pivx/lib/src/pivx_wallet.dart:565-705`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:766-806`
Area: shielded address persistence, receive UI
What is wrong:
`diversifierIndex` is returned as an `int` but cast as a `String` in the receive list.
Why it matters:
Generated diversified shielded addresses can break the receive address UI.
How to reproduce or verify:
Generate an additional shielded address and reopen the receive address list.
Recommended fix:
Use a consistent type for `diversifierIndex` and add a test for stored shielded addresses.
Implementation update, 2026-06-06:
Wallet-side receive-list handling now accepts integer, numeric, or legacy string `diversifierIndex` values and skips malformed rows without crashing. Generated shielded address storage now has focused coverage for persistence, labels, and next receive index reload. PIVX wallet startup restores the current shielded receive address from the highest stored diversifier index after shielded storage initializes, so generated receive addresses do not silently fall back to the default address after restart. `fvm dart analyze cw_pivx/lib/src/pivx_wallet.dart cw_pivx/test/cw_pivx_test.dart cw_pivx/test/sapling_note_storage_test.dart lib/view_model/wallet_address_list/wallet_address_list_view_model.dart test/view_model/pivx_wallet_address_list_view_model_test.dart` exits 0 with only pre-existing `pivx_wallet.dart` deprecation infos, and `fvm flutter test cw_pivx/test/cw_pivx_test.dart cw_pivx/test/sapling_note_storage_test.dart test/view_model/pivx_wallet_address_list_view_model_test.dart --no-pub` passes all 46 focused tests. Closure still requires simulator/device evidence that generating additional PIVX shielded addresses, reopening the receive list, and restarting the app preserves selectable/current address behavior.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-REC-007: Receive scan logs leak shielded metadata through unconditional logging

Severity: Medium
Status: Needs Verification
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
Shield sync logs amounts, heights, positions, note counts, balances, and partial cmu/witness metadata, while `printV()` always prints.
Why it matters:
Device logs or crash/support captures can leak shielded receive metadata.
How to reproduce or verify:
Run shield sync and inspect logs for `[PIVX Sapling] Found note`, storage balance, restore, or witness messages.
Recommended fix:
Remove or redact receive-sensitive logs and gate any remaining diagnostics behind debug-only explicit opt-in.
Implementation update, 2026-05-27:
Note-found, native note restore detail, storage load/save error content, witness fetch errors, and balance reconciliation values were redacted. Needs release-log sweep and manual support/crash-log verification before closure.
Implementation update, 2026-05-28:
Shared Electrum request logging no longer prints raw Sapling RPC params or response snippets. Remaining risk is broader app/support/crash/copy handling, which still needs verification.
Implementation update, 2026-05-28:
Focused static redaction coverage was added for PIVX/Sapling log statements. The shared PIVX send OpenCryptoPay catch path now logs a generic failure instead of the raw exception, and Electrum response error logging prints only the response id, not raw server-provided error text. Test execution remains blocked by dependency resolution.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 5 - Restore And Key Derivation Findings

### PIVX-KEY-001: Invalid mnemonic handling leaks the full seed phrase

Severity: Critical
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `lib/view_model/wallet_creation_vm.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet_service.dart:167-169`
- `lib/view_model/wallet_creation_vm.dart:137-145`
Area: seed restore, key leakage in logs/errors
What is wrong:
PIVX seed restore includes the full entered mnemonic in the invalid-mnemonic exception, and the shared wallet creation flow logs and stores that exception text.
Why it matters:
An incorrectly entered seed can leak through logs, support bundles, crash diagnostics, UI error plumbing, or screenshots.
How to reproduce or verify:
Enter an invalid PIVX seed during restore and inspect logs for `Invalid mnemonic: ...`.
Recommended fix:
Throw a sanitized typed invalid-mnemonic error and never interpolate seed text into exceptions or logs.
Implementation update, 2026-05-27:
PIVX seed restore now throws `Invalid PIVX mnemonic` without interpolating the entered mnemonic. Remaining closure requires shared wallet-creation/error-popup verification that raw PIVX seed text cannot be logged, copied, or crash-reported.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-002: WIF/private-key restore is unavailable for old transparent funds

Severity: High
Status: Needs Verification
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
PIVX restore exposes only seed mode, and the WIF restore service path validates prefixes but then throws `UnimplementedError`.
Why it matters:
Users with old transparent PIVX WIF/private-key funds cannot recover or sweep them in the app.
How to reproduce or verify:
Open PIVX restore and confirm there is no key mode; call `restoreFromKeys` with a valid PIVX WIF and observe the unimplemented error.
Recommended fix:
Implement WIF sweep/import or explicitly remove the dead service path and document a migration route.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-003: Transparent restore discovery can stop after one extra gap batch

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:940-981`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart:612-624`
- `cw_bitcoin/lib/electrum_wallet_addresses.dart:627-655`
Area: transparent derivation, address discovery, recovery of old transparent funds
What is wrong:
The shared discovery helper compares the last newly checked result against the previous address-list tail, preventing recursive extension beyond one added batch.
Why it matters:
Seed restore can miss transparent receive/change funds beyond the initial window plus one extra gap batch.
How to reproduce or verify:
Fund a PIVX seed at indexes beyond multiple gap windows, restore from seed, and compare recovered history/balance to a full derivation scan.
Recommended fix:
Fix the discovery termination condition and add multi-gap PIVX restore tests for receive and change chains.
Implementation update, 2026-05-31:
Shared Electrum address discovery now treats any history in a newly generated gap batch as a reason to extend the scan, and the recursive call carries the generated batch forward so the next batch starts at the correct index. This should give PIVX transparent restore a full unused receive/change gap after the highest used derived address. Keep open until multi-gap PIVX receive/change restore tests and manual device recovery evidence pass.
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
Transparent PIVX always uses `m/44'/119'/0'`, Sapling always uses `m/32'/119'/0'`, and the PIVX restore flow offers no derivation/account chooser. The Sapling `accountIndex` parameter is accepted but ignored.
Why it matters:
Funds in non-zero accounts, alternate legacy paths, or another PIVX-compatible derivation path will not be recovered from seed.
How to reproduce or verify:
Place funds on account 1 or an alternate PIVX path, restore in Cake Wallet, and observe that only account 0 is scanned.
Recommended fix:
Define supported PIVX derivation paths/accounts, persist explicit metadata, add account/path selection or detection, and implement Sapling account indexing if supported.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-KEY-005: PIVX seed restore has no restore birthday/height control

Severity: Medium
Status: Needs Verification
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
The PIVX restore flow has no height/date selector and PIVX restore credentials do not carry a restore height. Fresh shielded restore falls back to Sapling activation height.
Why it matters:
Modern wallet restores can require excessive scanning, and any future height support must be carefully designed to avoid missing older shielded notes.
How to reproduce or verify:
Open PIVX seed restore and confirm no height/date field is present; restore a fresh seed and observe shield sync starting from activation height.
Recommended fix:
Add PIVX restore birthday UX with safe defaults and persist/display the chosen restore height.
Implementation update, 2026-05-31:
PIVX seed restore now uses the generic restore block-height field. Empty height remains the safe import default, preserving transparent scan from genesis and shielded scan from Sapling activation. If a user enters a height, it is carried through PIVX restore credentials, persisted as `WalletInfo.restoreHeight`, used by transparent Electrum restore, and applied to the first shielded sync when no restored Sapling sidecar state exists. Keep open until device UX tests verify empty-height and explicit-height restores, and capable v1 Sapling node tests confirm the shielded first-scan start behavior.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-KEY-006: Seed restore can reuse prior diversified shielded addresses

Severity: Medium
Status: Needs Verification
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
Additional diversified shielded addresses and `nextDiversifierIndex` are local storage state. A seed-only restore starts at the default address with `nextDiversifierIndex = 1`, so the first generated shielded address can repeat an address from the old wallet.
Why it matters:
Funds remain recoverable by scanning, but receive UI state and address labels are lost, and address reuse can weaken privacy.
How to reproduce or verify:
Generate shielded address index 1, restore only from seed into a fresh wallet, then generate a shielded address and compare it with the old index-1 address.
Recommended fix:
Reconstruct or advance shielded address state from discovered note diversifiers where possible, and avoid presenting repeated diversified addresses as new.
Implementation update, 2026-06-01:
After shielded sync, the wallet now derives and Bech32-decodes the first 1,000 Sapling addresses, compares their raw 43-byte payment-address payloads with recovered note recipient bytes (`address` or `diversifier + pk_d`), and advances `nextDiversifierIndex` past the highest observed match without moving the index backwards. `SaplingNoteStorage.advanceNextDiversifierIndexAtLeast` persists that floor and has focused storage coverage added. Keep open until dependency-unblocked tests run and manual seed-only restore confirms a new generated shielded receive address does not repeat a previously used diversified address.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-KEY-007: Sapling FFI seed copy is freed without being zeroed

Severity: Medium
Status: Needs Verification
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
The original implementation zeroed the Dart Sapling seed buffer after initialization but freed the copied `malloc` seed buffer used for FFI without overwriting it.
Why it matters:
Seed material can remain in freed native heap memory until overwritten, weakening key-handling guarantees.
How to reproduce or verify:
Inspect `SaplingKeys.fromSeed()` and confirm the copied seed is overwritten before `malloc.free`, then run the focused native-buffer wipe test.
Recommended fix:
Overwrite the native seed buffer before `malloc.free`, and audit Rust/Dart key buffers with zeroizing allocation helpers where possible.
Update 2026-06-11:
`SaplingKeys.fromSeed()` now calls `zeroNativeUint8Buffer()` before freeing the native `malloc<Uint8>` seed copy, and `cw_pivx/test/sapling_ffi_memory_test.dart` verifies the native byte-buffer wipe helper. Keep this as Needs Verification until the broader FFI/native memory boundary is reviewed with `PIVX-MOB-004`.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 7 - Mobile Security Findings

### PIVX-MOB-001: Sapling note/address sidecar is plaintext in app documents storage

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_core/lib/wallet_keys_file.dart`
- `cw_core/lib/encryption_file_utils.dart`
Code references:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:50-64`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:111-131`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:166-213`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:271-287`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:313-320`
- `cw_core/lib/wallet_keys_file.dart:21-31`
- `cw_core/lib/encryption_file_utils.dart:28-41`
Area: mobile local storage, shielded note metadata, secure storage
What is wrong:
PIVX Sapling notes, nullifiers, memos, rseed/diversifier/pk_d/address data, shielded address labels, and sync state are written as raw JSON under app documents instead of using the existing encrypted wallet-key file path or another encrypted local store.
Why it matters:
Compromise of app documents, device forensic extraction, local backup artifacts, or debug access exposes shielded wallet metadata and note-restoration material.
How to reproduce or verify:
Receive or restore a shielded note, then inspect the app documents directory for `pivx_sapling_<wallet>_mainnet.json`.
Recommended fix:
Encrypt Sapling sidecar state with a per-wallet key derived/stored consistently with the wallet password architecture, and migrate/delete plaintext legacy files after successful encrypted write.
Implementation update, 2026-05-27:
The sidecar now requires wallet encryption outside explicit tests, writes to `.json.enc`, and migrates/deletes legacy plaintext only after an encrypted write. Needs device storage inspection, backup inclusion/exclusion decision, and restore verification before closure.
Implementation update, 2026-05-28:
Added pending test coverage for plaintext-to-encrypted sidecar migration and deletion. The test could not be executed yet because `flutter test cw_pivx/test/sapling_note_storage_test.dart` fails during package resolution on the existing `mockito`/`hive_generator`/SDK `_macros` conflict.
Implementation update, 2026-05-31:
Cake backup import/export now skips legacy plaintext PIVX Sapling sidecars while leaving encrypted `.json.enc` sidecars eligible for encrypted Cake app backup inclusion. Device storage inspection and clean-device backup/restore verification are still required before closure.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-MOB-002: Cake backup can include plaintext PIVX Sapling sidecar state without a dedicated sensitive-state policy

Severity: High
Status: Needs Verification
Files:
- `lib/core/backup_service_v3.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `android/app/src/main/AndroidManifest.xml`
Code references:
- `android/app/src/main/AndroidManifest.xml:32-41`
- `lib/core/backup_service_v3.dart:348-361`
- `lib/core/backup_service_v3.dart:380-397`
- `lib/core/backup_service_v3.dart:399-423`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`
Area: backup/restore exposure, plaintext note metadata
What is wrong:
Android OS backup is disabled, but Cake's app-level backup walks the app directory and archives first-level files/directories before encrypting the backup. The plaintext PIVX Sapling sidecar is not explicitly encrypted before backup or classified by the backup layer.
Why it matters:
The backup archive is encrypted, but sensitive PIVX state remains plaintext at rest before export, and future backup/restore changes could include or omit critical shielded state accidentally.
How to reproduce or verify:
Create a PIVX shielded note file, export a Cake backup, and confirm whether `pivx_sapling_*.json` is included in the pre-encryption archive content.
Recommended fix:
Treat Sapling sidecar state as a first-class encrypted wallet artifact. Either include only the encrypted sidecar in backups, or exclude plaintext sidecars and reconstruct them safely during restore.
Implementation update, 2026-05-31:
Wallet-side policy now includes encrypted PIVX Sapling sidecars in Cake's encrypted app backup path but explicitly excludes legacy plaintext `pivx_sapling_*.json`, the public proving-parameter cache directory `pivx_sapling_params`, and Sapling parameter `.download` temp files during v3 export and v1/v2/v3 restore. `dart analyze lib/core/backup_service.dart lib/core/backup_service_v3.dart` exits 0 with one pre-existing `encryptionKey` deprecation info. Keep this open until a backup containing an encrypted Sapling sidecar is exported, inspected for plaintext/parameter exclusion, restored on a clean device, and verified against shielded state/rescan expectations.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-MOB-003: PIVX errors/logs can leak seed phrases and shielded metadata, then expose them through crash/support/copy flows

Severity: Critical
Status: Needs Verification
Files:
- `cw_core/lib/utils/print_verbose.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `lib/view_model/wallet_creation_vm.dart`
- `lib/utils/exception_handler.dart`
Code references:
- `cw_core/lib/utils/print_verbose.dart:8-25`
- `cw_pivx/lib/src/pivx_wallet_service.dart:167-169`
- `lib/view_model/wallet_creation_vm.dart:137-145`
- `lib/utils/exception_handler.dart:396-423`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:178-212`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:374-377`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:444-464`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:762-796`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:875-896`
Area: logs, crash reports, support diagnostics, clipboard
What is wrong:
Invalid PIVX seed restore interpolates the full mnemonic into an exception, shared wallet creation logs that exception and stack, and PIVX Sapling sync logs shielded note metadata. The shared error popup can copy raw error content to the system clipboard.
Why it matters:
Seed phrases and shielded receive/spend metadata can leak through device logs, crash tooling, support screenshots, copied errors, or developer log files.
How to reproduce or verify:
Enter an invalid PIVX mnemonic and inspect logs/UI error text; run shield sync and inspect logs for note values, heights, positions, cmu/witness, and balance data.
Recommended fix:
Sanitize PIVX exceptions, remove seed interpolation, redact all shielded metadata logs by default, and add tests/lints for banned sensitive logging patterns.
Implementation update, 2026-05-27:
PIVX wallet/Sapling logs were redacted for seed restore failures, sidecar load/save failures, note restore, witness fetch, selected-note counts, txid mismatch, and transaction-build/broadcast errors. Remaining release work: add automated banned-log coverage and verify shared support/crash/copy flows sanitize PIVX exceptions end to end.
Implementation update, 2026-05-28:
Removed raw Sapling RPC request logging and raw response snippets from the shared Electrum client. This closes one additional log path for shielded metadata, but does not yet prove crash/support/copy-flow redaction.
Implementation update, 2026-05-28:
Added banned-pattern regression coverage for PIVX/Sapling logs and removed two raw shared error-print paths relevant to PIVX. Closure still requires running the regression test and manually checking invalid-seed UI, crash/support export, and copy-to-clipboard behavior.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-MOB-004: FFI/native key and transaction buffers are freed without a consistent zeroization policy

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/rust/src/ffi.rs`
- `cw_pivx/rust/src/keys.rs`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:220-256`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:525-545`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:575-586`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:745-790`
- `cw_pivx/rust/src/ffi.rs:251-259`
- `cw_pivx/rust/src/ffi.rs:261-305`
- `cw_pivx/rust/src/ffi.rs:307-322`
- `cw_pivx/rust/src/ffi.rs:1348-1418`
- `cw_pivx/rust/src/keys.rs:191-246`
Area: FFI memory handling, native key material, mobile crash/core-dump exposure
What is wrong:
The Dart BIP39 seed buffer, native seed copy, Dart-owned native UTF-8 inputs/short-lived Sapling byte buffers, Rust-owned returned strings/buffers, Rust shielded-transaction result staging strings, deserialized spendable-note input strings, and Rust transaction/UTXO/options transfer strings are now zeroed on their relevant free/copy/drop paths, but broader Rust key/proving/transaction intermediates carrying note objects, viewing keys, anchors/nullifiers, and spend-proving material still lack a fully documented memory-hardening boundary. Rust key manager `Drop` uses best-effort byte writes and documents remaining limitations.
Why it matters:
Seed/key/transaction material can persist in freed native heap memory, process memory snapshots, crash artifacts, or swapped pages longer than necessary.
How to reproduce or verify:
Inspect `SaplingKeys.fromSeed()`, Dart `toNativeUtf8()` FFI input free paths, `cw_pivx_free_string()`, `cw_pivx_free_buffer()`, legacy `pivx_*` free paths, and Rust key manager disposal.
Recommended fix:
Zero native Dart `malloc` and UTF-8 input buffers before free, use zeroizing allocations/wrappers on Rust buffers and strings carrying secrets where practical, and document the mobile memory-hardening guarantee.
Update 2026-06-11:
The native Dart `malloc<Uint8>` seed copy passed into `cw_pivx_init_keys` is now overwritten before free, with focused `zeroNativeUint8Buffer()` coverage. Rust FFI returned allocations are also wiped before free: `cw_pivx_free_string()` and the legacy `pivx_free_string()` overwrite C string bytes before `CString::from_raw()`, `cw_pivx_free_buffer()` overwrites returned `FFIBuffer.data` before releasing the `libc::malloc()` allocation with `libc::free()`, and the legacy `pivx_free_buffer()` wipes bytes before dropping its `Vec`. `cargo test --manifest-path cw_pivx/rust/Cargo.toml test_zero_ffi_allocation_overwrites_bytes` passes. This finding remains Confirmed until Rust-owned key/transaction intermediates, transaction JSON lifetime, memo/address/error material, and the documented mobile memory-hardening boundary are addressed or explicitly accepted.
Update 2026-06-11:
Dart-owned native UTF-8 inputs now call `zeroNativeUtf8String()` before `malloc.free()` across PIVX Sapling FFI calls, including restored-note JSON, transaction notes JSON, recipient addresses, optional memos, anchors, proving-parameter paths, and prover directories. Temporary native byte buffers for trial decryption and nullifier checks are also overwritten before free. `fvm dart analyze cw_pivx/lib/src/sapling/sapling_ffi.dart cw_pivx/test/sapling_ffi_memory_test.dart` exits 0, and `fvm flutter test cw_pivx/test/sapling_ffi_memory_test.dart --no-pub` passes both focused memory-hygiene tests. This finding remains Confirmed until Rust-owned key/transaction intermediates, transaction JSON lifetime inside Rust/Dart results, allocator/platform residuals, and the documented mobile memory-hardening boundary are addressed or explicitly accepted.
Update 2026-06-11:
`cw_pivx_build_shielded_tx()` now copies shielded transaction result JSON into the returned `FFIBuffer` through a helper that zeroizes the Rust staging `String` immediately after the copy. The success path also zeroizes temporary `txid` and raw transaction hex strings, and the error path zeroizes temporary error JSON/message strings, after the returned buffer is populated. `cargo test --manifest-path cw_pivx/rust/Cargo.toml test_ffi_buffer_from_string_copies_bytes` and `cargo test --manifest-path cw_pivx/rust/Cargo.toml test_zero_ffi_allocation_overwrites_bytes` pass. This finding remains Confirmed until deeper Rust-owned key/proving/transaction intermediates, allocator/platform residuals, and the documented mobile memory-hardening boundary are addressed or explicitly accepted.
Update 2026-06-11:
`SpendableNoteData` now zeroizes sensitive deserialized note-input strings on drop, including diversifier, `pk_d`, `rcm`, `rseed`, witness path, nullifier, optional `cmu`, and optional memo. `cargo test --manifest-path cw_pivx/rust/Cargo.toml spendable_note_data_zeroizes_sensitive_strings` passes. This finding remains Confirmed until deeper Rust-owned key/proving/transaction intermediates, allocator/platform residuals, and the documented mobile memory-hardening boundary are addressed or explicitly accepted.
Update 2026-06-11:
Rust serialized transfer structs now zeroize sensitive strings on drop: `TransactionResult` wipes txid, raw transaction hex, and nullifier strings; `TransparentUtxoData` wipes txid, script pubkey, and private key material; and `TransactionOptions` wipes destination address, optional memo, and optional change address. Focused cargo tests for those three helpers and the existing spendable-note helper pass. This finding remains Confirmed until deeper Rust-owned key/proving/transaction intermediates, allocator/platform residuals, and the documented mobile memory-hardening boundary are addressed or explicitly accepted.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-MOB-005: PIVX network privacy is weakened by permissive TLS and proving downloads that bypass Tor/proxy policy

Severity: High
Status: Confirmed
Files:
- `cw_core/lib/utils/proxy_socket/abstract.dart`
- `cw_bitcoin/lib/electrum.dart`
- `cw_bitcoin/lib/electrum_wallet.dart`
- `cw_core/lib/node.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `cw_core/lib/utils/proxy_socket/abstract.dart:18-39`
- `cw_bitcoin/lib/electrum.dart:67-85`
- `cw_bitcoin/lib/electrum_wallet.dart:671-685`
- `cw_core/lib/node.dart:282-305`
- `cw_pivx/lib/src/pivx_wallet.dart:775-793`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:653-795`
Area: TLS, Tor/proxy, proving parameter acquisition, mobile privacy
What is wrong:
Electrum SSL sockets accept bad certificates. The proving-parameter downloader now uses Cake's `ProxyWrapper`, but Tor/proxy behavior still needs device evidence and per-node proxy/TLS policy remains unresolved.
Why it matters:
Users who enable Tor or SSL can still leak IP/network metadata or accept MITM-modified network paths during PIVX operations.
How to reproduce or verify:
Enable Tor or configure a node proxy, trigger PIVX proving-parameter download, and verify it uses the expected proxy path; connect to an SSL node with a bad certificate and observe acceptance until TLS policy is fixed.
Recommended fix:
Route proving downloads through the same Tor/proxy policy as wallet traffic, require pinned hashes for params, and enforce normal TLS validation for PIVX SSL nodes unless explicitly overridden for a custom node.
Implementation update, 2026-05-28:
The proving-parameter portion is wallet-side mitigated by `ProxyWrapper`, size/hash checks, and atomic temp-file promotion. This finding remains blocking for Electrum TLS behavior, node-specific proxy semantics, and manual Tor/proxy proof on Android/iOS.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-MOB-006: Shielded receive/payment clipboard and URI flows lack a PIVX privacy policy

Severity: Medium
Status: Confirmed
Files:
- `lib/utils/clipboard_util.dart`
- `lib/src/screens/receive/widgets/qr_widget.dart`
- `lib/utils/payment_request.dart`
- `lib/src/screens/send/widgets/send_card.dart`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
Code references:
- `lib/utils/clipboard_util.dart:6-14`
- `lib/src/screens/receive/widgets/qr_widget.dart:225-229`
- `lib/src/screens/receive/widgets/qr_widget.dart:263-265`
- `lib/utils/payment_request.dart:8-67`
- `lib/src/screens/send/widgets/send_card.dart:762-790`
- `lib/src/screens/send/widgets/send_card.dart:900-945`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:88-91`
Area: clipboard, QR, payment URI, shielded address privacy
What is wrong:
Sensitive clipboard is available and used for seeds/keys, but receive addresses and address URIs are copied through normal clipboard. Generic payment URI parsing does not define PIVX Sapling memo/privacy handling, and shielded transaction UR export is empty.
Why it matters:
Shielded addresses and memos are privacy-sensitive metadata. Normal clipboard history, cross-app paste prompts, keyboards, or device sync can expose receive/payment context.
How to reproduce or verify:
Copy a PIVX shielded receive address or URI from the receive QR widget and observe normal clipboard behavior.
Recommended fix:
Define PIVX-specific clipboard/URI rules: normal vs sensitive clipboard, optional auto-clear, memo handling, and explicit support or non-support for shielded payment URI/UR formats.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-MOB-007: Screenshot/app-switcher protection exists but is opt-in and not enforced on PIVX sensitive screens

Severity: Medium
Status: Confirmed
Files:
- `cw_core/lib/set_app_secure_native.dart`
- `android/app/src/main/java/com/cakewallet/cake_wallet/MainActivity.java`
- `ios/Runner/AppDelegate.swift`
- `lib/store/settings_store.dart`
- `lib/src/screens/settings/privacy_page.dart`
Code references:
- `cw_core/lib/set_app_secure_native.dart:3-8`
- `android/app/src/main/java/com/cakewallet/cake_wallet/MainActivity.java:52-58`
- `ios/Runner/AppDelegate.swift:76-89`
- `lib/store/settings_store.dart:327-333`
- `lib/store/settings_store.dart:1048-1050`
- `lib/src/screens/settings/privacy_page.dart:76-83`
Area: screenshots, app switcher, shoulder-surfing risk
What is wrong:
The app can prevent screenshots/screen recording, but the setting defaults to false and is global. PIVX seed, wallet keys, viewing keys, shielded receive metadata, and error screens do not force protection.
Why it matters:
Sensitive PIVX material can appear in screenshots, screen recordings, app switcher previews, support images, or shared-device contexts unless the user found and enabled the global setting.
How to reproduce or verify:
With a fresh install, open PIVX seed/key or shielded receive screens and confirm the privacy setting is off by default.
Recommended fix:
Force secure-screen mode on seed/key/viewing-key and high-sensitivity PIVX screens, or default it on for PIVX wallets with a clear user override policy.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-MOB-008: Native Sapling library artifacts are not release-provenanced or rebuilt deterministically

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt`
- `cw_pivx/ios/cw_pivx.podspec`
- `scripts/build_android_macos.sh`
- `android/app/build.gradle`
Code references:
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:20-43`
- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt:19-25`
- `cw_pivx/ios/cw_pivx.podspec:23-42`
- `scripts/build_android_macos.sh:98-114`
- `android/app/build.gradle:79-94`
Area: native library loading, release artifacts, Android/iOS packaging
What is wrong:
PIVX Sapling native libraries are loaded dynamically/force-loaded, checked-in Android/iOS artifacts exist, and the build script skips rebuilding if an arm64 Android `.so` already exists. Debug builds also use release signing.
Why it matters:
A stale, mismatched, or unverified native library that handles Sapling keys/proofs can ship in mobile releases without deterministic provenance.
How to reproduce or verify:
Inspect checked-in `cw_pivx_sapling` artifacts and run the build script with existing Android libs present; it reports PIVX libraries already exist instead of rebuilding all ABIs.
Recommended fix:
Release CI should rebuild PIVX native libraries from source for every release candidate, record per-platform/ABI hashes and versions, fail on missing symbols, and keep debug/release signing clearly separated.
Implementation update, 2026-05-31:
The Android native build helpers now rebuild when any required ABI is missing and exit non-zero if any ABI artifact remains absent or empty. Dart exposes a runtime Sapling native self-test for load/symbol/version/Core-fee alignment, and Android plugin load no longer crashes the process on missing native artifacts. Release provenance is still not complete until CI rebuilds from Rust source, records artifact hashes and source commit, and runs native self-tests on target Android/iOS hardware.
Implementation update, 2026-06-04:
Added `tool/pivx_sapling_native_self_test.dart` so release owners can run the Dart native runtime self-test directly and point it at a specific artifact with `PIVX_SAPLING_LIBRARY_PATH`. The macOS loader also now has repo-local framework fallbacks for command-line validation. Initial local evidence showed the checked-in macOS framework dylib loaded and resolved symbols but failed fee parity (`native=25000`, `expected=1417000`), while the current Rust source test and freshly rebuilt debug/release dylibs passed the Dart self-test when selected through `PIVX_SAPLING_LIBRARY_PATH`. `bash cw_pivx/scripts/build_macos.sh` then rebuilt the checked-in universal macOS dylib/static lib/header from current Rust source; the default `fvm dart run tool/pivx_sapling_native_self_test.dart` now passes against `cw_pivx/macos/Frameworks/libcw_pivx_sapling.dylib`. Recorded SHA-256 hashes are `40e4ce2467f154c313adb0296d882ca9363c1cde1149401235899faee5e2b692` for `libcw_pivx_sapling.dylib`, `b5b1129a23e50f73dec34f18a816321e29d3c418e641367f0cc698df8ddbea7a` for `libcw_pivx_sapling.a`, and `4e521cfcf050679fcf57e887a8ff03cd712daa159989ebd8a57c241db9b1e3c8` for `cw_pivx_sapling.h`.
Additional implementation update, 2026-06-04:
`bash cw_pivx/scripts/build_ios.sh` and `bash cw_pivx/scripts/build_android.sh` locally rebuilt the remaining mobile Sapling artifacts from the current Rust source. Local checkout commit was `e575783afd869f4d3292216106bea8aba2bbe0d8`, with uncommitted PIVX audit/native-tooling changes still present, so this remains local engineering evidence rather than release CI provenance. iOS SHA-256 hashes: `ios-arm64/libcw_pivx_sapling.a` = `5e17451c72c045598d69edfb68c0f0afb7ce34e817371162d3647a846275a9f4`; `ios-arm64_x86_64-simulator/libcw_pivx_sapling.a` = `09b7c2368846648043a5083946f1c6b9c830001f059a80990196bca0fc2bcf35`; `cw_pivx_sapling.h` = `4e521cfcf050679fcf57e887a8ff03cd712daa159989ebd8a57c241db9b1e3c8`; `Info.plist` = `bc358716655e7a67cf89e89bc89945ae689237dcdfa131e2009635ce16cd052b`. Android SHA-256 hashes: `arm64-v8a/libcw_pivx_sapling.so` = `fb0880f8d9f66c6d712b75927f62e0ab10b835802537aea151947fa6aea88960`; `armeabi-v7a/libcw_pivx_sapling.so` = `f7bb8991f3111865393497c0f46dcb315d0be456d808e37abaaa96e7900346d8`; `x86_64/libcw_pivx_sapling.so` = `9ccd98ec7055045e3628495423bd3c243d6e45e8b5a28e264cb5265cbd4c37a6`; `x86/libcw_pivx_sapling.so` = `4f5bf0be57e72a462dcfdebf7d577556e914e4c7025e022b0a54be91d57829dc`. The local iOS XCFramework directory is ignored by `cw_pivx/ios/.gitignore`, and the iOS build emitted deployment-target linker warnings for bundled `secp256k1` objects built for iOS/iOS-simulator 26.1 against linked targets 10.0/14.0. This keeps the finding open for exact release CI source provenance, tracked/packaged iOS artifact confirmation, iOS warning resolution or acceptance, and Android/iOS physical-device self-tests before external distribution.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-MOB-009: iOS ATS permits arbitrary loads globally, conflicting with a strict PIVX network-security posture

Severity: Medium
Status: Confirmed
Files:
- `ios/Runner/InfoBase.plist`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
Code references:
- `ios/Runner/InfoBase.plist:350-354`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:630-636`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:687-714`
Area: iOS release security, TLS policy, proving parameter acquisition
What is wrong:
iOS globally allows arbitrary network loads, while PIVX proving parameters and Electrum connections need a strict release policy.
Why it matters:
Global ATS relaxation weakens platform-level assurance and makes it harder to guarantee that PIVX release traffic uses approved TLS/proxy paths.
How to reproduce or verify:
Inspect `InfoBase.plist` and confirm `NSAllowsArbitraryLoads` is true.
Recommended fix:
Replace global ATS allowance with the narrowest required exceptions, and make PIVX proving-parameter hosts/TLS requirements explicit.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 8 - UI/UX Findings

### PIVX-UX-001: PIVX testnet/mainnet controls are hidden or ineffective

Severity: High
Status: Confirmed
Files:
- `lib/src/screens/new_wallet/advanced_privacy_settings_page.dart`
- `lib/view_model/wallet_creation_vm.dart`
- `lib/view_model/wallet_new_vm.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
Code references:
- `lib/src/screens/new_wallet/advanced_privacy_settings_page.dart:276-289`
- `lib/src/screens/new_wallet/advanced_privacy_settings_page.dart:318-325`
- `lib/view_model/wallet_creation_vm.dart:251-254`
- `lib/view_model/wallet_new_vm.dart:182-184`
- `cw_pivx/lib/src/pivx_wallet_service.dart:34-45`
- `cw_pivx/lib/src/pivx_wallet_service.dart:163-179`
- `cw_pivx/lib/src/pivx_wallet.dart:86-99`
Area: wallet creation/restore UX, mainnet/testnet safety
What is wrong:
The shared creation/restore flow has a `useTestnet` switch model, but the advanced settings UI only exposes it for Bitcoin and Decred. PIVX service methods accept `isTestnet` but do not pass it through, and `PivxWalletBase` always constructs with `PivxNetwork.mainnet`.
Why it matters:
Testers cannot safely choose or verify PIVX testnet from the UI, and future test builds can silently operate on mainnet while appearing to support testnet internally.
How to reproduce or verify:
Open PIVX create or restore advanced settings and confirm no testnet option is shown. Then force `useTestnet` through the view model and inspect the resulting PIVX wallet network.
Recommended fix:
Add an explicit PIVX network policy to create/restore UI, persist the selected network, pass it into PIVX create/open/restore, and display network state on receive/send/history.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-002: PIVX restore UI omits restore height and key-recovery affordances

Severity: High
Status: Confirmed
Files:
- `lib/view_model/wallet_restore_view_model.dart`
- `cw_pivx/lib/src/pivx_wallet_service.dart`
Code references:
- `lib/view_model/wallet_restore_view_model.dart:44-69`
- `lib/view_model/wallet_restore_view_model.dart:89-104`
- `lib/view_model/wallet_restore_view_model.dart:168-174`
- `cw_pivx/lib/src/pivx_wallet_service.dart:134-150`
Area: restore UX, wallet birthday, WIF/private-key recovery
What is wrong:
PIVX restore is seed-only in the UI, PIVX is excluded from the restore-height selector, and PIVX seed credentials do not carry a restore height. The PIVX service contains WIF restore logic, but PIVX key restore is not exposed by the UI.
Why it matters:
Users restoring PIVX, especially shielded wallets, lack the birthday/height control needed for safe and practical rescans. Users with WIF/private-key recovery material cannot discover the intended migration path.
How to reproduce or verify:
Start PIVX restore from seed/keys and confirm only seed mode is available and no block-height field appears.
Recommended fix:
Expose PIVX restore height/birthday input, define default behavior for Cake-created vs imported wallets, and add explicit seed/WIF/viewing-key restore choices aligned with the final recovery policy.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-003: PIVX shielded balance card renders Litecoin MWEB actions

Severity: High
Status: Needs Verification
Files:
- `lib/view_model/dashboard/balance_view_model.dart`
- `lib/src/screens/dashboard/pages/balance/balance_row_widget.dart`
Code references:
- `lib/view_model/dashboard/balance_view_model.dart:183-200`
- `lib/view_model/dashboard/balance_view_model.dart:336-351`
- `lib/src/screens/dashboard/pages/balance/balance_row_widget.dart:359-393`
- `lib/src/screens/dashboard/pages/balance/balance_row_widget.dart:471-590`
Area: amount/balance display, shield/deshield affordances
What is wrong:
PIVX uses the shared second-balance card for shielded balance, but the card body contains Litecoin MWEB Peg In/Peg Out controls, Litecoin payment URI generation, and MWEB coin-type arguments.
Why it matters:
PIVX users/testers can see incorrect Litecoin actions on a PIVX shielded balance card. Tapping them can create invalid payment requests, route to the wrong send mode, or crash depending on wallet casts.
How to reproduce or verify:
Open a PIVX wallet dashboard and inspect the second balance card. Confirm the card includes Litecoin MWEB peg controls when `hasSecondAvailableBalance` is true for PIVX.
Recommended fix:
Gate MWEB actions to Litecoin only. Add PIVX-specific shield/deshield controls only after the corresponding route is implemented, tested, and clearly labeled.
Implementation update, 2026-06-01:
The dashboard balance row now computes a Litecoin-only MWEB state from wallet type plus `CryptoCurrency.ltc`, uses it for the MWEB logo, and renders the Peg In/Peg Out controls only when that state is true. PIVX keeps the shielded confirmed/unconfirmed card but no longer shows Litecoin MWEB actions. `fvm dart analyze lib/src/screens/dashboard/pages/balance/balance_row_widget.dart` exits 0. Closure still requires Android/iOS PIVX dashboard screenshots/device evidence and product acceptance that PIVX shield/deshield buttons remain hidden while those routes are unsupported.
Implementation update, 2026-06-02:
Focused local regression coverage now pins the MWEB-control predicate used by the dashboard balance row. `fvm dart analyze lib/src/screens/dashboard/pages/balance/balance_row_widget.dart test/src/screens/dashboard/pages/balance/balance_row_widget_test.dart` exits 0, and `fvm flutter test test/src/screens/dashboard/pages/balance/balance_row_widget_test.dart --no-pub` passes all 3 focused MWEB-gating tests, including the PIVX/PIVX false case. Closure still requires Android/iOS dashboard screenshots/device evidence and product acceptance.
Implementation update, 2026-06-04:
The iPhone 16e iOS 26.1 simulator PIVX dashboard showed transparent `0.0` PIVX, shielded `0.1` PIVX, and no Litecoin MWEB branding/actions after height-aware shielded sync. This provides simulator evidence for the UI mitigation, but closure still requires Android/iOS physical-device screenshots and product acceptance that PIVX shield/deshield controls remain hidden while those routes are unsupported.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-004: PIVX send route UI implies unsupported transparent/shielded routes are available

Severity: High
Status: Confirmed
Files:
- `lib/src/screens/send/widgets/send_card.dart`
- `lib/view_model/send/send_view_model.dart`
- `lib/core/address_validator.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
Code references:
- `lib/src/screens/send/widgets/send_card.dart:762-792`
- `lib/view_model/send/send_view_model.dart:171-180`
- `lib/view_model/send/send_view_model.dart:303-324`
- `lib/core/address_validator.dart:156-163`
- `cw_pivx/lib/src/pivx_wallet.dart:1200-1205`
- `cw_pivx/lib/src/pivx_wallet.dart:1216-1250`
- `cw_pivx/lib/src/pivx_wallet.dart:1262-1275`
Area: send UX, route selection, address validation, unsupported feature messaging
What is wrong:
The send page exposes one checkbox, `Send from shielded balance`, instead of explicit t-to-t, t-to-z, z-to-t, and z-to-z route states. PIVX only routes to Sapling when the destination is shielded; transparent destinations fall through to the transparent parent path even when shielded input is selected. Direct transparent-to-external-shielded is rejected late, and the PIVX address validator accepts both mainnet and testnet shielded HRPs regardless of wallet network.
Why it matters:
Users can select combinations that the implementation does not support, discover failures only after amount/address entry, and fail to catch wrong-network shielded addresses before fee/build logic.
How to reproduce or verify:
Try PIVX sends for t-to-t, t-to-z, z-to-t, and z-to-z from the UI, including a `ptestsapling1...` destination in a mainnet wallet. Compare UI affordances with actual create-transaction routing.
Recommended fix:
Replace the checkbox with route-aware UI that detects source/destination pools, shows supported/disabled states, validates network HRPs, and explains unsupported routes before fee estimation.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-005: PIVX receive QR/URI/copy flow is not Sapling-aware

Severity: Medium
Status: Confirmed
Files:
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart`
- `lib/src/screens/receive/receive_page.dart`
- `lib/src/screens/receive/widgets/qr_widget.dart`
- `lib/core/payment_uris.dart`
Code references:
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:198-250`
- `lib/src/screens/receive/receive_page.dart:57-71`
- `lib/src/screens/receive/receive_page.dart:107-113`
- `lib/src/screens/receive/widgets/qr_widget.dart:70-78`
- `lib/src/screens/receive/widgets/qr_widget.dart:220-229`
- `lib/core/payment_uris.dart:256-269`
Area: receive UX, QR, payment URI, clipboard
What is wrong:
PIVX receive uses generic QR/share/copy handling and a generic Electrum disclaimer. `PivxURI` only emits `pivx:<address>?amount=...` and does not define Sapling memo support, pool metadata, or network metadata. Shielded address copying uses the normal clipboard.
Why it matters:
Shielded addresses and payment requests are privacy-sensitive metadata. Testers also lack clear guidance about whether the displayed QR is transparent or shielded, whether memos are supported, and whether the current node has scanned shielded funds.
How to reproduce or verify:
Open PIVX receive, select/share/copy a shielded address, and inspect the URI and disclaimer text.
Recommended fix:
Define PIVX transparent vs shielded receive copy/URI behavior, add network/pool labels, define memo policy, and decide whether shielded receive data should use sensitive clipboard/auto-clear behavior.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-UX-006: PIVX history lacks shielded entries, pool labels, and confirmation semantics

Severity: High
Status: Confirmed
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `lib/view_model/dashboard/transaction_list_item.dart`
- `lib/src/screens/dashboard/pages/transactions_page.dart`
- `lib/view_model/transaction_details_view_model.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:932-1037`
- `lib/view_model/dashboard/transaction_list_item.dart:57-63`
- `lib/view_model/dashboard/transaction_list_item.dart:65-115`
- `lib/src/screens/dashboard/pages/transactions_page.dart:96-106`
- `lib/view_model/transaction_details_view_model.dart:927-962`
Area: transaction history, labels, confirmations
What is wrong:
PIVX history fetch is transparent-address based, transaction list rows are generic Received/Sent, PIVX is not included in pending-confirmation formatting, and no PIVX tags exist for transparent, shielded, shield, deshield, z-to-z, or shielded receive.
Why it matters:
Users can receive or send shielded funds without a trustworthy history label or confirmation state. This compounds Stage 2's finding that shielded receives are not added to normal transaction history.
How to reproduce or verify:
Receive a shielded note and inspect history; send to transparent and shielded addresses and inspect list/detail labels and pending status.
Recommended fix:
Add PIVX-specific history items/tags for transparent and shielded flows, including confirmation depth, pending status, pool direction, and transaction detail fields appropriate for shielded metadata.
Implementation update, 2026-05-28:
PIVX shielded receive and outgoing z-to-z rows now carry `isPivxShielded`, `pivxPool`, and `pivxRoute` metadata, and the dashboard transaction list labels shielded receive/send rows with 6-confirmation pending status. Manual restart/history evidence is still required.
Implementation update, 2026-05-28:
PIVX shielded transaction detail rows now display pool, route, and shielded status. Pending shielded receives show confirmation progress, pending outgoing z-to-z sends are labeled as broadcast while awaiting a mined spend, and confirmed rows distinguish spendable shielded receives from confirmed shielded sends. Manual detail/restart verification remains required.
Implementation update, 2026-06-02:
Focused local regression coverage now pins the PIVX transaction-detail formatter for pending shielded receive progress, spendable shielded receive, outgoing broadcast awaiting mined spend, mined-but-not-final outgoing shielded send, confirmed outgoing shielded send, negative-confirmation clamping, and shielded/transparent pool plus route labels. `fvm dart analyze lib/view_model/transaction_details_view_model.dart test/view_model/pivx_transaction_details_view_model_test.dart` exits 0, and `fvm flutter test test/view_model/pivx_transaction_details_view_model_test.dart --no-pub` passes all 7 focused tests. Closure still requires restart/history persistence and manual receive/send detail checks on Android/iOS with Sapling-capable nodes.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-007: Shielded sync/progress/error states are hidden inside generic wallet sync

Severity: High
Status: Needs Verification
Files:
- `cw_pivx/lib/src/pivx_wallet.dart`
- `lib/pivx/pivx.dart`
- `lib/pivx/cw_pivx.dart`
- `lib/view_model/dashboard/dashboard_view_model.dart`
- `lib/src/screens/dashboard/widgets/sync_indicator.dart`
- `lib/src/screens/settings/connection_sync_page.dart`
- `lib/src/widgets/standard_list_status_row.dart`
- `lib/core/sync_status_title.dart`
Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:465-531`
- `cw_pivx/lib/src/pivx_wallet.dart:537-555`
- `lib/src/screens/dashboard/widgets/sync_indicator.dart:20-30`
- `lib/core/sync_status_title.dart:40-52`
Area: sync status, shielded progress, error visibility
What is wrong:
PIVX runs shielded sync after transparent sync and maps shield progress into the generic sync status. Shielded failures are logged and swallowed so the whole wallet sync can still appear usable. The shared sync indicator has no PIVX/Sapling-specific status text, capability check, last shielded height, or actionable shielded error.
Why it matters:
Users/testers can believe a PIVX wallet is synced while shielded scanning failed, was skipped, or is connected to a non-capable node.
How to reproduce or verify:
Connect to a reachable PIVX node without working Sapling RPC, sync a wallet, and observe dashboard status versus shielded receive/balance behavior.
Recommended fix:
Expose separate transparent and shielded sync states, show last shielded scanned height, surface Sapling RPC capability failures, and block/label shielded actions when shielded sync is not healthy.
Implementation update, 2026-05-28:
The PIVX facade and dashboard view model now expose shielded sync status, last shielded scanned height, Sapling RPC availability, and sanitized shielded sync errors. The dashboard sync pill uses PIVX shielded status text and remains unsynced while shielded sync is running or failed. The Connection/Sync page now shows a PIVX shielded sync status row with Sapling RPC readiness, scanned height, or shielded sync error. Closure still requires device/manual evidence against capable and non-capable nodes, plus route-specific disabled/actionable states.
Implementation update, 2026-06-04:
PIVX Sapling sync now logs sanitized height-only start, first completed range, coarse checkpoint, and final range messages. This gives manual simulator/device runs enough evidence to prove whether a wallet started shielded scanning at Sapling activation, an explicit restore height, or a conservative fresh-wallet birthday fallback without exposing txids, shielded addresses, note values, nullifiers, commitments, witness data, or raw RPC payloads. `fvm dart analyze cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart cw_pivx/lib/src/sapling/sapling_factories.dart cw_pivx/test/pivx_sapling_electrumx_test.dart` exits 0, and the later live-helper validation run supersedes this with `fvm flutter test cw_pivx/test/pivx_sapling_electrumx_test.dart --no-pub` passing all 20 focused tests. Closure still requires captured device/simulator evidence that UI status and height-aware logs agree.
Additional implementation update, 2026-06-04:
The iPhone 16e simulator run captured that agreement and one bug: the backend completed Sapling sync from `5440418` to `5440973`, but the dashboard stayed at `56 Blocks Remaining`. PIVX shielded final progress now clears the generic wallet sync status to `SyncedSyncStatus`, and `fvm flutter test cw_pivx/test/cw_pivx_test.dart --no-pub` passes all 15 focused PIVX tests including the regression. A hot-restart simulator rerun completed `5440974-5440976`, emitted `SYNC_STATUS_CHANGE: Synced`, and the dashboard showed `Shielded synced 5440976` with the expected transparent/shielded balances. Closure still requires physical-device evidence, non-capable-node/actionable-error checks, and default-node live helper readiness.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-UX-008: PIVX node/proxy/Tor settings do not expose Sapling capability or per-node privacy state

Severity: Medium
Status: Needs Verification
Files:
- `lib/src/screens/settings/connection_sync_page.dart`
- `lib/view_model/dashboard/dashboard_view_model.dart`
- `lib/view_model/node_list/node_create_or_edit_view_model.dart`
- `lib/src/screens/nodes/widgets/node_form.dart`
Code references:
- `lib/src/screens/settings/connection_sync_page.dart:44-95`
- `lib/view_model/dashboard/dashboard_view_model.dart:1066-1095`
- `lib/view_model/node_list/node_create_or_edit_view_model.dart:63-77`
- `lib/src/screens/nodes/widgets/node_form.dart:177-255`
Area: node settings, proxy/Tor visibility, Sapling capability
What is wrong:
The UI exposes generic node management and global built-in Tor, but does not show whether the selected PIVX node supports Sapling RPC. Per-node SOCKS proxy controls exist in the form but are rendered under the auth-credentials section, which PIVX does not use.
Why it matters:
Testers cannot tell whether shielded features are failing because of wallet state, node capability, proxy/Tor routing, or unsupported server RPCs.
How to reproduce or verify:
Open PIVX node edit settings and confirm no Sapling capability indicator or SOCKS proxy controls are visible for PIVX nodes.
Recommended fix:
Show PIVX Sapling capability/version status per node, expose effective Tor/proxy routing for PIVX, and add a clear disabled state when the active node cannot support shielded operations.
Implementation update, 2026-05-28:
The node form now renders SOCKS proxy controls for PIVX nodes, not only auth-based node types, and PIVX manual node testing fails when the node is reachable but lacks Sapling block-range capability. Persistent per-node capability/version status is now partially implemented but still needs capable/non-capable node verification, so the finding remains Needs Verification.
Implementation update, 2026-05-28:
The Connection/Sync page now surfaces the active PIVX wallet's Sapling RPC readiness and last shielded scanned height through wallet status. This helps distinguish wallet shielded sync state from generic node connectivity, but durable per-node capability/version metadata still depends on the ElectrumX v1 capability contract and node-list UI evidence.
Implementation update, 2026-05-28:
PIVX `Node` records now persist Sapling capability/version metadata, and the node list shows a cached per-node Sapling readiness/status line with network, activation height, and advertised contract/server/Core version when available. This still needs capable/non-capable node evidence on device and default-node v1 metadata proof before closure.
Implementation update, 2026-06-02:
The node list now distinguishes `Sapling v1 ready` from `Sapling legacy only`, and persisted PIVX Sapling readiness is set from the explicit v1 release-contract predicate. This is local wallet/UI hardening only; screenshots and device runs against capable/non-capable deployed nodes are still required.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-UX-009: Backup/security copy does not explain or expose PIVX Sapling recovery material

Severity: Medium
Status: Confirmed
Files:
- `lib/src/screens/settings/security_backup_page.dart`
- `lib/view_model/wallet_keys_view_model.dart`
Code references:
- `lib/src/screens/settings/security_backup_page.dart:119-136`
- `lib/view_model/wallet_keys_view_model.dart:166-187`
- `lib/view_model/wallet_keys_view_model.dart:299-306`
Area: backup/security UX, viewing keys, recovery guidance
What is wrong:
PIVX Show Keys follows the Bitcoin-like WIF/private/public/xPub path and does not expose PIVX Sapling viewing keys or shielded recovery metadata. Backup/restore QR params include seed/private key/height/passphrase but no PIVX Sapling sidecar/viewing-key policy.
Why it matters:
Users cannot tell whether backups cover shielded state, whether seed-only restore recovers shielded funds, or how viewing-key import/export should work.
How to reproduce or verify:
Open Security & Backup -> Show Keys for PIVX and inspect available keys; generate a wallet backup/restore URI and inspect PIVX-specific recovery fields.
Recommended fix:
Add PIVX-specific backup text and key export/import policy for Sapling viewing keys, restore height, diversified addresses, and sidecar state inclusion/exclusion.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-UX-010: Unsupported feature and release tester guidance is insufficient

Severity: Medium
Status: Confirmed
Files:
- `lib/src/screens/send/widgets/send_card.dart`
- `cw_pivx/lib/src/pivx_wallet.dart`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart`
- `docs/audits/pivx-cake-wallet/08_ui_ux_audit.md`
Code references:
- `lib/src/screens/send/widgets/send_card.dart:762-792`
- `cw_pivx/lib/src/pivx_wallet.dart:1262-1275`
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:198-250`
Area: unsupported feature messaging, release tester guidance
What is wrong:
PIVX shielded features are visible in receive/send/balance UI, but unsupported routes and unsafe states are mostly communicated by late generic exceptions or not at all. There is no product/tester-facing guide in the UI that names supported routes, required node capability, restore-height expectations, known blockers, and expected failures.
Why it matters:
External testers may report known blockers as random bugs or, worse, attempt real-value flows on paths that the app has not actually implemented safely.
How to reproduce or verify:
Walk through PIVX create, restore, receive, send, node settings, and backup as a tester without audit context; note that the UI does not distinguish implemented, experimental, disabled, and blocked shielded features.
Recommended fix:
Add explicit PIVX beta/tester guidance and feature-state messaging before external distribution. Disable or label unsupported routes until implementation and tests are complete.
Blocks APK testing: No
Blocks TestFlight: Yes
