# Stage 9 - Manual Test Plan

Status: Complete; not yet executed for release readiness.

Date: 2026-05-27

Last updated: 2026-06-04

Scope: manual validation plan for PIVX release readiness, derived from Stages 2-8. This plan is intended for internal QA first; it should not be used to justify external APK/TestFlight release until the blockers in `09_release_gate_checklist.md` are closed.

Execution status as of 2026-05-28: no external APK/TestFlight readiness upgrade has been earned. The highest-priority manual tests for the current wallet-side mitigations are `RESTORE-004`, `RECV-Z-003`, `SEND-ZZ-001`, `SEND-TZ-001` disabled-route behavior if still unsupported, `SEND-ZT-001` disabled-route behavior if still unsupported, `NET-POL-001`, and `RESTORE-001`. Also verify ambiguous PIVX source-pool sends to shielded addresses are blocked before construction.

## Test Principles

- Use throwaway wallets only until the release gate explicitly permits real-value testing.
- Run every test with a recorded build ID, git commit, platform, device model, OS version, native Sapling library version/hash, PIVX Core version, ElectrumX Sapling server version, node URL, and network.
- Keep mainnet and testnet test runs separate. Never paste a testnet shielded address into a mainnet wallet or the reverse.
- Sanitize all logs before sharing. Logs must not include seed phrases, viewing/spending keys, shielded addresses, note values, nullifiers, cmu values, witness data, or payment URIs unless explicitly approved for an internal secure report.
- A test passes only if UI state, wallet state after restart, transaction history, node state, and recovery behavior all match the expected result.

## Required Test Environments

### Mobile Targets

- Android physical device, release-signed APK, arm64.
- Android physical device, release-signed APK, 32-bit ABI if supported.
- Android emulator or physical x86_64 only if that ABI is shipped.
- iPhone physical device via TestFlight or equivalent internal distribution before TestFlight.
- Optional simulator checks may supplement iOS UI work but do not replace physical-device native Sapling tests.

### Node And Chain Targets

- PIVX Core canonical release for the test cycle, currently expected to be PIVX Core 5.6.1 unless changed by release owner.
- Sapling-capable ElectrumX fork with a frozen versioned RPC contract.
- At least one non-Sapling PIVX Electrum node for negative capability tests.
- Testnet if relaunched and wired end to end; otherwise controlled mainnet dust-only testing with explicit approval.
- Funding source or faucet for transparent funds and shielded funds.
- Ability to mine/confirm blocks or wait for confirmations.
- Ability to simulate RPC failures, unsupported RPC methods, malformed responses, dropped connections, and reorgs on a controlled environment.

### Required Sapling RPC Capability Probe

Before running wallet tests, record whether the selected node supports the release contract:

- Sapling capability/version method or agreed equivalent.
- `get_block_range` or release-equivalent block scan method.
- Nullifier status lookup.
- Commitment info or global output position source, if used.
- Anchor/tree-state lookup.
- Witness lookup or documented client-side witness construction data.
- Broadcast path for shielded transactions.
- Explicit error response for unsupported methods and daemon failures.
- Cake Wallet height-only shielded sync log evidence showing the selected start height, first completed range, coarse checkpoints for long scans, and final completed range.

For bundled default-node evidence, run:

`fvm dart run tool/pivx_sapling_default_node_probe.dart`

If a node is intentionally offline for reindexing, record the release-owner reason and rerun the same command after reindex completion. For targeted retests, pass endpoints such as `electrum01.chainster.org:50002:ssl`.

Expected result: shielded receive/send tests are not valid unless this probe passes capability, sampled range, and live helper-method validation. `live_helper_methods_ready` must be `true`; `blockchain.sapling.get_best_anchor`, the dummy all-zero nullifier-status probe, and the dummy all-zero commitment-info probe must not fail or return malformed responses for the wallet's v1 parser. The app must visibly disable or warn on shielded features when the probe fails. Shared logs may include shielded sync heights/ranges only; they must not include txids, shielded addresses, note values, nullifiers, commitments, witness data, or raw RPC response bodies.

## Mainnet/Testnet Policy Tests

### NET-POL-001: Wallet Network Selection

1. Create a PIVX wallet with mainnet selected.
2. Create a PIVX wallet with testnet selected, if testnet is exposed for the build.
3. Restore both networks from known seeds.
4. Record transparent prefixes, Sapling HRPs, activation height, default node, and wallet metadata after restart.

Expected result: selected network is honored and persisted. Mainnet wallets never accept testnet addresses for send, and testnet wallets never accept mainnet addresses.

### NET-POL-002: Build Flavor And Release Notes Match Behavior

1. Compare build flavor, UI network selector, release notes, and actual wallet network.
2. Attempt to change nodes to a node from the opposite network.
3. Attempt to scan/restore a seed on the wrong network.

Expected result: product messaging, wallet metadata, address validation, nodes, and Sapling constants agree. Wrong-network configuration is blocked or clearly marked.

## Wallet Creation Tests

### CREATE-001: New PIVX Wallet Determinism

1. Create a new PIVX wallet.
2. Record first transparent receive address and default shielded address.
3. Close and reopen the app.
4. Restore the same seed/passphrase into a second wallet.

Expected result: transparent account-0 index-0 and default shielded address reproduce exactly. No seed or shielded metadata appears in logs.

### CREATE-002: Different Passphrase Produces Different Keys

1. Restore the same mnemonic with passphrase A.
2. Restore the same mnemonic with passphrase B.
3. Compare first transparent and shielded addresses.

Expected result: both transparent and shielded addresses differ between passphrases.

### CREATE-003: Native Sapling Availability

Preflight before device runs:

1. Run `fvm dart run tool/pivx_sapling_native_self_test.dart` against the packaged desktop artifact where available.
2. Run `PIVX_SAPLING_LIBRARY_PATH=<rebuilt artifact path> fvm dart run tool/pivx_sapling_native_self_test.dart` for each release-candidate native artifact before it is packaged.
3. Record platform, artifact path, source commit, artifact hash, `cw_pivx_version`, and pass/fail output.

Expected preflight result: every release-candidate artifact passes load, symbol, version, and Core-fee parity checks. A failure such as `native=25000 expected=1417000` means the artifact is stale and must be rebuilt before device testing can count.

2026-06-04 local preflight evidence: macOS, iOS, and Android Sapling artifacts were rebuilt from the current Rust source and SHA-256 hashes were recorded in `09_release_gate_checklist.md`. This does not replace release CI provenance or packaged physical-device self-tests. The iOS rebuild also needs release-owner review of deployment-target linker warnings for bundled `secp256k1` objects built for iOS/iOS-simulator 26.1 against linked targets 10.0/14.0, and confirmation that the generated XCFramework is tracked/packaged as intended.

1. Launch the app on each target ABI/platform.
2. Create/open a PIVX wallet.
3. Trigger default shielded address generation and Sapling sync startup.

Expected result: no native library load crash. The app reports Sapling availability accurately and disables shielded actions if native loading fails.

## Restore Tests

### RESTORE-001: Invalid Seed Redaction

1. Enter an invalid PIVX mnemonic containing realistic seed words.
2. Submit restore.
3. Inspect UI error, app logs, crash/error copy text, and support log export if available.

Expected result: entered seed text is never displayed, logged, copied, or crash-reported.

### RESTORE-002: Transparent Gap Recovery

1. Fund receive and change addresses beyond the initial PIVX restore window and beyond at least two gap-extension batches.
2. Restore from seed.
3. Let transparent discovery complete.
4. Compare recovered addresses, balance, and history against a full derivation scan.

Expected result: all funded receive/change addresses are recovered until a full unused gap is proven.

### RESTORE-003: Shielded Birthday/Height

1. Create a wallet with a known shielded receive at height H.
2. Restore with a birthday before H.
3. Restore with a birthday after H only if the UI explicitly warns that old funds may be missed.
4. Record scanned start height and final balance/history.

Expected result: safe restore recovers the note. Risky restore heights are blocked or require explicit informed acceptance.

### RESTORE-004: Shielded Notes After Restart

1. Receive shielded notes across blocks containing unrelated Sapling outputs.
2. Restart after sync.
3. Reopen with a current sidecar that includes a persisted global tree cursor.
4. Reopen or migrate a legacy sidecar that has owned note positions but no persisted global tree cursor.
5. Spend one note if z-to-z is enabled.
6. Compare note positions/nullifiers with canonical Core/indexer data.

Expected result: restored notes have correct global positions/nullifiers and remain spendable. Legacy sidecars without a trusted cursor do not resume post-activation scanning unless the node returns explicit global positions.

### RESTORE-005: Spent Shielded Note Restore

1. Receive a shielded note.
2. Spend it through an enabled shielded route.
3. Restore from seed/birthday.
4. Sync past receive and spend heights.

Expected result: wallet shows historical receive/spend and does not count spent notes as spendable.

### RESTORE-006: Diversified Address Reuse

1. Generate at least three diversified shielded receive addresses.
2. Receive funds to a non-default diversified address.
3. Restore from seed only.
4. Generate a new shielded address.

Expected result: restored wallet recovers funds and does not silently present a previously used diversified address as newly generated.

### RESTORE-007: WIF/Private-Key Policy

1. Attempt PIVX WIF/private-key restore or sweep according to the advertised release scope.
2. Use a valid PIVX WIF with dust funds.

Expected result: if supported, funds are swept/imported correctly. If unsupported, UI blocks the flow with safe migration guidance and no unimplemented exception.

## Receive Tests

### RECV-T-001: Transparent Receive

1. Create a fresh wallet.
2. Copy a transparent PIVX receive address.
3. Send dust transparent funds to it.
4. Wait for confirmations and restart.

Expected result: transparent balance and transaction history update correctly and survive restart.

### RECV-Z-001: Default Shielded Receive

1. Copy the default shielded address.
2. Send a shielded note to it from a known-good wallet/Core setup.
3. Sync through confirmation threshold.
4. Restart and resync.

Expected result: shielded pending/confirmed/spendable balances follow policy, transaction history shows the receive, and logs do not leak shielded metadata.

### RECV-Z-002: Additional Shielded Address Receive

1. Generate an additional diversified shielded address.
2. Reopen the receive list.
3. Send funds to that address.
4. Restart and verify address list/current selection.

Expected result: no receive-list crash, funds are found, address label/index persists as intended, and history labels the receive as shielded.

### RECV-Z-003: Empty Range Versus Failed Range

1. Sync through a genuinely empty Sapling block range.
2. Simulate RPC failure for a range containing a wallet note.
3. Simulate a v1 `get_block_range` envelope with `complete: false` and one with mismatched `from_height`/`to_height`.
4. Restore RPC behavior and sync again.

Expected result: empty ranges advance normally. Failed ranges retry or stop with visible shielded sync error and do not advance scan height.

### RECV-Z-004: Reorg Receive

1. Receive a shielded note in a controlled environment.
2. Reorg out the receive block.
3. Continue sync beyond the replacement chain.

Expected result: pending/confirmed/spendable balance and history roll back or update according to policy.

## Send Route Tests

Run only routes enabled by the release matrix. Disabled routes must be tested for clean blocking.

### SEND-TT-001: Transparent To Transparent

1. Fund transparent balance.
2. Send dust to another transparent PIVX address.
3. Test normal amount, send-max, low fee, and dust boundary.
4. Restart before and after confirmation.

Expected result: transaction builds, broadcasts, confirms, appears in history, and balance updates correctly.

### SEND-TZ-001: Transparent To Shielded

1. Fund transparent balance.
2. Enter a shielded destination.
3. Build and broadcast, if route is enabled.
4. If disabled, attempt the route from the UI.

Expected result: enabled route confirms and appears as shield/shielded receive. Disabled route is blocked before transaction creation with route-specific text.

### SEND-ZZ-001: Shielded To Shielded

1. Fund shielded balance with at least two notes.
2. Wait until notes are spendable by policy.
3. Send a partial amount to another shielded address.
4. Restart immediately after broadcast and again after confirmation.

Expected result: selected nullifiers are reserved/pending spent, duplicate spend is prevented, change is correct, history shows outgoing shielded spend, and confirmed state reconciles after sync.

### SEND-ZT-001: Shielded To Transparent

1. Fund shielded balance.
2. Select shielded source and transparent destination.
3. Build and broadcast, if route is enabled.
4. If disabled, attempt the route from the UI.

Expected result: enabled route confirms and appears as deshield. Disabled route must not fall through to transparent sending.

### SEND-Z-ALL-001: Shielded Send Max

1. Fund shielded balance with one note.
2. Press send-all/max in shielded mode.
3. Repeat with multiple notes where the first note covers amount but not amount plus fee.
4. Repeat near dust/change thresholds.

Expected result: UI amount and transaction amount are numeric and fee-aware. Note selection includes enough notes for amount plus fee, Sapling fees include PIVX Core's shielded fee factor `100`, shielded outputs below `1,446,000` zatoshis are blocked, shielded change at or below `1,446,000` zatoshis is suppressed into the fee, and dust/change policy matches PIVX Core mempool acceptance.

### SEND-Z-CONF-001: Spend Confirmation Policy

1. Receive a shielded note.
2. Attempt to spend before required depth.
3. Attempt again after required depth.

Expected result: early spend is blocked with clear status. Spend succeeds after maturity if route is enabled.

### SEND-Z-ANCHOR-001: Witness/Anchor Consistency

1. Build a shielded spend while new blocks are arriving, or mock changing anchor responses.
2. Compare witness root/anchor to the anchor passed to signing.

Expected result: wallet uses one selected anchor and rejects mismatched witnesses.

### SEND-Z-PARAM-001: Proving Parameters

1. Delete local proving parameters.
2. Enable Tor/proxy according to release policy.
3. Attempt first shielded send.
4. Interrupt download, retry, and confirm only a `.download` temp file is left or cleaned up; no partial final parameter file should be accepted.
5. Corrupt a cached final parameter file and retry.
6. Repeat under low-storage conditions and, on iOS, background/foreground the app during download.

Expected result: download uses approved policy and Cake's Tor/proxy path, progress/errors are visible, partial files do not poison retries, hashes/sizes are verified before `initProver`, and corrupted files are replaced or rejected safely.

## Balance And History Tests

### BAL-001: Pool-Specific Display

1. Hold transparent-only funds.
2. Hold shielded-only funds.
3. Hold both.
4. Toggle route/source controls and inspect send-page balance.

Expected result: displayed spendable balance matches selected route/source pool. Combined totals are not presented as spendable for unsupported routes.

### BAL-002: Pending Outgoing Shielded

1. Broadcast a shielded spend.
2. Before confirmation, try another spend using the same funds.
3. Kill and reopen the app.

Expected result: pending outgoing state survives restart and prevents duplicate spending.

### BAL-003: Failed Broadcast

1. Build a shielded transaction.
2. Simulate broadcast rejection.
3. Inspect balances, pending state, and history.

Expected result: selected notes are released or marked failed according to policy, and the UI shows an actionable error.

### HIST-001: Pool Labels And Confirmations

1. Execute every enabled route.
2. Inspect transaction list and detail screens before and after confirmation.

Expected result: each item has correct direction, amount, fee, txid, pool/route label, confirmation state, and restart persistence.

## Sync And Error-State Tests

### SYNC-001: Transparent Sync Failure

1. Use a node that returns null/malformed transparent balance.
2. Sync.

Expected result: prior transparent balance is preserved or marked stale; it is not silently overwritten to zero.

### SYNC-002: Shielded Sync Failure

1. Connect to a node without Sapling RPC support.
2. Open a wallet with shielded funds.
3. Attempt receive sync and shielded send.
4. Capture the sanitized shielded sync error and confirm no raw RPC payload or shielded metadata appears in logs.

Expected result: shielded sync status shows capability failure, shielded actions are disabled or clearly blocked, and generic wallet sync does not imply Sapling success.

### SYNC-003: Node Auto-Switch

1. Start on a Sapling-capable node.
2. Force failure so auto-switch selects another node.
3. Include one non-Sapling node in candidate list.

Expected result: auto-switch never silently moves shielded wallets to a non-Sapling node, or shielded features visibly disable with a clear reason.

### SYNC-003B: PIVX Node Capability Badges

1. Add or open one v1 Sapling-capable PIVX ElectrumX node and one reachable non-Sapling PIVX Electrum node.
2. Open Manage nodes and wait for the node rows to finish probing.
3. Confirm the capable node row shows Sapling readiness plus network, activation height, and advertised contract/server/Core version when available.
4. Confirm the non-capable node row shows Sapling unavailable and cannot be mistaken for a shielded-ready node.
5. Restart the app and reopen Manage nodes.

Expected result: per-node Sapling capability/version status persists across restart, refreshes without looping, and agrees with manual shielded sync/send behavior.

### SYNC-003C: PIVX Shielded Sync Start-Height Evidence

1. Select an upgraded v1-capable default PIVX node and record its capability metadata.
2. Restore or open one wallet with an explicit nonzero restore height near the current tip.
3. Open the wallet and wait for shielded sync to start.
4. Capture sanitized logs for `PIVX Sapling` sync start, first completed range, any checkpoint range, and final range.
5. Repeat with a wallet that has no explicit restore height, using throwaway funds only.

Expected result: explicit-height wallets start shielded sync at the persisted restore height or Sapling activation if the selected height is before activation. Fresh non-recovery wallets without a restore height use the conservative birthday fallback. Logs prove heights/ranges without exposing shielded metadata.

2026-06-04 simulator execution note: iPhone 16e iOS 26.1 completed the current-build PIVX wallet shielded sync from `5440418` to `5440973`, displayed transparent `0.0` and shielded `0.1`, exposed a stale `56 Blocks Remaining` dashboard status after final Sapling completion, then passed a hot-restart rerun after the status fix with `Shielded synced 5440976`. This supplements the manual plan but does not replace physical-device evidence or capable/non-capable node checks.

### SYNC-004: Offline Rescan

1. Start shielded rescan.
2. Disconnect before the first range fetch.
3. Reopen wallet.

Expected result: cleared/rescanned state does not leave stale shielded balances, and rescan can resume safely.

### SYNC-005: App Lifecycle

1. Background during shielded sync.
2. Kill during range processing.
3. Kill after broadcast and before confirmation.
4. Reopen and resync.

Expected result: persisted sync height/tree state, notes, nullifiers, pending sends, and balances remain consistent.

## Backup And Security Tests

### SEC-001: Sapling Sidecar At Rest

1. Receive shielded funds.
2. Inspect app document storage on a test device.
3. Search for note values, txids, nullifiers, rseed, diversifier, pk_d, labels, and addresses.

Expected result: sensitive Sapling state is encrypted or absent from plaintext storage.

### SEC-002: Cake Backup Policy

1. Create a Cake backup from a PIVX wallet with transparent and shielded activity.
2. Inspect backup contents according to the allowed internal process.
3. Restore from backup on another device.

Expected result: backup behavior matches policy. If Sapling state is included, it is encrypted. If excluded, seed plus restore height recovers funds correctly.

### SEC-003: Logs And Crash/Error Copy

1. Trigger invalid seed, shielded receive, shielded send, RPC failure, witness failure, and broadcast failure.
2. Inspect runtime logs, saved logs, crash dialogs, and copy-to-clipboard error flows.

Expected result: no seed phrase, key material, note metadata, nullifier, cmu, witness, txid linkage, payment URI, or balance leaks unless explicitly allowed in secure internal debug mode.

### SEC-004: Clipboard

1. Copy seed, wallet keys, shielded address, transparent address, payment URI, and error text.
2. Observe clipboard auto-clear behavior and sensitive clipboard UI.

Expected result: seed/key flows use sensitive clipboard. Shielded address/URI behavior matches the chosen PIVX privacy policy.

### SEC-005: Screenshots And App Switcher

1. Open seed, wallet keys, PIVX restore, shielded receive QR, transaction details, and error screens.
2. Background app and attempt screenshots with privacy setting off and on.

Expected result: forced-protection screens are protected regardless of global setting; optional screens follow product policy.

### SEC-006: FFI Memory Boundary

1. Review or instrument seed handoff to FFI.
2. Confirm Dart and native seed buffers are wiped before free.
3. Confirm native key manager disposal path is exercised on wallet close.

Expected result: key-material memory handling matches documented release policy.

## QR, URI, And Address Validation Tests

### QR-001: Transparent QR/URI

1. Generate transparent receive QR and `pivx:` URI.
2. Scan from another wallet.
3. Include amount and note fields if supported.

Expected result: URI parses correctly, sends to the transparent address, and rejects incompatible shielded-only fields.

### QR-002: Shielded QR/URI

1. Generate shielded receive QR and URI.
2. Scan into Cake and a known-good external wallet/Core-supported tool if available.
3. Test amount, memo/note, label, special characters, max memo length, and no-memo cases.

Expected result: shielded address and optional fields follow the chosen PIVX URI/memo spec. Unsupported fields are blocked or ignored with clear behavior.

### QR-003: Network Mismatch

1. Scan mainnet transparent and shielded addresses into a testnet wallet.
2. Scan testnet transparent and shielded addresses into a mainnet wallet.

Expected result: mismatch is rejected before fee estimation or transaction creation.

### QR-004: Malformed And Mixed Inputs

1. Paste malformed PIVX addresses, wrong HRP shielded addresses, Bitcoin/Litecoin addresses, mixed-case values, and partial URIs.

Expected result: validation errors are specific and do not crash.

## UI/UX Regression Tests

### UX-001: PIVX Shielded Balance Card

1. Open dashboard with shielded balance enabled.
2. Inspect secondary balance card actions.

Expected result: no Litecoin MWEB peg actions appear for PIVX. PIVX-only actions appear only if implemented and enabled.

### UX-002: Route UI Disabled States

1. Try each disabled route from the send screen.
2. Try insufficient balance, immature note, non-Sapling node, missing params, and wrong network.

Expected result: errors are route-specific, actionable, and shown before expensive build/signing work where possible.

### UX-003: Shielded Sync Visibility

1. Open a wallet during transparent sync, shielded sync, shielded RPC failure, and shielded complete states.
2. Compare dashboard/Connection status with the sanitized height-only shielded sync logs.

Expected result: dashboard distinguishes transparent sync from shielded sync and shows last shielded height/capability/error.

### UX-004: Backup/Restore Messaging

1. Open security/backup, show keys, create backup, restore, and release notes.

Expected result: UI explains PIVX seed restore, restore height, WIF/viewing-key availability, and Sapling backup policy accurately.

## Release Tester Dry Run

Before external distribution, run one full dry run as if the tester had no internal context:

1. Give tester only the proposed release guide, build, node list, funding instructions, and reporting template.
2. Ask tester to create, fund, receive, send through enabled routes, restore, back up, scan QR/URI, switch nodes, and report one simulated failure.
3. Collect report and verify no secret data was requested or included.

Expected result: tester can complete all supported flows without private Slack/context, does not attempt disabled routes with real value, and reports failures with enough sanitized detail for engineering.

## Minimum Pass Set For Limited External Readiness

Limited external readiness requires all of the following to pass on each target platform:

- Network policy tests: `NET-POL-001`, `NET-POL-002`.
- Creation tests: `CREATE-001`, `CREATE-002`, `CREATE-003`.
- Restore tests: `RESTORE-001` through `RESTORE-006`, plus `RESTORE-007` if WIF/private-key support is advertised.
- Receive tests: `RECV-T-001`, `RECV-Z-001`, `RECV-Z-002`, `RECV-Z-003`.
- Every enabled send route test; every disabled route must pass clean-blocking behavior.
- Balance/history tests: `BAL-001`, `BAL-002`, `BAL-003`, `HIST-001`.
- Sync/error tests: `SYNC-001` through `SYNC-005`.
- Security tests: `SEC-001` through `SEC-005`; `SEC-006` must be completed by engineering review or instrumentation.
- QR/URI tests: `QR-001` through `QR-004`.
- UI/UX tests: `UX-001` through `UX-004`.
- Release tester dry run.
