# Stage 6 - Network And Configuration Audit

Status: Complete.

Scope covered:

- Mainnet/testnet selection
- Node defaults and automatic node switching
- ElectrumX Sapling RPC compatibility
- Sapling activation heights
- Transparent prefixes and Sapling HRPs
- Fee and dust policies
- Proving parameter acquisition
- Native library loading and release build configuration
- Tor/proxy behavior
- Release/test configuration risk

## Executive Verdict

PIVX network/configuration is not ready for external APK or TestFlight release.

The largest Stage 6 risks are:

- PIVX wallet construction is hard-coded to `PivxNetwork.mainnet`, while service APIs still accept `isTestnet`.
- Default and fallback PIVX nodes are not tied to the required custom Sapling ElectrumX fork or to a verified Sapling RPC capability check.
- The Dart Sapling client, in-repo Sapling docs, and known local ElectrumX fork use incompatible RPC method names.
- Sapling activation heights are inconsistent across Dart constants and Rust/Electrum client code.
- Fee and dust rules differ across transparent Dart code, Sapling Dart constants, Sapling FFI validation, and Rust transaction validation.
- Proving parameters are downloaded at send time from third-party hosts. The active downloader now uses Cake's proxy wrapper, hash/size checks, and temp-file promotion, but there is still no bundled/offline release path, no streaming/resume behavior, no canonical PIVX host evidence, and conflicting parameter metadata remains.
- Native Sapling library loading can fail release builds or crash app startup when artifacts are missing/stale, and the build script skips rebuilds if only one Android ABI artifact exists.

## Evidence Map

### Mainnet/Testnet Selection

`PivxWalletBase` always passes `PivxNetwork.mainnet` into the shared Electrum wallet constructor:

- `cw_pivx/lib/src/pivx_wallet.dart:86-99`

The PIVX service methods accept `isTestnet`, but do not pass it through:

- `cw_pivx/lib/src/pivx_wallet_service.dart:34-45`
- `cw_pivx/lib/src/pivx_wallet_service.dart:163-179`

Existing wallet snapshots also load using `PivxNetwork.mainnet`:

- `cw_pivx/lib/src/pivx_wallet.dart:1111-1118`

Downstream Sapling code checks `network == PivxNetwork.testnet`, but that condition is unreachable through normal PIVX wallet creation/open/restore:

- `cw_pivx/lib/src/pivx_wallet.dart:223-226`
- `cw_pivx/lib/src/pivx_wallet.dart:481-486`

### Prefixes, HRPs, and Version Bytes

Transparent mainnet constants are present:

- `cw_pivx/lib/src/pivx_network.dart:35-41`
- `cw_pivx/lib/src/pivx_network.dart:136-155`

Testnet transparent constants are present but unreachable through normal wallet creation:

- `cw_pivx/lib/src/pivx_network.dart:44-51`

Sapling HRPs are mostly consistent between Dart and Rust:

- `cw_pivx/lib/src/sapling/sapling_constants.dart:39-69`
- `cw_pivx/rust/src/keys.rs:24-40`

However `PivxNetwork.isValidAddress()` is mainnet-only for shielded addresses because it accepts `ps...` and does not account for `ptestsapling...`:

- `cw_pivx/lib/src/pivx_network.dart:162-180`

### Activation Heights

Mainnet Sapling activation is consistent at `2,700,500`:

- `cw_pivx/lib/src/sapling/sapling_constants.dart:71-80`
- `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:31-36`
- `cw_pivx/rust/src/transaction.rs:119-133`

Original audit finding: testnet was inconsistent:

- Dart constants say `1,164,637`: `cw_pivx/lib/src/sapling/sapling_constants.dart:75-83`
- The Sapling Electrum wrapper says `201`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:31-36`
- Rust consensus params say `201`: `cw_pivx/rust/src/transaction.rs:138-150`
- Rust tests assert `201`: `cw_pivx/rust/src/transaction.rs:765-779`

Because the app is mainnet-hardcoded, this inconsistency is currently masked in normal UI flows.

Implementation update, 2026-05-28: Dart/Rust wallet constants now use testnet activation `201` based on the ElectrumX agent's PIVX Core v5.6.1 source report. This still needs independent release-owner Core evidence and manual testnet validation before the release gate closes.

### Node Defaults and Sapling RPC Compatibility

The bundled PIVX default node list points at Chainster Electrum servers:

- `assets/pivx_electrum_server_list.yml:1-17`

Migration fallback uses a different PIVX node URI:

- `lib/entities/default_settings_migration.dart:53`
- `lib/entities/default_settings_migration.dart:1203-1206`
- `lib/store/settings_store.dart:1181-1182`

There is no release config or node metadata proving those endpoints support PIVX Sapling RPCs.

The Sapling client methods in Dart call both planned/upstream-style names and one supported current name:

- `blockchain.nullifier.get_spend`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:378-383`
- `blockchain.commitment.get_info`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:389-394`
- `blockchain.sapling.get_outputs`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:404-417`
- `blockchain.sapling.get_block_range`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:427-458`
- `blockchain.anchor.get_height`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:467-469`
- `blockchain.sapling.get_nullifiers`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:533-539`
- `blockchain.sapling.get_tree_state`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:545-550`
- `blockchain.sapling.get_witness`: `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart:557-562`

The previously documented local `sapling_integration` ElectrumX fork supports different names:

- `blockchain.sapling.get_nullifier_status`
- `blockchain.sapling.get_commitment_info`
- `blockchain.sapling.get_outputs_by_height`
- `blockchain.sapling.get_block_range`
- `blockchain.sapling.get_anchor_height`
- `blockchain.sapling.get_best_anchor`

This means receive sync may reach `get_block_range`, but nullifier, commitment, anchor, tree-state, witness, and outputs-by-height flows are not contract-aligned.

### Server Failure Handling

Stage 2 already recorded `PIVX-REC-002`: `getBlockRange()` catches all exceptions and returns `[]`, and range completion advances storage height.

Stage 6 adds a broader config risk: automatic node health and switching only verify generic Electrum connectivity/transparent balance, not Sapling RPC support.

- PIVX health check calls transparent `getBalance`: `cw_pivx/lib/src/pivx_wallet.dart:882-898`
- Node liveness only opens an Electrum socket: `cw_core/lib/node.dart:307-318`
- Automatic switching uses nodes with `isEnabledForAutoSwitching` but no Sapling capability filter: `lib/core/node_switching_service.dart:98-175`

The app can therefore switch a PIVX wallet to a reachable Electrum server that cannot serve shielded sync/spend RPCs.

### Fee and Dust Policy

Transparent fee/dust policy:

- `PivxNetwork.dustThreshold = 5460`: `cw_pivx/lib/src/pivx_network.dart:136-143`
- `PivxWallet.networkDustAmount = 5460`: `cw_pivx/lib/src/pivx_wallet.dart:1094-1100`
- PIVX transparent fee uses `feeRate * estimatedSize / 1000`: `cw_pivx/lib/src/pivx_wallet.dart:1054-1065`

Sapling Dart constants:

- `PivxFeePolicy` now records min relay fee `10000`, dust relay fee `30000`, Sapling fee factor `100`, transparent dust `5460`, and shielded dust `1446000`: `cw_pivx/lib/src/sapling/sapling_constants.dart:124-184`

FFI fee/validation:

- `validate_shielded_amount()` dust threshold is `1446000`: `cw_pivx/rust/src/ffi.rs:170-204`
- `validate_fee()` min fee is `10000`: `cw_pivx/rust/src/ffi.rs:186-198`
- `cw_pivx_estimate_fee()` now estimates serialized-size Sapling fee using min relay fee `10000` and shielded fee factor `100`: `cw_pivx/rust/src/ffi.rs:684-730`

Rust transaction validation:

- `SHIELDED_DUST_THRESHOLD = 1,446,000`: `cw_pivx/rust/src/transaction.rs:24-29`

Implementation note, 2026-05-28:
PIVX Core v5.6.1 source evidence now confirms `DUST_RELAY_TX_FEE = 30000`, `minRelayTxFee = CFeeRate(10000)`, wallet `DEFAULT_TRANSACTION_MINFEE = 10000`, and shielded relay fee as serialized-size min relay fee multiplied by `100`. Cake's Dart/Rust Sapling fee estimator was aligned to the factor-100 Core policy.

### Proving Parameter Acquisition

The send path downloads proving params lazily at send time:

- `cw_pivx/lib/src/pivx_wallet.dart:765-793`

The active download implementation uses `https://duddino.com/...`, Cake's `ProxyWrapper`, expected size/SHA-256 checks, and temp-file promotion:

- `cw_pivx/lib/src/sapling/sapling_factories.dart:653-795`

Hash verification exists in Rust when initializing the prover:

- `cw_pivx/rust/src/prover.rs:21-81`

Local existence checks now verify size and SHA-256 before prover initialization:

- `cw_pivx/lib/src/sapling/sapling_factories.dart:616-647`
- `cw_pivx/rust/src/ffi.rs:723-744`

2026-05-31 live metadata evidence for the configured PIVX-hosted files:

- `https://duddino.com/sapling-spend.params`: `47,958,396` bytes, SHA-256 `8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13`
- `https://duddino.com/sapling-output.params`: `3,592,860` bytes, SHA-256 `2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4`

Dart constants, Rust prover constants, FFI availability checks, and alternate-builder messaging now use the same metadata:

- `cw_pivx/lib/src/sapling/sapling_constants.dart:97-118`
- `cw_pivx/rust/src/prover.rs:21-81`
- `cw_pivx/rust/src/ffi.rs:723-744`
- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart:150-186`

There is also an unused/alternate builder with Zcash URLs and different hashes that throws `UnimplementedError`:

- `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart:150-186`

### Native Library Loading and Build Flags

Dart dynamically opens platform-specific libraries:

- `cw_pivx/lib/src/sapling/sapling_ffi.dart:20-43`

Android plugin startup also unconditionally loads the library:

- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt:19-25`

The Android/macOS build helper skips all PIVX native rebuilds if only the arm64 Android `.so` exists:

- `scripts/build_android_macos.sh:98-112`

The same helper enables PIVX unconditionally during project configuration:

- `scripts/build_android_macos.sh:155-156`

iOS force-loads a copied static library into the plugin framework:

- `cw_pivx/ios/cw_pivx.podspec:23-42`

macOS and Linux link or bundle static `.a` libraries, while Dart attempts to open `.dylib`/`.so` names at runtime:

- `cw_pivx/macos/cw_pivx.podspec:27-29`
- `cw_pivx/linux/CMakeLists.txt:27-38`
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:36-40`

No environment/build flag was found that switches PIVX mainnet/testnet or disables PIVX Sapling for unsupported release artifacts.

### Tor and Proxy Behavior

Electrum sockets route through global Tor when `CakeTor.instance.started` is true:

- `cw_core/lib/utils/proxy_socket/abstract.dart:18-29`
- `cw_bitcoin/lib/electrum_wallet.dart:671-684`
- `cw_bitcoin/lib/electrum.dart:59-81`

Per-node `socksProxyAddress` exists but is not passed into Electrum connection setup:

- `cw_core/lib/node.dart:41-49`
- `cw_bitcoin/lib/electrum_wallet.dart:671-684`

SSL certificate verification is bypassed for secure Electrum sockets:

- `cw_core/lib/utils/proxy_socket/abstract.dart:33-37`

Proving parameter downloads now use `ProxyWrapper`, but this still requires device evidence for Tor/proxy routing and does not settle per-node proxy behavior:

- `cw_pivx/lib/src/sapling/sapling_factories.dart:744-795`

## Findings

Stage 6 findings are recorded in `11_findings_register.md`:

- `PIVX-NET-001`: PIVX mainnet is hard-coded while testnet/build selection parameters are ignored.
- `PIVX-NET-002`: Sapling ElectrumX RPC method names do not match the documented supported server contract.
- `PIVX-NET-003`: Node health and automatic switching do not verify Sapling RPC capability.
- `PIVX-NET-004`: Proving parameter acquisition is not release-safe or proxy/Tor-aware.
- `PIVX-NET-005`: Fee and dust policies are inconsistent across transparent, Sapling, Dart, and Rust layers.
- `PIVX-NET-006`: Native Sapling library loading and build scripts can ship missing or stale artifacts.
- `PIVX-NET-007`: PIVX networking bypasses per-node proxy settings and disables TLS certificate validation for Electrum sockets.

## Open Questions Added

Stage 6 open questions were added to `12_open_questions.md`.

## Release Gate

Blocks APK testing: Yes.

Blocks TestFlight: Yes.

Recommended minimum before external release:

- Decide explicit PIVX mainnet/testnet flavor policy and wire it end to end.
- Require default PIVX nodes to advertise/pass Sapling RPC capability checks before shielded features are enabled.
- Align Dart client RPC names with the production ElectrumX fork.
- Collapse activation heights, prefixes, fees, dust, and params metadata into one verified source of truth.
- Make proving parameter acquisition bundled or verified via an approved release download path with Tor/proxy support and atomic writes.
- Make native library artifact checks deterministic for every supported platform/ABI.

## Implementation Notes

2026-05-28:

- Wallet code now accepts the reported v1 Sapling capability method `blockchain.sapling.capabilities` before the older `blockchain.sapling.get_capabilities` fallback and preserves advertised capability/version/network/activation metadata.
- PIVX node records now persist Sapling capability/version fields and the node list displays cached readiness/version status after probing.
- Dart/Rust testnet Sapling activation constants now use `201` based on the ElectrumX agent's PIVX Core v5.6.1 source report. This audit finding remains open until independent release-owner Core evidence and manual testnet validation pass.
- The active proving-parameter downloader now uses `ProxyWrapper`, verifies cached and downloaded files by expected size and SHA-256, writes to `.download`, and renames only verified temp files into place. The finding remains open for release-owner approval of canonical PIVX-host/mirror policy, streaming/resume policy, and mobile Tor/interruption/low-storage evidence.
- Independent PIVX Core v5.6.1 fee-policy source evidence was recorded for min relay fee, dust relay fee, wallet min fee, and the Sapling fee factor. Cake's Dart/Rust Sapling fee estimation now applies Core's factor-100 shielded relay policy.

2026-05-31:

- Independent PIVX Core v5.6.1 shielded dust source evidence was recorded from `validation.h`, `policy.cpp`, `policy/feerate.cpp`, and `sapling/sapling_transaction.h`. Cake now applies Core transparent dust `5,460` and shielded dust `1,446,000` in Dart/Rust. The gate remains open for PIVX Core mempool acceptance and device tests.
- Live proving-parameter URL/hash/size evidence was recorded for the configured `duddino.com` files, and Dart/Rust/alternate-builder metadata was reconciled. The gate remains open for release-owner approval of the canonical host/mirror policy, streaming/resume or accepted-memory policy, and mobile Tor/interruption/low-storage evidence.
