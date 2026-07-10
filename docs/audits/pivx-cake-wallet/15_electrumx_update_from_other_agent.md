# PIVX Sapling ElectrumX Support Status

## Summary

Implemented production-oriented PIVX Sapling ElectrumX support for Cake Wallet, including Sapling parsing, indexing, RPC contract discovery, block-range scanning, nullifier/commitment lookup, anchor/tree/witness APIs, and reorg-safe rollback behavior.

## Core Contract

Primary contract identifier:

`pivx.sapling.electrumx.v1`

Capability probe:

`blockchain.sapling.capabilities`

The capability response advertises:
- supported methods and aliases
- Sapling activation height
- max block range
- range response format
- structured error types

## Block Range API

Method:

`blockchain.sapling.get_block_range`

Response is an envelope, not a bare list:

- `success`
- `complete`
- `empty`
- `start_height`
- `end_height`
- `height_count`
- `block_count`
- `sapling_tx_count`
- `block_hashes`
- `blocks`
- `error`

Important behavior:
- Empty successful ranges return `success: true`, `complete: true`, `empty: true`.
- Failed/partial ranges return `success: false`, `complete: false`, structured `error`.
- A failed range can never look complete.
- `block_hashes` includes every scanned height, even blocks with no Sapling transactions, so clients can detect stale scanned state.

## Sapling Indexing

Implemented canonical global Sapling output positions.

Positions are assigned in:
1. block height order
2. PIVX Core transaction order within block
3. vShieldOutput order within transaction

Empty blocks do not consume positions.

Persisted indexes include:
- nullifier to spending tx
- commitment to creating tx/output/position
- global position to commitment
- anchor to height
- indexed root to tree size/height

## Witness API

Method:

`blockchain.sapling.get_witness`

Returns anchor-bound witness data:

- `anchor`
- `root`
- `anchor_height`
- `position`
- `path`
- `commitment`

Witness paths verify against the requested indexed anchor/root.

## Reorg Handling

PIVX ElectrumX keeps:

`Pivx.REORG_LIMIT = 100`

Cake Wallet should rescan the last 100 inclusive heights unless policy changes.

Sapling rollback removes reverted:
- nullifiers
- commitments
- global positions
- anchors
- indexed roots

Rollback rewinds `sapling_output_count` to the lowest removed position, so new-branch outputs reuse reverted positions while earlier outputs stay stable.

## Client Reorg Detection

Cake Wallet should persist block hashes per scanned height.

On resume:

`start = max(SAPLING_START_HEIGHT, last_scanned_height - 99)`

Then compare local hashes against `get_block_range(...).block_hashes`.

Any mismatch means local Sapling scanned state is stale and should be rewound to the last matching height.

## Activation Heights

Confirmed against PIVX Core v5.6.1:

- Mainnet Sapling activation: `2700500`
- Testnet Sapling activation: `201`

Source:
- PIVX Core release tag `v5.6.1`
- release commit `af60f19`
- `src/chainparams.cpp`

## Tests Added / Covered

Tests cover:
- Sapling parser structure and real block parsing
- rollback policy and activation heights
- reorg removing Sapling outputs/spends/anchors/roots/positions
- nullifier respent on different branch
- full rollback-boundary rescan
- returned block hashes for stale-state detection
- range rejection beyond max block range
- empty successful ranges
- daemon failure
- unsupported daemon method
- invalid range
- partial/index-incomplete responses
- stable positions across restart
- empty blocks not consuming positions
- canonical block response ordering
- witness path verification against requested anchor

## Verification

Passing:

`PYTHONPATH=. pytest tests/lib/test_pivx_sapling.py tests/lib/test_pivx_sapling_real.py tests/server/test_pivx_sapling_reorg.py -q`

Result:

`62 passed`

## Cake Wallet Follow-Up

2026-05-28 wallet-side follow-up applied:

- Cake Wallet now probes `blockchain.sapling.capabilities` before the older `blockchain.sapling.get_capabilities` fallback.
- The wallet stores advertised capability/version/network/activation metadata on PIVX node records and displays cached Sapling readiness/version status in the node list.
- Dart/Rust testnet Sapling activation constants now use `201`, matching this report.

This remains incoming evidence, not a release gate closure, until Cake Wallet is manually tested against the reported v1 server/default nodes and the release owner records independent PIVX Core source evidence.

2026-06-03 live default-node retest:

- `electrum02.chainster.org:50002` and `:50001` refused connections during the latest probe, so the default SSL node was not available for Cake Wallet validation.
- `electrum01.chainster.org:50001` returned complete `pivx.sapling.electrumx.v1` capability metadata with `release_contract_ready: true`.
- `electrum01.chainster.org:50002` still returned an incomplete v1 block-range envelope for `blockchain.sapling.get_block_range [2700500, 2700599]`: `success: false`, `complete: false`, `error.type: index_incomplete`, `error.message: Sapling commitment is not indexed`, height `2700502`, txid `0c7d177ee5952f2a0d27fc25ae48cbf08ee0908fac9e5cc1b164b788c10fb608`, commitment `958a58f6c519d9f06fa3cd6c1bfbc8e3869d2b46d914443c139e0f2222bc9a21`.

Result: capability metadata is no longer the only blocker, but default-node readiness remains blocked until both default deployments are reachable and the Sapling commitment/global-position indexes are backfilled from activation so Cake Wallet can complete v1 `get_block_range` scans.

2026-06-04 live `electrum01` retest:

- `electrum01.chainster.org:50002` now returns complete `pivx.sapling.electrumx.v1` capability metadata: `release_contract_ready: true`, mainnet, Sapling activation `2700500`, required v1 methods, global output positions, block hashes, and structured errors.
- Previously failing range `blockchain.sapling.get_block_range [2700500, 2700599]` now returns `success: true`, `complete: true`, `empty: false`, `height_count: 100`, `block_hash_count: 100`, `block_count: 22`, and `sapling_tx_count: 30`.
- Previously failing range `blockchain.sapling.get_block_range [2700900, 2700999]` now returns `success: true`, `complete: true`, `empty: false`, `height_count: 100`, `block_hash_count: 100`, `block_count: 7`, and `sapling_tx_count: 8`.
- Later empty-range spot check `blockchain.sapling.get_block_range [2705000, 2705099]` returns `success: true`, `complete: true`, `empty: true`, `height_count: 100`, `block_hash_count: 100`, `block_count: 0`, and `sapling_tx_count: 0`.

Result: `electrum01` has progressed from capability-only readiness to returning complete v1 range envelopes for sampled activation and later ranges. Keep default-node release evidence open until Cake Wallet shielded sync completes against the node and `electrum02` finishes reindexing/resyncing and passes the same probes.

2026-06-04 Cake Wallet iOS simulator birthday-height retest:

- Live tip from `electrum01.chainster.org:50002` was `5440392`; a restored simulator PIVX wallet with `restoreHeight: 0` was therefore scanning from Sapling activation `2700500`, which would require roughly 2.74 million historical blocks.
- For the manual retest, the iPhone 16e simulator wallet metadata row `pivx_PIVX` was updated to requested restore height `5440400`.
- After relaunch, Cake Wallet created `Documents/pivx_sapling_pivx_PIVX_mainnet.json.enc`, returned to `Synced`, and no sanitized PIVX Sapling failure message surfaced in the observed Flutter log stream.
- The app log stream is still too generic to prove exact block-range heights because `ElectrumClient` logs response ids/result types without method names or parameters. Treat this as simulator smoke evidence that the wallet can avoid activation-height scanning when a restore height is present, not as final shielded-sync completion evidence.
- Wallet-side code was tightened so first shielded sync now honors any nonzero `walletInfo.restoreHeight` when Sapling storage is empty, not only recovery wallets. Fresh non-recovery wallets with no restore height now get a conservative timestamp-derived birthday fallback. Focused verification: `fvm dart analyze cw_pivx/lib/src/pivx_wallet.dart cw_pivx/test/cw_pivx_test.dart` exits 0 with only pre-existing `pivx_wallet.dart` deprecation infos, and `fvm flutter test cw_pivx/test/cw_pivx_test.dart --no-pub` passes all 14 focused PIVX tests.

2026-06-04 Cake Wallet shielded-sync observability update:

- Cake Wallet now logs sanitized height-only PIVX Sapling sync evidence: sync start height/target height, first completed block range, coarse 10,000-block checkpoints, and final completed range.
- The ElectrumX block-range callback now carries both range start and range end to wallet-side sync code, allowing future simulator/device logs to prove whether shielded sync used activation height, explicit restore height, or fresh-wallet birthday fallback without logging txids, shielded addresses, note values, nullifiers, commitments, witness data, or raw RPC responses.
- Focused verification: `fvm dart analyze cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart cw_pivx/lib/src/sapling/sapling_factories.dart cw_pivx/test/pivx_sapling_electrumx_test.dart` exits 0, and the later live-helper validation run supersedes this with `fvm flutter test cw_pivx/test/pivx_sapling_electrumx_test.dart --no-pub` passing all 20 focused ElectrumX/sync-observability/helper-validation tests.

Result: this removes the previous "logs are not height-aware enough" blocker for the next manual run, but it does not close default-node readiness. Capture new height-aware logs while syncing against `electrum01`, repeat once `electrum02` is reachable after reindexing, and keep `PIVX-NET-002`/`PIVX-NET-003` open until Cake Wallet shielded sync completion is proven on simulator/device.

2026-06-04 repeatable default-node probe tooling/evidence:

- Added `tool/pivx_sapling_default_node_probe.dart` in Cake Wallet to probe the bundled PIVX Electrum nodes without wallet secrets. It records server version, Sapling capability method, contract id, release-ready classification, network, activation height, global-position/block-hash support, required method presence, and sampled `get_block_range` summaries.
- `fvm dart analyze tool/pivx_sapling_default_node_probe.dart` exits 0.
- A full default-node run at `2026-06-04T00:50:13Z` found `electrum02.chainster.org:50002` and `:50001` refusing connections. The release owner/user reported `electrum02` is reindexing, so this remains pending expected downtime evidence rather than final non-capability evidence.
- `fvm dart run tool/pivx_sapling_default_node_probe.dart electrum01.chainster.org:50002:ssl electrum01.chainster.org:50001:plain` at `2026-06-04T00:51:09Z` showed both `electrum01` SSL and plain endpoints reachable with `server_version ["ElectrumX 1.19.0","1.4"]`, capability method `blockchain.sapling.capabilities`, contract `pivx.sapling.electrumx.v1`, `release_contract_ready: true`, mainnet activation `2700500`, block hashes, global output positions, and all required v1 methods.
- `electrum01` SSL and plain both returned complete sampled v1 range envelopes for `2700500-2700599` (`height_count=100`, `block_hash_count=100`, `block_count=22`, `sapling_tx_count=30`), `2700900-2700999` (`height_count=100`, `block_hash_count=100`, `block_count=7`, `sapling_tx_count=8`), and `2705000-2705099` (`height_count=100`, `block_hash_count=100`, `empty=true`, `block_count=0`, `sapling_tx_count=0`).

Result: `electrum01` now has repeatable wallet-side v1 metadata/range evidence for both SSL and plain endpoints. Default-node readiness remains open until `electrum02` completes reindexing and passes the same probe, node-list UI/device evidence is captured, and Cake Wallet shielded sync completion is proven with the height-aware logs.

2026-06-04 live helper-method retest:

- The default-node probe now also calls safe live v1 helper methods without wallet secrets: `blockchain.sapling.get_best_anchor`, dummy `blockchain.sapling.get_nullifier_status`, and dummy `blockchain.sapling.get_commitment_info`.
- `fvm dart run tool/pivx_sapling_default_node_probe.dart electrum01.chainster.org:50002:ssl electrum01.chainster.org:50001:plain` at `2026-06-04T01:08:20Z` showed both `electrum01` endpoints still advertising complete v1 metadata and returning complete sampled ranges, but `blockchain.sapling.get_best_anchor` returned `internal server error` on both SSL and plain endpoints. Dummy nullifier status returned `spent=false`; dummy commitment info returned `null`.
- Cake Wallet was tightened so `PIVXSaplingElectrumX.probeCapabilities()` now rejects advertised v1 nodes when safe live helper validation fails. This prevents node-list readiness and automatic switching from treating an advertised-but-broken v1 node as release-ready when z-to-z spend construction would later fail at best-anchor lookup.
- Focused verification: `fvm dart analyze cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart cw_pivx/test/pivx_sapling_electrumx_test.dart tool/pivx_sapling_default_node_probe.dart` exits 0, and `fvm flutter test cw_pivx/test/pivx_sapling_electrumx_test.dart --no-pub` passes all 20 focused ElectrumX capability/envelope/witness/live-helper tests.

Result: default-node readiness is still blocked even for `electrum01` until live `get_best_anchor` succeeds. `electrum02` remains pending reindex completion and the same probe.

2026-06-04 bundled-default retest:

- `fvm dart run tool/pivx_sapling_default_node_probe.dart` at `2026-06-04T01:23:31Z` still found `electrum02.chainster.org:50002` and `:50001` refusing connections.
- `electrum01.chainster.org:50002` and `:50001` remained reachable with `ElectrumX 1.19.0`, `blockchain.sapling.capabilities`, contract `pivx.sapling.electrumx.v1`, mainnet activation `2700500`, block hashes, global output positions, all required v1 methods, and complete sampled range envelopes for `2700500-2700599`, `2700900-2700999`, and `2705000-2705099`.
- Both `electrum01` endpoints still returned RPC `-32603` internal server error for `blockchain.sapling.get_best_anchor`; dummy nullifier status remained `spent=false`, dummy commitment-info remained `null`, and `live_helper_methods_ready=false`.

Result: no default-node gate closes from this retest. Keep `electrum01` blocked on live best-anchor/commitment-info contract compatibility, and keep `electrum02` pending post-reindex reachability plus the same capability/range/helper probe.

2026-06-04 targeted electrum01 retest:

- `fvm dart run tool/pivx_sapling_default_node_probe.dart electrum01.chainster.org:50002:ssl electrum01.chainster.org:50001:plain` at `2026-06-04T01:28:32Z` was unchanged.
- Both endpoints remained reachable with complete v1 metadata and complete sampled range envelopes.
- Both endpoints still returned RPC `-32603` internal server error for `blockchain.sapling.get_best_anchor`; dummy nullifier status remained `spent=false`, dummy commitment-info remained `null`, and `live_helper_methods_ready=false`.

Result: `electrum01` remains blocked on live helper validation. The wallet-side fail-closed behavior is still required until the server returns a usable best-anchor response and the unknown commitment-info response shape is confirmed or adjusted.
