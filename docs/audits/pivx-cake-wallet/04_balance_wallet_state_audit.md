# Stage 4 - Balance And Wallet State Audit

Status: Complete.

Date: 2026-05-27

Scope: PIVX balance and wallet state correctness only. This pass used Stage 2 and Stage 3 findings as context, did not audit new receive/send construction details beyond their balance effects, and did not modify production code.

## Verdict

PIVX balance and wallet state are NOT READY for external APK or TestFlight testing.

The wallet has separate transparent and shielded balance paths, but shielded state is not modeled deeply enough for a spendable mobile wallet. Shielded notes are counted as confirmed/spendable immediately, pending shielded balance is always zero, outgoing shielded sends do not reserve or mark notes locally, send-max is not fee-aware, and restart/rescan/failure/reorg paths can show stale or unspendable shielded balances.

## Findings Summary

- Critical: 0
- High: 6
- Medium: 3
- Low: 0

## Audited Files

- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart`
- `cw_pivx/lib/src/sapling/sapling_factories.dart`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart`
- `cw_pivx/rust/src/sync.rs`
- `cw_pivx/rust/src/ffi.rs`
- `cw_bitcoin/lib/electrum_balance.dart`
- `cw_bitcoin/lib/electrum_wallet.dart`
- `lib/view_model/dashboard/balance_view_model.dart`
- `lib/view_model/send/send_view_model.dart`
- `lib/view_model/send/output.dart`
- `lib/src/screens/send/widgets/send_card.dart`
- `lib/view_model/unspent_coins/unspent_coins_list_view_model.dart`
- `lib/bitcoin/cw_bitcoin.dart`

## Balance Flow Map

Transparent balance:

- `cw_pivx/lib/src/pivx_wallet.dart:813-876` fetches transparent address balances from Electrum and returns an `ElectrumBalance`.
- `cw_pivx/lib/src/pivx_wallet.dart:835-845` computes frozen transparent amount from `UnspentCoinsInfo`.
- `cw_pivx/lib/src/pivx_wallet.dart:870-876` attaches shielded values as `secondConfirmed` and `secondUnconfirmed`.

Shielded balance:

- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:242-248` defines shielded balance as the sum of all stored notes where `isSpent == false`.
- `cw_pivx/lib/src/sapling/sapling_factories.dart:223-230` exposes `pendingBalance` as always `0`.
- `cw_pivx/lib/src/pivx_wallet.dart:511-515` copies sync-engine balance into `shieldedBalance` and `pendingShieldedBalance`.
- `cw_pivx/lib/src/pivx_wallet.dart:867-876` exposes those fields through `ElectrumBalance.secondConfirmed` and `secondUnconfirmed`.

UI balance:

- `cw_bitcoin/lib/electrum_balance.dart:12-17` maps `secondConfirmed` to `secondAvailable`.
- `cw_bitcoin/lib/electrum_balance.dart:60-61` formats full available balance as transparent confirmed + transparent unconfirmed + shielded confirmed - frozen.
- `lib/view_model/dashboard/balance_view_model.dart:182-200` labels PIVX secondary balances as shielded and shielded unconfirmed.
- `lib/view_model/send/send_view_model.dart:272-280` displays PIVX send-page balance as full combined available balance.
- `lib/view_model/send/send_view_model.dart:302-325` uses separate pool values for send-all depending on `coinTypeToSpendFrom`.

## Findings

### PIVX-BAL-001: Shielded notes are counted as confirmed and spendable immediately

Severity: High
Status: Confirmed
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
Any stored shielded note with `isSpent == false` is included in `storage.balance`, while `pendingBalance` always returns `0`. There is no confirmation depth, spendable depth, locked note state, or pending-receive state before exposing the value as `secondConfirmed` / shielded available balance.
Why it matters:
New shielded receives can appear as confirmed/spendable too early, and the UI cannot distinguish pending, confirmed, and actually spendable shielded funds.
How to reproduce or verify:
Receive a shielded note and inspect balance immediately after the block is scanned. `secondConfirmed` increases and `secondUnconfirmed` remains zero.
Recommended fix:
Persist note block height, scanned block hash, confirmation depth, and spendability state. Only include notes in spendable/confirmed balance after the configured confirmation policy; expose pending shielded receives through `secondUnconfirmed`.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-002: Restart balance can include notes that are not restorable for spending

Severity: High
Status: Confirmed
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
On initialization, `_loadShieldedBalanceFromStorage()` counts all unspent stored notes. Then `_restoreNotesToNativeEngine()` restores only notes with `hasSpendingData`; notes missing rseed/diversifier/pk_d/nullifier are skipped. The balance can therefore include notes that are not loaded into the native engine and cannot be selected/spent.
Why it matters:
Users can see shielded funds as available after restart while transaction creation says no spendable notes or fails during note selection.
How to reproduce or verify:
Create or modify a stored note missing one spending-data field, restart the wallet, and compare displayed shielded balance with the native spendable notes restored by `restoreNotesFromStorage()`.
Recommended fix:
Separate observed balance from spendable balance. During startup, classify notes missing spending data as unavailable/recovery-needed and exclude them from spendable/send-all balances until a successful rescan repairs the note data.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-003: Outgoing shielded sends do not update pending or spendable balance until mined and rescanned

Severity: High
Status: Confirmed
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
Successful shielded broadcast calls `updateBalance()` and `syncShielded()`, but selected notes are not marked pending spent and no pending outgoing balance is recorded. Stored notes are marked spent only when a later scanned block contains their nullifier.
Why it matters:
After a send, the wallet can keep showing the spent shielded notes as available and can attempt another send from the same notes. If the app is killed after broadcast, there is no durable outgoing pending state to reconcile.
How to reproduce or verify:
Broadcast a shielded z-to-z transaction, then inspect shielded balance before the spending nullifier is mined/scanned. The selected notes remain in unspent balance.
Recommended fix:
Persist outgoing pending shielded transactions and selected nullifiers before/at successful broadcast. Move their value out of spendable balance immediately, and reconcile to confirmed spent, failed, or available through chain/broadcast status.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-004: Shielded send-max and fee deduction are not balance-correct

Severity: High
Status: Confirmed
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
PIVX shielded send-all uses `secondAvailable` as the full send amount, without subtracting the Sapling fee. The visible amount is changed to localized "all", which parses to `0` in PIVX amount parsing. Independently, shielded note selection chooses notes for `amount` before fee and then fails if selected total is less than `amount + fee`.
Why it matters:
The wallet cannot correctly spend max shielded balance, can present an amount that is not actually spendable, and can reject valid spends when additional notes could cover the fee.
How to reproduce or verify:
Use PIVX shielded mode, press Send all, and try to create a transaction. Also test notes where the first selected note covers amount but not amount plus fee while another note exists.
Recommended fix:
Implement a PIVX shielded spendable-balance API that calculates send-max after note selection, fees, change, and dust policy. Keep the UI display string separate from the integer amount used by transaction creation.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-005: Combined full balance suggests cross-pool spendability that is not implemented

Severity: High
Status: Confirmed
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
The wallet exposes total/full available balance as transparent plus shielded, but cross-pool spending is not implemented. t-to-z and z-to-t paths throw or fall through, and shielded notes are not UTXOs. A user can see a combined balance that cannot be spent in a single transaction or from the selected pool.
Why it matters:
The send screen can overstate what is spendable for a given destination/source pool, creating failed sends and tester confusion around funds that appear available.
How to reproduce or verify:
Hold 1 PIV transparent and 1 PIV shielded, then attempt to send 2 PIV to a transparent address or shielded address. The displayed full balance can imply 2 PIV available, but the needed cross-pool flow is unsupported.
Recommended fix:
Display pool-specific spendable balances in PIVX send flows. Do not use combined full balance as spendable unless cross-pool selection/transaction construction is implemented and tested.
Blocks APK testing: Yes
Blocks TestFlight: Yes

### PIVX-BAL-006: Stale shielded balance can survive zero-balance storage, failed sync, or aborted rescan

Severity: High
Status: Confirmed
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
`_loadShieldedBalanceFromStorage()` only updates the wallet balance map when `storedBalance > 0`. If the encrypted wallet snapshot has a nonzero prior secondary balance but Sapling storage is empty or cleared, the old in-memory `initialBalance` can remain. During shielded rescan, storage is cleared and native state reset, but if `syncShielded()` aborts due to no connection, the previous `shieldedBalance` is not immediately zeroed or marked stale.
Why it matters:
After restart, rescan, or connectivity failure, the UI can show shielded funds that are no longer present in local Sapling storage.
How to reproduce or verify:
Start with nonzero shielded balance, clear/rescan shielded storage while offline, or open a wallet whose encrypted snapshot still has `secondConfirmed` while Sapling storage has zero notes. Observe whether the displayed shielded balance is cleared.
Recommended fix:
On startup and rescan, explicitly set shielded confirmed/pending/spendable state from the authoritative Sapling storage state even when zero. Mark shielded balance stale/unavailable when sync cannot run after destructive local state changes.
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
The parent Electrum wallet detects null balance responses, marks sync as lost connection, and returns the previous balance. The PIVX override does not preserve that guard; it treats missing `confirmed` / `unconfirmed` fields as zero.
Why it matters:
A node/API failure can make transparent PIVX balance display as zero instead of stale/unknown, which is confusing and can corrupt saved balance state.
How to reproduce or verify:
Mock `electrumClient.getBalance()` to return a map with null or missing `confirmed` during `PivxWallet.fetchBalances()`. The returned `ElectrumBalance` uses zero totals.
Recommended fix:
Port the parent null-response handling into the PIVX override and preserve last known balance while setting lost-connection/stale status.
Implementation update, 2026-06-01:
`PivxWallet.fetchBalances()` now detects transparent Electrum balance responses missing `confirmed` or `unconfirmed`, sets `LostConnectionSyncStatus`, and returns the previous transparent balance instead of converting missing fields to zero. It keeps the current shielded secondary balance values in the returned `ElectrumBalance`. `fvm dart analyze cw_pivx/lib/src/pivx_wallet.dart` exits 0 with only pre-existing snapshot deprecation infos, and `fvm flutter test cw_pivx/test --no-pub` passes all 65 PIVX tests. This remains open for malformed-node/device evidence.
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
For PIVX, the send view `balance` getter displays `formattedFullAvailableBalance`, which includes both transparent and shielded. The send-all helper uses pool-specific values, but the main displayed balance does not change with `coinTypeToSpendFrom`.
Why it matters:
Users can believe the selected source pool has more funds than it does. This is especially confusing when a destination type cannot spend from both pools.
How to reproduce or verify:
Open a PIVX wallet with transparent and shielded funds, toggle "Send from shielded balance", and compare the visible balance text with the actual source-pool spendable amount.
Recommended fix:
Make the PIVX send-page balance source-pool aware. Show transparent, shielded, and total separately, or clearly bind the primary send balance to the selected source pool.
Implementation update, 2026-06-01:
The PIVX send view now binds the displayed-balance fallback to the selected source pool while the async send-balance lookup is loading: transparent mode falls back to transparent available balance and shielded mode falls back to shielded `secondAvailable`. The send-balance refresh helper also recomputes for PIVX transparent/shielded source changes. `fvm dart analyze lib/view_model/send/send_view_model.dart` exits 0. This remains open for manual mixed-pool send-screen evidence.
Blocks APK testing: No
Blocks TestFlight: Yes

### PIVX-BAL-009: Shielded balance has no rollback/reorg model

Severity: Medium
Status: Confirmed
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
A reorg can leave shielded balance too high, too low, or notes incorrectly marked spent until the user performs a full rescan. This is a medium-risk lifecycle issue for beta testing.
How to reproduce or verify:
On regtest/testnet, receive or spend a shielded note, then reorg out the block and continue sync. Inspect whether the note/spent state rolls back automatically.
Recommended fix:
Persist scanned block hashes and per-block note/nullifier effects. On reorg, roll back to a safe common ancestor and rescan forward.
Blocks APK testing: No
Blocks TestFlight: Yes

## Stage 4 Stop Point

Per staged workflow, this pass stops after balance and wallet state. Next stage should audit restore and key derivation.
