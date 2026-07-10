# Stage 8 - UI/UX Audit

Status: Complete.

Scope:
- PIVX wallet creation/restore, mainnet/testnet affordances, receive UI for transparent and shielded addresses, send UI and route selection, amount/balance display, history labeling, sync/progress/error states, node/proxy/Tor visibility, backup/security copy, QR/payment URI behavior, unsupported-feature messaging, and release tester guidance.
- Production code was not modified.

## Verdict

PIVX is not ready for external APK distribution or TestFlight from a UI/UX perspective.

The UI exposes PIVX as a normal wallet type and adds several shielded-specific affordances, but those affordances do not yet match the actual Sapling support matrix or the risk state from Stages 2-7. The biggest tester-facing risks are: testnet controls are hidden/ineffective, restore lacks PIVX restore-height and key-recovery controls, the shielded balance card renders Litecoin MWEB actions for PIVX, the send UI implies route support that is not implemented, shielded transaction history/status is missing, and Sapling sync failures are easy to miss.

## Evidence Reviewed

### Wallet Creation And Mainnet/Testnet

- The shared wallet creation view model tracks `useTestnet` and passes it to the wallet creation service.
- The advanced settings page only shows the testnet switch for Bitcoin and Decred, not PIVX.
- PIVX wallet service `create()` and `restoreFromSeed()` accept `isTestnet` but do not pass it into the wallet constructor.
- `PivxWalletBase` always constructs the underlying wallet with `PivxNetwork.mainnet`.

Code references:
- `lib/view_model/wallet_creation_vm.dart:251-254`
- `lib/view_model/wallet_new_vm.dart:182-184`
- `lib/src/screens/new_wallet/advanced_privacy_settings_page.dart:276-289`
- `cw_pivx/lib/src/pivx_wallet_service.dart:34-45`
- `cw_pivx/lib/src/pivx_wallet_service.dart:163-179`
- `cw_pivx/lib/src/pivx_wallet.dart:86-99`

Assessment:
The product has an internal testnet model, but PIVX users/testers cannot select it from creation/restore, and even if set programmatically it is ignored by the active PIVX wallet construction path.

### Restore Flow

- PIVX restore mode is seed-only in the shared restore view model.
- The restore-height selector is only shown for Monero, Haven, and Wownero.
- PIVX restore credentials do not carry a restore height/birthday.
- Existing PIVX WIF restore service code is not reachable through the PIVX restore UI.

Code references:
- `lib/view_model/wallet_restore_view_model.dart:44-69`
- `lib/view_model/wallet_restore_view_model.dart:89-104`
- `lib/view_model/wallet_restore_view_model.dart:168-174`
- `cw_pivx/lib/src/pivx_wallet_service.dart:134-150`

Assessment:
This conflicts with the Stage 5 restore requirement to expose a PIVX restore birthday/height path and recovery guidance. It also hides available WIF/private-key recovery behavior.

### Receive UI

- When Sapling is enabled, PIVX receive list prepends a shielded section, shows a shared shielded balance, adds the default shielded address as primary, then adds transparent addresses.
- Additional shielded addresses are read from the PIVX sidecar and parsed as string `diversifierIndex`.
- The receive page uses the same generic Electrum disclaimer for PIVX unless it is Bitcoin silent payments.
- QR/share/copy use a generic `pivx:` URI and normal clipboard behavior.

Code references:
- `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart:198-260`
- `lib/src/screens/receive/receive_page.dart:57-71`
- `lib/src/screens/receive/receive_page.dart:107-113`
- `lib/src/screens/receive/widgets/qr_widget.dart:70-78`
- `lib/src/screens/receive/widgets/qr_widget.dart:220-229`
- `lib/core/payment_uris.dart:256-269`

Assessment:
The receive surface is pointed in a reasonable direction, but it lacks PIVX-specific warnings/status for shielded readiness, memo/URI rules, testnet network labeling, and privacy clipboard policy.

### Balance Display

- PIVX maps the second balance labels to `Shielded` and `Shielded unconfirmed`.
- PIVX always enables the second balance card.
- 2026-06-01 wallet-side mitigation: the shared second-balance card now gates Litecoin MWEB branding and Peg In/Peg Out controls to Litecoin/LTC rows only. PIVX keeps the shielded balance display but no longer renders Litecoin payment requests or MWEB coin-type arguments from that card.

Code references:
- `lib/view_model/dashboard/balance_view_model.dart:183-200`
- `lib/view_model/dashboard/balance_view_model.dart:336-351`
- `lib/src/screens/dashboard/pages/balance/balance_row_widget.dart:359-393`
- `lib/src/screens/dashboard/pages/balance/balance_row_widget.dart:471-590`

Assessment:
This was a serious release/testing affordance bug. The wallet-side mitigation now needs Android/iOS dashboard evidence before the gate can close, and PIVX shield/deshield actions must remain hidden unless those routes are implemented and manually accepted.

### Send UI And Route Selection

- The PIVX send page shows a single checkbox captioned `Send from shielded balance`.
- The checkbox only toggles input pool; it does not show destination pool, route type, required confirmations, memo support, unsupported routes, or why a route is disabled.
- PIVX transaction creation routes to Sapling only when the destination is shielded. Transparent destinations still go through the parent transparent path even if the UI is toggled to shielded input.
- Transparent-to-external-shielded is explicitly unsupported after validation/build begins.
- The address validator accepts both `ps1...` and `ptestsapling1...` for PIVX regardless of wallet network.

Code references:
- `lib/src/screens/send/widgets/send_card.dart:762-792`
- `lib/view_model/send/send_view_model.dart:171-180`
- `lib/view_model/send/send_view_model.dart:303-324`
- `cw_pivx/lib/src/pivx_wallet.dart:1200-1205`
- `cw_pivx/lib/src/pivx_wallet.dart:1216-1250`
- `cw_pivx/lib/src/pivx_wallet.dart:1262-1275`
- `lib/core/address_validator.dart:156-163`

Assessment:
The UI suggests a route matrix broader than the implementation. Testers can select shielded mode for transparent sends, enter testnet shielded addresses in a mainnet wallet, and only discover unsupported routes through late generic failures.

### Transaction History And Details

- PIVX transaction fetching is transparent-address-history based.
- PIVX transaction list titles use generic Received/Sent.
- PIVX is not included in the wallet types with pending-confirmation formatting.
- Transaction rows tag Bitcoin silent payments and Litecoin MWEB, but there are no PIVX tags for transparent, shielded, shield, deshield, z-to-z, or shielded receive.
- PIVX details show standard id/date/height/amount/fee/source/recipient fields only.

Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:932-1037`
- `lib/view_model/dashboard/transaction_list_item.dart:57-63`
- `lib/view_model/dashboard/transaction_list_item.dart:65-115`
- `lib/src/screens/dashboard/pages/transactions_page.dart:96-106`
- `lib/view_model/transaction_details_view_model.dart:927-962`

Assessment:
The UI cannot reliably tell users whether a PIVX transaction was transparent or shielded, and Stage 2 already found shielded receives are not added to normal history at all.

### Sync, Progress, And Error States

- PIVX runs transparent sync first, then shielded sync.
- Shielded sync updates the generic wallet `syncStatus` with a normal `SyncingSyncStatus`, but the shared sync title has no PIVX/Sapling context.
- Shielded sync failures are logged and intentionally do not fail the whole wallet sync.
- If the Electrum connection is unavailable, shielded sync logs and returns.

Code references:
- `cw_pivx/lib/src/pivx_wallet.dart:465-531`
- `cw_pivx/lib/src/pivx_wallet.dart:537-555`
- `lib/src/screens/dashboard/widgets/sync_indicator.dart:20-30`
- `lib/core/sync_status_title.dart:40-52`

Assessment:
Users/testers can see a generally synced wallet while Sapling sync failed, was skipped, or is only partially complete. There is no separate shielded sync status, Sapling capability status, last shielded height, or actionable shielded error.

### Node, Proxy, And Tor Settings

- Connection settings expose Manage Nodes and global built-in Tor.
- Node create/edit supports `useSocksProxy` and `socksProxyAddress` in the view model.
- The node form renders proxy controls only inside the auth-credentials section, which PIVX does not use.
- Node UI does not show Sapling RPC capability, supported route matrix, or whether the selected node can scan/build shielded transactions.

Code references:
- `lib/src/screens/settings/connection_sync_page.dart:44-95`
- `lib/view_model/dashboard/dashboard_view_model.dart:1066-1095`
- `lib/view_model/node_list/node_create_or_edit_view_model.dart:63-77`
- `lib/src/screens/nodes/widgets/node_form.dart:177-255`

Assessment:
PIVX network privacy/capability state is not visible enough for testers. The UI cannot distinguish a reachable transparent Electrum node from a Sapling-capable PIVX node.

### Backup, Security, And Key Copy

- Security & Backup exposes Show Keys and Create Backup through shared flows.
- PIVX Show Keys follows the Bitcoin-like WIF/private/public/xPub path and does not expose Sapling viewing keys or shielded recovery metadata.
- Wallet QR/backup URI query params include seed/private key/restore height/passphrase, but no PIVX Sapling state or viewing-key policy.

Code references:
- `lib/src/screens/settings/security_backup_page.dart:119-136`
- `lib/view_model/wallet_keys_view_model.dart:166-187`
- `lib/view_model/wallet_keys_view_model.dart:299-306`

Assessment:
The UI does not tell users whether Cake backups include PIVX Sapling sidecar state, whether seed-only restore is sufficient for shielded funds, or how to export/import PIVX viewing keys.

### Disabled/Unsupported Messaging And Tester Guidance

- Unsupported PIVX routes are mostly expressed as generic late exceptions.
- Sapling-disabled/native-library unavailable states remove shielded receive affordances but the send page still has a PIVX shielded input toggle based only on currency.
- There is no in-app PIVX tester guidance describing supported routes, known blockers, required node capability, restore-height expectations, or which screens are expected to fail until Stage 2-7 blockers are resolved.

Assessment:
External testers would need out-of-band instructions to avoid misleading UI paths. Until then, many failures will look like ordinary user mistakes instead of known release blockers.

## Findings

Stage 8 findings are recorded in `11_findings_register.md`:

- `PIVX-UX-001` High: PIVX testnet/mainnet controls are hidden or ineffective.
- `PIVX-UX-002` High: PIVX restore UI omits restore height and key-recovery affordances.
- `PIVX-UX-003` High: PIVX shielded balance card rendered Litecoin MWEB actions; wallet-side mitigation added on 2026-06-01 and awaiting device evidence.
- `PIVX-UX-004` High: PIVX send route UI implies unsupported transparent/shielded routes are available.
- `PIVX-UX-005` Medium: PIVX receive QR/URI/copy flow is not Sapling-aware.
- `PIVX-UX-006` High: PIVX history lacks shielded entries, pool labels, and confirmation semantics.
- `PIVX-UX-007` High: Shielded sync/progress/error states are hidden inside generic wallet sync.
- `PIVX-UX-008` Medium: PIVX node/proxy/Tor settings do not expose Sapling capability or per-node privacy state.
- `PIVX-UX-009` Medium: Backup/security copy does not explain or expose PIVX Sapling recovery material.
- `PIVX-UX-010` Medium: Unsupported feature and release tester guidance is insufficient.

## Recommended UX Release Gates

Before external APK/TestFlight:

1. Add a PIVX network policy to create/restore UI and ensure the selected network is persisted and honored.
2. Add PIVX restore-height/birthday UI and explicit seed/WIF/viewing-key restore guidance.
3. Remove Litecoin MWEB actions from the PIVX shielded balance card and replace them with PIVX shield/deshield actions only after those routes are implemented and tested.
4. Replace the single send checkbox with explicit route detection/status: t-to-t, t-to-z, z-to-t, z-to-z, disabled state, required confirmations, memo availability, and selected source balance.
5. Add network-aware PIVX address validation and reject mainnet/testnet mismatches before fee estimation.
6. Add PIVX-specific receive copy/QR/URI rules, including shielded memo policy and privacy clipboard behavior.
7. Add PIVX shielded transaction-history entries and visible tags for transparent, shielded, shield, deshield, and z-to-z transactions.
8. Split transparent and shielded sync status in the dashboard, including last shielded height, node Sapling capability, and actionable errors.
9. Expose PIVX Sapling node capability/proxy/Tor status in node settings.
10. Provide a release tester guide that names supported routes, disabled routes, required node setup, expected error messages, and known blockers.

## Implementation Notes

2026-05-28:

- PIVX shielded history/detail semantics are partially mitigated: shielded receive and z-to-z rows carry pool/route/confirmation metadata, dashboard rows label shielded receive/send, and transaction details now show Pool, Route, and Shielded status.
- PIVX node capability UI is partially mitigated: node records persist Sapling capability/version metadata and Manage nodes displays cached readiness/version status after probing.
- These UX findings remain open until manual capable/non-capable node tests, transaction detail restart checks, and default-node v1 metadata evidence pass.

2026-06-01:

- PIVX shielded balance card MWEB leakage is wallet-side mitigated: `BalanceRowWidget` now renders Litecoin MWEB logo and Peg In/Peg Out actions only when the wallet is Litecoin and the balance row is LTC. `fvm dart analyze lib/src/screens/dashboard/pages/balance/balance_row_widget.dart` exits 0.
- `PIVX-UX-003` remains `Needs Verification` until Android/iOS PIVX dashboard evidence confirms no MWEB branding/actions are visible and product accepts that PIVX shield/deshield controls are hidden until those routes are implemented.
