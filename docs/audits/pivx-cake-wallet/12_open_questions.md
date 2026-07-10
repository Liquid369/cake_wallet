# PIVX Audit Open Questions

Status: Open questions and release-owner decisions accumulated here.

Last updated: 2026-05-31

## Current Decision And Verification Ledger

The release-owner answers below have been preserved in-line with the original questions. Current implementation tracking uses this interpretation:

- Mainnet is the first external-test default unless product direction changes; testnet code paths must remain wired and testnet should be usable when reliable nodes are available.
- PIVX native Sapling libraries should be rebuilt for release candidates unless a release owner explicitly accepts checked-in artifacts with provenance/hash evidence.
- PIVX Sapling sidecar state should be encrypted locally; the wallet-side pass now writes `.json.enc`, but backup inclusion/exclusion remains unresolved.
- The production Sapling ElectrumX contract is not yet frozen. Wallet code now probes a proposed capability method and supports legacy aliases, but server-side v1 work remains open in `14_electrumx_followups.md`.
- PIVX Sapling global output positions should be implemented server-side and returned explicitly; wallet code can consume them and blocks unsafe post-activation sync without a trusted persisted cursor or positions. Legacy inferred cursors from owned notes are intentionally not trusted.
- Unsupported PIVX routes must be blocked until implemented. Product intent is eventually all routes, but current wallet code still lacks `t-to-z` and `z-to-t` builders.
- PIVX dashboard status remains a combined sync indicator per product direction, but now includes shielded sync/error/height context. Persistent per-node Sapling capability/version badges remain open and depend on the ElectrumX v1 capability contract.
- PIVX Core 5.6.1 is the current canonical target for transaction serialization, fees, dust, and activation-height checks until release owner selects another commit.
- ElectrumX agent update `15_electrumx_update_from_other_agent.md` reports PIVX Core v5.6.1 tag `v5.6.1`, commit `af60f19`, `src/chainparams.cpp`, with mainnet Sapling activation `2700500` and testnet Sapling activation `201`. Wallet Dart/Rust constants have been aligned to `201`, but the release gate remains open until the release owner records independent Core evidence and device/testnet validation.
- Independent PIVX Core v5.6.1 source evidence now confirms fee-policy inputs: dust relay fee `30000`, min relay fee `10000`, wallet min fee `10000`, Sapling relay fee factor `100`, transparent dust `5,460`, and shielded dust `1,446,000`. Wallet Dart/Rust Sapling fee estimation, shielded amount checks, and dust-change handling now apply these constants, but mempool/device acceptance remains open.
- PIVX node records now persist Sapling capability/version metadata and node-list status displays it when probed. This still needs default-node and capable/non-capable manual evidence before the node/UI question is closed.
- PIVX proving parameters should come from PIVX-approved hosts and respect Tor/proxy policy. The active downloader now uses `ProxyWrapper`, size/SHA-256 checks, and temp-file promotion. Live metadata evidence for the configured `duddino.com` files was recorded on 2026-05-31 and Dart/Rust/alternate-builder metadata now agrees, but release-owner approval of the canonical host/mirror policy, streaming/resume policy, and device Tor/interruption tests remain open.
- PIVX shielded reorg handling now follows the ElectrumX agent's proposed 100-block block-hash comparison model on the wallet side when the active node advertises block-hash support. This still needs release-owner confirmation that `100` remains the final rollback depth and live v1 server/manual reorg evidence.

Still-blocking unresolved choices:

- Exact proving-parameter distribution policy, release-approved host/mirror policy, streaming/resume or accepted memory policy, and Tor/proxy enforcement.
- Exact backup policy for encrypted Sapling sidecar state: include encrypted sidecar, exclude and reconstruct, or include only selected metadata.
- Final shielded receive/spend confirmation depths: candidate values remain 1 or 6 confirmations.
- Final shielded reorg rollback depth: current wallet-side implementation uses the proposed 100-block window.
- Final release route matrix for the first external build if all routes are not implemented by then.
- Default node list and monitoring/rotation proof for Sapling-capable PIVX ElectrumX nodes.
- Independent release-owner confirmation of PIVX Core v5.6.1 activation-height evidence and testnet device validation, after the ElectrumX agent reported testnet activation `201`.
- Mempool acceptance behavior around transparent/Sapling dust, shielded change, and send-max.

## Stage 1 Open Questions

1. Which PIVX network should pre-distribution test APKs use: mainnet, testnet, or a build-flavor-specific setting? mainnet
2. Are the checked-in Android native `libcw_pivx_sapling.so` binaries considered release candidates, or should APKs always rebuild them from Rust source? always rebuild
3. Are proving parameter files expected to be bundled, downloaded at runtime, or manually provisioned for test builds? i need help deciding best practice here
4. Which ElectrumX server implementation/version supports the PIVX Sapling RPC methods listed in `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart`?
Supported ElectrumX implementation/version

The supporting server is this local sapling_integration ElectrumX fork, not upstream ElectrumX. PIVX uses PIVXSaplingElectrumX as its session class and DeserializerPIVXSapling for parsing: lib/coins.py (line 1619), server/session.py (line 592).

Important API mismatch: the branch implements:


blockchain.sapling.get_nullifier_status

blockchain.sapling.get_commitment_info

blockchain.sapling.get_outputs_by_height

blockchain.sapling.get_block_range

blockchain.sapling.get_anchor_height

blockchain.sapling.get_best_anchor


It does not implement the doc/planned names like blockchain.sapling.get_outputs, get_tree_state, get_witness, get_nullifiers, or blockchain.nullifier.get_spend

But should it?
5. What is the intended restore birthday/height UX for PIVX wallets? references date and time/block number wallet was committed so we scan only after that period in time for shorter syncing

## Stage 2 Open Questions

1. What source of truth should be used for PIVX Sapling global commitment tree position: ElectrumX tree state, PIVX Core RPC, local compact block scan, or a dedicated indexer value? Global commitment tree position source of truth

Current implementation does not store or return global Sapling commitment positions. It indexes only commitment → tx/output and nullifier → tx/spend: server/db.py (line 684).

The intended current flow is: wallet gets canonical Sapling tx data from ElectrumX/PIVX Core and maintains the commitment tree locally. That is stated in the server comments: client maintains tree/witnesses locally and raw tx hex is provided for parsing: server/session.py (line 604).

For production, I’d add explicit global output positions to the ElectrumX index. The design doc proposes that, but the code has not implemented it.
so we will implement it
2. Does the intended ElectrumX Sapling API return all Sapling outputs in every returned block, in canonical transaction/output order, including outputs not owned by the wallet?
Does get_block_range return all outputs in canonical order?

It fetches getblock(hash, 2) from PIVX Core, iterates daemon transaction order, filters Sapling txs, and returns raw tx hex: server/session.py (line 826).

So canonical order is inherited from PIVX Core block tx order and each raw transaction’s internal output order. It omits non-Sapling transactions and omits blocks with no Sapling transactions. That is probably fine for output scanning, but the API does not include explicit block hash/time or output positions.
3. How should the wallet distinguish a genuinely empty Sapling range from a failed/unsupported `blockchain.sapling.get_block_range` call?
Empty range vs unsupported/failed get_block_range

On this server, a genuinely empty Sapling range returns []: server/session.py (line 859). Invalid ranges and daemon failures raise RPC errors.

The client must not treat RPC errors as empty ranges. If we later change implementation, I’d prefer an envelope like {blocks: [], from, to, complete: true} so empty success is unambiguous.
4. What confirmation depth should make a received PIVX Sapling note visible, confirmed, and spendable? 1 or 6
5. What reorg depth must the mobile wallet support for Sapling note/nullifier rollback? 100
6. Should PIVX shielded note storage be encrypted with the existing wallet password file encryption, platform secure storage, or a new per-wallet local database key?
7. What transaction-history model should represent shielded receives: a PIVX-specific transaction info type, an extension of `ElectrumTransactionInfo`, or a separate shielded note history item? PIVX Specific
8. Should generated diversified shielded addresses remain selectable/current after restart, or should the UI always reset to the default address while retaining the generated address list? generated remain selectable

## Stage 3 Open Questions

1. What is the intended PIVX shielded send support matrix for first external APKs: z-to-z only, t-to-z, z-to-t, t-to-t, or explicit blocking for unsupported routes? All
2. Is there a known-good PIVX Core/regtest/testnet transaction vector for a Sapling z-to-z spend that can validate this repository's raw transaction serialization, txid, sighash, and spend signatures? We can collect from mainnet full transaction/block data as needed for each tx type/route
3. Which PIVX Core version/commit should be treated as canonical for Sapling transaction serialization and sighash behavior? 5.6.1 for now
4. Does the intended ElectrumX Sapling `blockchain.sapling.get_witness` response include the anchor/root, and should the wallet reject witnesses whose root differs from the selected anchor? Intended get_witness responses should be anchor-bound. Include anchor/root and anchor_height; the wallet must verify the witness path reconstructs exactly the selected anchor before building/signing. Current branch does not implement this RPC and instead leans toward client-side witness construction.
5. What shielded note confirmation depth should be required before selection for spending? 1 or 6
6. What local pending-state model should be used for outgoing shielded transactions: existing transaction history, a Sapling-specific pending table, or note-storage fields? what do you think is best
7. What PIVX shielded fee and dust policy should be used for send-max, dust change, and multi-note selection? PIVX Core Policy
8. Should shielded spend metadata ever be allowed in logs for debug builds, or should PIVX Sapling logging be fully redacted by default? I dont think so

## Stage 5 Open Questions

1. What exact transparent derivation paths/accounts must Cake support for PIVX restore: only `m/44'/119'/0'`, multiple BIP44 accounts, historical Cake paths, PIVX Core-derived keys, or common third-party wallet paths? Whatever aligns best with cakes current setup no extra work should be done
2. Should PIVX WIF/private-key recovery be implemented as sweep-only, import-as-standalone-key, watch-only, or intentionally unsupported with explicit migration guidance? People should be able to xfer with seedphrases? if not for sapling sure might need a sweep functionality
3. What should the PIVX restore birthday UX be: date picker, block-height field, automatic estimate from backup metadata, or always scan from activation/genesis for maximum safety? block-height field if they created in cake, if theyre importing we go from genesis
Update 2026-05-31: PIVX restore now exposes the block-height field. Empty height is treated as the safe import path, so transparent restore starts from genesis and shielded restore starts from Sapling activation. A user-entered height is persisted and used for transparent restore plus the first shielded scan when no sidecar sync state exists. Keep open for device/v1-node verification.
4. What exact Sapling ZIP-32 path and account policy should be treated as canonical for PIVX: `m/32'/119'/0'` only, multiple accounts, or a PIVX Core-compatible account discovery scheme? PIVX Core compatible
5. On seed-only shielded restore, should Cake reconstruct the prior diversified shielded address list/current address from discovered note diversifiers, or simply advance `nextDiversifierIndex` past observed diversifiers to avoid reuse? Avoid reuse
Update 2026-06-01: wallet-side restore now implements the "avoid reuse" policy for observed recovered notes by scanning the first 1,000 derived Sapling addresses after shield sync and advancing `nextDiversifierIndex` past matched recovered recipient bytes. It intentionally does not reconstruct labels/current-address selection. Keep open for manual seed-only restore evidence and for deciding whether the 1,000-index search limit is acceptable release policy.
6. Should PIVX support shielded viewing-key export/import or watch-only restore for audit/recovery use cases, and if so which key type/HRP should be exposed?
viewing key import/export sounds good
7. What is the required key-material memory handling bar for mobile release: zeroing Dart buffers only, zeroing FFI copies, Rust `zeroize` integration, mlock/no-swap hardening, or a documented best-effort policy?
you choose best practice based on pivx and privacy features
8. Should PIVX restore detect alternate derivations by querying address history like Bitcoin restore derivation detection, or require the user to choose a path/account manually?
Detect

## Stage 6 Open Questions

1. Should Cake expose PIVX testnet in product builds, restrict it to internal/dev builds, or keep PIVX mainnet-only while still requiring testnet-capable code paths for QA? Testnet is being relaunched and should be able to use testnet when available
2. Which PIVX ElectrumX Sapling RPC contract is production canonical: the current `sapling_integration` fork names, the planned/upstream-style names in `pivx_sapling_electrumx.dart`, or a new compatibility envelope/versioned API?
No existing RPC contract is production canonical yet. The production contract should be a versioned PIVX Sapling ElectrumX API with explicit capability discovery. Current sapling_integration names are implementation aliases; planned names are design/client intent; final production should reconcile both into v1 methods and response envelopes.
3. Which public/default PIVX nodes are guaranteed to run the Sapling-capable ElectrumX fork, and who owns monitoring/rotation when a default node loses Sapling RPC support? We will be maintaining them and they will stay up I handle rotation
4. Should PIVX shielded features be disabled unless the current node passes a Sapling capability probe, or should the app auto-switch to a Sapling-capable node?
All nodes should be sapling capable soon
5. What is the canonical PIVX testnet Sapling activation height for Cake: `201` as used by Rust/Electrum code, or `1,164,637` as previously present in Dart constants? its atleas tthe one inthe dart constraints, sapling didnt start until maybe even later use pivx core for v5.0 sapling upgrade height
Update 2026-05-28: ElectrumX agent reports canonical PIVX Core v5.6.1 evidence for testnet activation `201` from tag `v5.6.1`, commit `af60f19`, `src/chainparams.cpp`. Wallet Dart/Rust constants now use `201`; keep open for independent release-owner Core-source confirmation and manual testnet validation.
6. What PIVX Core fee/dust policy should Cake use for transparent outputs, shielded outputs, shielded change, send-max, and local pre-broadcast validation?
Whatever core is using currently
Update 2026-05-28: PIVX Core v5.6.1 source evidence confirms dust relay fee `30000`, min relay fee `10000`, wallet min fee `10000`, and Sapling fee factor `100`. Cake's Sapling fee estimator now applies the factor-100 policy.
Update 2026-05-31: PIVX Core v5.6.1 source evidence confirms transparent dust `5,460` and shielded dust `1,446,000` from `DEFAULT_SHIELDEDTXFEE_K = 100`, `SPENDDESCRIPTION_SIZE = 384`, `CTXOUT_REGULAR_SIZE = 34`, `BINDINGSIG_SIZE = 64`, and `CFeeRate::GetFee()` integer division. Cake now applies those thresholds in Dart/Rust. Keep open for mempool/device acceptance tests.
7. Should Sapling proving parameters be bundled in release builds, downloaded during first-run/setup, downloaded lazily during first shielded send, or managed as an explicit optional privacy feature download? You tell me whats best
8. Which proving-parameter host(s), hashes, and file sizes should be treated as release-canonical, and should Cake use Zcash-hosted params, PIVX-hosted mirrors, or both? PIVX
Update 2026-05-28: the wallet-side downloader now points at the existing PIVX-hosted constants, verifies expected size/SHA-256, and promotes verified temp files only. Keep open until the release owner records canonical PIVX-hosted URLs/hashes/sizes and reconciles the conflicting Dart/Rust/alternate-builder metadata.
Update 2026-05-31: live metadata was recorded for the configured PIVX-hosted URLs: `https://duddino.com/sapling-spend.params` is `47,958,396` bytes with SHA-256 `8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13`, and `https://duddino.com/sapling-output.params` is `3,592,860` bytes with SHA-256 `2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4`. Dart constants, Rust prover verification, FFI `has_proving_params`, and alternate-builder messaging now use this same metadata. Keep open for release-owner approval of the host/mirror policy and device download evidence.
9. Should proving-parameter downloads always respect built-in Tor/per-node proxy settings, and should downloads be blocked when Tor is enabled but the downloader cannot use it? Respect tor
Update 2026-05-28: the active downloader now uses Cake's `ProxyWrapper`, but manual Tor/proxy evidence and a fail-closed policy for any future non-proxyable download path are still required.
10. Should release CI rebuild PIVX native libraries from Rust source for every release candidate, or are checked-in Android/iOS/macOS/Linux artifacts acceptable if hashes/version checks pass? rebuild unless not necessary
Update 2026-05-31: Android build helpers now require all four APK ABI artifacts and fail if any PIVX Sapling `.so` is missing or empty, Android plugin load is fail-soft, and Dart exposes a native self-test for load/symbol/version/Core-fee alignment. Keep this open until CI policy is encoded, artifacts are rebuilt from Rust for release candidates, and per-platform/ABI hashes plus device self-test results are recorded.
11. Which platforms are in scope for PIVX Sapling at first external release: Android, iOS, macOS, Linux, Windows, or mobile only? android and ios
12. Should Electrum TLS certificate validation remain permissive for PIVX, or should PIVX require normal certificate verification/pinning for SSL nodes?
probably require normal but this would require work to electrumx

## Stage 7 Open Questions

1. What encrypted storage model should PIVX Sapling sidecar state use: existing wallet `.keys` password encryption, a per-wallet encrypted database key in secure storage, Hive/SQLCipher-style encrypted boxes, or a dedicated Sapling state keystore? not sure
2. Should Cake backups include encrypted PIVX Sapling sidecar state for faster restore, or exclude it and always reconstruct shielded state from seed plus restore height? im not sure
Update 2026-05-31: wallet-side backup filters now treat encrypted `pivx_sapling_*.json.enc` sidecars as eligible for Cake's encrypted app backup while excluding legacy plaintext `pivx_sapling_*.json`, `pivx_sapling_params`, and Sapling parameter `.download` temp files on export/restore. Keep open until release/product owners accept this policy and a clean-device backup/restore test verifies shielded state or safe rescan behavior.
3. What is the required mobile key-material policy for PIVX release: zero FFI copies only, Rust `zeroize` for all secret buffers, guarded/no-swap memory where available, crash-dump suppression, or a documented best-effort profile? not sure
4. Should PIVX-sensitive screens force screenshot/app-switcher protection even when the global privacy setting is off? If yes, which screens: seed, wallet keys, viewing keys, receive QR, transaction details, error popups, or all shielded screens? QR should not force protection but seed and keys
5. Should shielded PIVX addresses, payment URIs, memos, and viewing keys use normal clipboard, sensitive clipboard, auto-clear, or an explicit no-copy/warning policy? yes
6. Should PIVX restore/send errors be excluded from user-copyable crash/error dialogs unless sanitized, and should support logs have an automated redaction pass?
yes
7. Should PIVX proving parameters be included in Cake backups, excluded and re-downloaded, or cached outside backed-up document storage with hash revalidation?
yes
Update 2026-05-31: Cake backup filters now exclude the PIVX proving-parameter cache directory and Sapling parameter temp downloads. Proving parameters should be revalidated/redownloaded via the hardened downloader instead of restored from backups.
8. What exact release provenance is required for `cw_pivx_sapling` mobile binaries: rebuild every CI run, reproducible builds, notarized/hash manifest, symbol/version self-test, or all of these? Cake wallet standard?
9. Should iOS PIVX release require removing global `NSAllowsArbitraryLoads`, or are there non-PIVX app dependencies that still require ATS exceptions?
No idea you need to help here
10. Should PIVX Electrum SSL require normal platform certificate validation only, certificate pinning to Cake/PIVX-operated nodes, or a per-node trust-on-first-use model for community nodes?
Default/bundled PIVX Electrum servers should use normal CA/platform TLS validation where possible. User-added or community/self-signed Electrum nodes may use explicit trust-on-first-use with stored certificate fingerprint and warnings on fingerprint change. Certificate pinning should be optional for curated nodes, not the universal production requirement.

## Stage 8 Open Questions

1. Should PIVX testnet be exposed in normal create/restore advanced settings, hidden behind internal/dev builds, or enabled only when a PIVX testnet node list is available? normal
2. What exact PIVX restore UI should ship first: seed plus block-height field only, seed plus date/height, WIF sweep/import, viewing-key import, or all of these with staged availability? all
3. Should new PIVX wallets default the receive screen to shielded, transparent, or the last user-selected address type? shielded
4. Should PIVX receive QR/payment URIs support Sapling memos, and if yes what URI parameter names and length/encoding rules should Cake use? yes and use info from other private coins like zcash
5. Should shielded addresses/payment URIs use normal clipboard, sensitive clipboard, auto-clear, or a warning-before-copy flow? yes should be clipboard capable
6. What send route UI should be canonical for PIVX: automatic route detection from destination address, explicit source/destination segmented controls, or a route summary card before confirmation? it should detect route based on address used in send and recv whihc is data the user should provide
7. Which PIVX routes should be enabled in the first tester build: t-to-t only, z-to-z only, t-to-z self-shielding, z-to-t deshielding, t-to-z external, or all routes once implemented? all need to be
8. What labels should transaction history use for PIVX pool direction: `Transparent`, `Shielded`, `Shield`, `Deshield`, `Private`, `Public`, or PIVX-Core-compatible terminology? Transparent, Shielded, Deshield
9. Should the dashboard show transparent sync and shielded sync as separate statuses, or one combined status with expandable Sapling details? one combined
10. Should node settings show a PIVX Sapling capability badge/probe result for every node, and should shielded actions be disabled when that probe fails? yes
11. Should PIVX backup UI explicitly state whether Sapling sidecar state is included, excluded, or unnecessary because seed plus restore height is sufficient? no need just do whats necessary
12. Should PIVX Show Keys expose Sapling full viewing key, incoming viewing key, extended spending key, or none until import/export is fully designed? yes
13. Should the PIVX release tester guide live in-app, in the APK/TestFlight release notes, in `docs/audits/pivx-cake-wallet/10_test_plan.md`, or all three? docs
14. What exact user-facing wording should be used for unsupported PIVX routes so testers do not attempt real-value sends on blocked paths? none should be unsupported so its fine
