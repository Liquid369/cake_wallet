# Stage 1 - Repository Discovery And Integration Map

Status: Complete for shallow repository discovery. No production code was modified.

## Search Method

Commands used:

- `rg -l -i "pivx" --glob '!**/target/**' --glob '!**/build/**' --glob '!**/.dart_tool/**' --glob '!docs/audits/**' --glob '!scripts/reown_flutter/**' --glob '!scripts/bitbox_flutter/**'`
- `rg -l -i "sapling|shielded|zaddr|taddr|nullifier|diversifier|viewing key|spending key|birthday|restore height|sync height|branch id|consensus branch" cw_pivx lib cw_core cw_bitcoin --glob '!**/target/**' --glob '!**/build/**' --glob '!**/.dart_tool/**'`
- `rg --files cw_pivx/lib cw_pivx/rust/src cw_pivx/rust/tests cw_pivx/android cw_pivx/ios cw_pivx/macos cw_pivx/linux cw_pivx/scripts cw_pivx/test`
- Targeted `rg -n -i "pivx"` over `lib`, `cw_core`, `cw_bitcoin`, `tool`, `integration_test`, `test`, `pubspec_base.yaml`, `docs`, and `scripts`.

Counts:

- Direct PIVX references: 152 files/code paths.
- Dedicated `cw_pivx` package paths: 66 source/native/build/test paths in the searched areas.
- Sapling/shield keyword superset: 227 files/code paths in the narrowed package/app search set. This includes false positives from shared wallet code and generic terms, so the high-signal map below is the audit reference.

## Architecture Summary

The integration appears to add a dedicated `cw_pivx` package for PIVX wallet logic, Sapling Dart wrappers, Rust FFI, native library packaging, and tests. The app-level Cake Wallet code registers `WalletType.pivx`, exposes a generated `Pivx` facade under `lib/pivx`, uses shared Bitcoin/Electrum infrastructure for transparent PIVX behavior, and adds PIVX-specific UI/view-model paths for balances, receive addresses, send coin type selection, nodes, fees, and wallet creation/restore.

The main risk concentration is the bridge between:

- `cw_pivx/lib/src/pivx_wallet.dart`
- `cw_pivx/lib/src/sapling/*`
- `cw_pivx/rust/src/*`
- `cw_bitcoin` shared Electrum/UTXO code
- App send/receive/balance view models under `lib/view_model/*`

## Dedicated `cw_pivx` Package

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_pivx/lib/cw_pivx.dart` | Public package export surface. | PIVX-specific | wallet-core | Medium |
| `cw_pivx/lib/src/pivx_wallet.dart` | Main PIVX wallet implementation; extends `ElectrumWallet`, initializes Sapling, tracks shielded balance/address/sync. Key refs: lines 40-69, 117-120, 127-177, 190-199, 206-258. | PIVX-specific plus shared Electrum base | wallet-core, sync, transaction, balance | Critical |
| `cw_pivx/lib/src/pivx_wallet_service.dart` | Create/open/remove/restore service for PIVX wallets. Key refs: lines 15-28, 34-49, 53-80, 163-183. | PIVX-specific | wallet-core, restore, storage | High |
| `cw_pivx/lib/src/pivx_wallet_creation_credentials.dart` | New/restore/WIF credential classes. Key refs: lines 4-20, 22-38, 40-54. | PIVX-specific | restore, key | Medium |
| `cw_pivx/lib/src/pivx_wallet_addresses.dart` | Transparent address derivation wrapper and shielded address selection override. Key refs: lines 10-23, 38-44, 46-74. | PIVX-specific plus shared Electrum address model | wallet-core, key, UI receive | High |
| `cw_pivx/lib/src/pivx_network.dart` | PIVX transparent prefixes, constants, Sapling HRPs, script hash handling. Key refs: lines 34-52, 54-61, 90-110, 115-156, 157-180, 202-218. | PIVX-specific | network, key, validation | High |
| `cw_pivx/lib/src/pivx_transaction_priority.dart` | PIVX fee priority model. | PIVX-specific | transaction, fee | Medium |
| `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart` | Pending transaction wrapper for shielded sends. | PIVX-specific | transaction, wallet state | High |

## Sapling Dart Layer

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_pivx/lib/src/sapling/sapling.dart` | Sapling abstraction/types. | PIVX-specific Sapling | wallet-core | High |
| `cw_pivx/lib/src/sapling/sapling_constants.dart` | Sapling constants. | PIVX-specific Sapling | network, transaction | High |
| `cw_pivx/lib/src/sapling/sapling_key_manager.dart` | Key manager abstraction. | PIVX-specific Sapling | key | Critical |
| `cw_pivx/lib/src/sapling/native_sapling_key_manager.dart` | Native FFI-backed key manager. | PIVX-specific Sapling | key, FFI | Critical |
| `cw_pivx/lib/src/sapling/sapling_ffi.dart` | Dart FFI bindings and native library loading. Key refs: lines 20-44, 51-68, 89-106, 108-161, 176-214. | PIVX-specific Sapling | FFI, native, transaction, sync | Critical |
| `cw_pivx/lib/src/sapling/pivx_sapling_electrumx.dart` | Sapling ElectrumX API client, activation heights, output/spend/tree/witness models. Key refs: lines 1-20, 32-36, 95-143, 186-220. | PIVX-specific Sapling | sync, network, receive | Critical |
| `cw_pivx/lib/src/sapling/sapling_factories.dart` | Factories/wrappers for key manager, sync engine, transaction builder; storage restore path. Key refs: lines 20-33, 36-93, 102-130, 133-166, 169-213, 223-260. | PIVX-specific Sapling | key, sync, storage, transaction | Critical |
| `cw_pivx/lib/src/sapling/shield_sync_engine.dart` | Sync engine abstraction. | PIVX-specific Sapling | sync, receive | Critical |
| `cw_pivx/lib/src/sapling/native_shield_sync_engine.dart` | Native sync engine wrapper. | PIVX-specific Sapling | sync, FFI | Critical |
| `cw_pivx/lib/src/sapling/sapling_note.dart` | Note/spendable note model. | PIVX-specific Sapling | note, transaction | Critical |
| `cw_pivx/lib/src/sapling/sapling_note_storage.dart` | JSON persistence for notes and shielded addresses. Key refs: lines 1-4, 12-64, 86-160, 166-214, 216-220. | PIVX-specific Sapling | storage, note, key metadata | Critical |
| `cw_pivx/lib/src/sapling/sapling_transaction_builder.dart` | Transaction builder abstractions and transparent UTXO type. | PIVX-specific Sapling | transaction | Critical |
| `cw_pivx/lib/src/sapling/native_sapling_transaction_builder.dart` | Native transaction builder; shield/deshield placeholders; proving params handling. Key refs: lines 27-55, 57-92, 94-127, 129-142, 150-187, 189-192. | PIVX-specific Sapling | transaction, send, fee, native | Critical |
| `cw_pivx/lib/src/sapling/utils/atomic_tree_position.dart` | Thread-safe tree position tracking. | PIVX-specific Sapling | sync, note | High |
| `cw_pivx/lib/src/sapling/utils/ordered_batch_processor.dart` | Ordered batch processing for sync. | PIVX-specific Sapling | sync | High |

## Rust Sapling FFI Layer

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_pivx/rust/src/lib.rs` | Rust crate entry point. | PIVX-specific Sapling | native | High |
| `cw_pivx/rust/src/ffi.rs` | C-compatible FFI functions, global key/sync handles, validation, error handling. Key refs: lines 1-7, 50-54, 56-84, 94-135, 137-151, 167-199. | PIVX-specific Sapling | FFI, key, sync, transaction | Critical |
| `cw_pivx/rust/src/keys.rs` | Sapling key derivation and address generation. | PIVX-specific Sapling | key | Critical |
| `cw_pivx/rust/src/sync.rs` | Native sync state and note tracking. | PIVX-specific Sapling | sync, note | Critical |
| `cw_pivx/rust/src/notes.rs` | Spendable note structures/helpers. | PIVX-specific Sapling | note | Critical |
| `cw_pivx/rust/src/transaction.rs` | Sapling transaction construction and PIVX serialization/signing. | PIVX-specific Sapling | transaction, consensus | Critical |
| `cw_pivx/rust/src/prover.rs` | Proving parameter/prover integration. | PIVX-specific Sapling | transaction, native | High |
| `cw_pivx/rust/src/types.rs` | Native domain types. | PIVX-specific Sapling | native | Medium |
| `cw_pivx/rust/src/error.rs` | Error types. | PIVX-specific Sapling | native, FFI | Medium |
| `cw_pivx/rust/src/utils.rs` | Utility helpers. | PIVX-specific Sapling | native | Medium |
| `cw_pivx/rust/Cargo.toml` | Rust dependencies/build config. | PIVX-specific Sapling | build, native | High |
| `cw_pivx/rust/cbindgen.toml` | Header generation config. | PIVX-specific Sapling | build, FFI | Medium |
| `cw_pivx/rust/tests/testnet_integration.rs` | Rust testnet integration tests. | PIVX-specific Sapling | tests | High |

## Native Platform Packaging

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_pivx/android/build.gradle` | Android plugin/native packaging config. | PIVX-specific | build, mobile | High |
| `cw_pivx/android/settings.gradle` | Android project settings. | PIVX-specific | build | Low |
| `cw_pivx/android/src/main/AndroidManifest.xml` | Android plugin manifest. | PIVX-specific | mobile, build | Medium |
| `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt` | Android Flutter plugin registration. | PIVX-specific | mobile, native | Medium |
| `cw_pivx/android/src/main/jniLibs/arm64-v8a/libcw_pivx_sapling.so` | Android native Sapling library. | PIVX-specific | native, release | Critical |
| `cw_pivx/android/src/main/jniLibs/armeabi-v7a/libcw_pivx_sapling.so` | Android native Sapling library. | PIVX-specific | native, release | Critical |
| `cw_pivx/android/src/main/jniLibs/x86/libcw_pivx_sapling.so` | Android native Sapling library. | PIVX-specific | native, release | High |
| `cw_pivx/android/src/main/jniLibs/x86_64/libcw_pivx_sapling.so` | Android native Sapling library. | PIVX-specific | native, release | High |
| `cw_pivx/ios/cw_pivx.podspec` | iOS podspec. | PIVX-specific | build, native, release | Critical |
| `cw_pivx/ios/Classes/CwPivxPlugin.swift` | iOS Flutter plugin registration. | PIVX-specific | mobile, native | Medium |
| `cw_pivx/ios/Classes/cw_pivx_sapling.h` | iOS native header. | PIVX-specific | FFI, native | High |
| `cw_pivx/ios/Frameworks/cw_pivx_sapling.h` | iOS framework header. | PIVX-specific | FFI, native | High |
| `cw_pivx/ios/Frameworks/README.md` | Native framework instructions. | PIVX-specific | docs, build | Low |
| `cw_pivx/macos/cw_pivx.podspec` | macOS podspec. | PIVX-specific | build | Medium |
| `cw_pivx/macos/Classes/CwPivxPlugin.swift` | macOS plugin registration. | PIVX-specific | native | Low |
| `cw_pivx/macos/Frameworks/cw_pivx_sapling.h` | macOS native header. | PIVX-specific | native | Medium |
| `cw_pivx/macos/Frameworks/libcw_pivx_sapling.a` | macOS native library. | PIVX-specific | native | Medium |
| `cw_pivx/macos/Frameworks/libcw_pivx_sapling.dylib` | macOS native library. | PIVX-specific | native | Medium |
| `cw_pivx/linux/CMakeLists.txt` | Linux plugin build config. | PIVX-specific | build | Low |
| `cw_pivx/linux/cw_pivx_plugin.cc` | Linux plugin registration. | PIVX-specific | native | Low |
| `cw_pivx/linux/include/cw_pivx/cw_pivx_plugin.h` | Linux plugin header. | PIVX-specific | native | Low |

## App-Level PIVX Facade And Registration

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `lib/pivx/pivx.dart` | Generated facade declaring `Pivx? pivx = CWPivx()`. | PIVX-specific generated app facade | wallet-core | High |
| `lib/pivx/cw_pivx.dart` | App facade implementation for wallet service, priorities, shielded address/balance helpers. Key refs: lines 3-8, 10-38, 40-54, 57-95. | PIVX-specific | wallet-core, UI bridge | High |
| `lib/di.dart` | Dependency injection creates `PivxWalletService`; key refs from search: lines 291, 1234-1235. | Shared app with PIVX branch | wallet-core | High |
| `tool/configure.dart` | Generates PIVX facade and pubspec dependency when `--pivx` is passed; key refs from search: lines 15, 38, 1528-1571, 1921-1923, 2002-2003, 2074-2075. | Shared build tool with PIVX branch | build, registration | Medium |
| `pubspec_base.yaml` | Includes PIVX server asset; key ref from search: line 240. | Shared app config | build, network | Medium |
| `cw_pivx/pubspec.yaml` | PIVX package dependencies. | PIVX-specific | build | High |

## Shared Core Model And Wallet Infrastructure

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_core/lib/wallet_type.dart` | Adds `WalletType.pivx` and serialization/display mappings. Key refs: lines 7-25, 27-85, 87-128, 130-170, 173-214, 216-257, 259-301. | Shared core with PIVX branch | wallet-core, storage | Critical |
| `cw_core/lib/crypto_currency.dart` | Adds `CryptoCurrency.pivx`; key ref from search: line 200. | Shared core with PIVX branch | wallet-core | High |
| `cw_core/lib/currency_for_wallet_type.dart` | Maps `WalletType.pivx` to `CryptoCurrency.pivx`. | Shared core with PIVX branch | wallet-core | Medium |
| `cw_core/lib/amount_converter.dart` | PIVX amount conversion. | Shared core with PIVX branch | balance, transaction | Medium |
| `cw_core/lib/node.dart` | PIVX node model handling. | Shared core with PIVX branch | network | High |
| `cw_core/lib/unspent_coin_type.dart` | Adds Sapling/transparent/any coin types; key refs from search: lines 5-13. | Shared core with PIVX branch | balance, transaction | High |
| `cw_core/lib/wallet_info.dart` and `cw_core/lib/wallet_info_legacy.dart` | PIVX appears in Sapling/shield keyword superset and may affect wallet metadata. | Shared | storage, restore | Medium |

## Shared Bitcoin/Electrum Reuse

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_bitcoin/lib/electrum_wallet.dart` | Transparent PIVX wallet behavior via shared Electrum path; key refs from search: lines 145-162, 723-726, 2228-2229. | Shared Bitcoin-like wallet with PIVX branches | wallet-core, sync, transaction | Critical |
| `cw_bitcoin/lib/electrum_wallet_addresses.dart` | PIVX transparent address types and address generation selection; key refs from search: lines 39, 292, 533. | Shared Bitcoin-like address model with PIVX branches | key, receive | High |
| `cw_bitcoin/lib/pending_bitcoin_transaction.dart` | PIVX label/handling in shared pending tx wrapper. | Shared with PIVX branch | transaction | Medium |
| `cw_bitcoin/lib/bitcoin_receive_page_option.dart` | Receive page address type options touched by Sapling keyword search. | Shared | UI receive | Medium |
| `lib/bitcoin/cw_bitcoin.dart` | Shared UTXO helper behavior has PIVX shielded/transparent filtering comments/branches; key refs from search: lines 217-221, 279-283. | Shared app Bitcoin facade with PIVX branches | transaction, balance | High |

## App UI, View Models, And User Flows

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `lib/view_model/send/send_view_model.dart` | PIVX shielded/transparent send mode selection and sending balance selection. Key refs: lines 171-180, 302-325, plus search refs 918. | Shared send VM with PIVX branches | UI, transaction, balance | Critical |
| `lib/view_model/send/fees_view_model.dart` | PIVX fee priority logic. Key refs from search: lines 102-103, 136, 208-209. | Shared send VM with PIVX branches | fee, transaction | High |
| `lib/view_model/send/output.dart` | PIVX output/address handling. Key refs from search: lines 116, 195, 401. | Shared send output model | transaction, validation | High |
| `lib/src/screens/send/widgets/send_card.dart` | PIVX shielded/transparent toggle. Key refs from search: lines 762-787. | Shared UI with PIVX branch | UI, transaction | High |
| `lib/view_model/dashboard/balance_view_model.dart` | Labels and display for PIVX shielded balances. Key refs: lines 182-204, 216-290, 302-353. | Shared dashboard VM with PIVX branches | balance, UI | High |
| `lib/view_model/wallet_address_list/wallet_address_list_view_model.dart` | Receive list inserts shielded Sapling section and addresses. Key refs: lines 199-250. | Shared receive VM with PIVX branches | UI, receive | High |
| `lib/view_model/wallet_address_list/wallet_address_edit_or_create_view_model.dart` | Creates/labels PIVX shielded addresses through facade. Key refs from search: lines 49-60, 81-83, 129-134. | Shared receive VM with PIVX branches | UI, key, receive | High |
| `lib/view_model/wallet_address_list/address_edit_or_create_arguments.dart` | Shielded address creation flag. | Shared UI args with PIVX/Sapling note | UI | Medium |
| `lib/view_model/wallet_address_list/wallet_address_list_header.dart` | Shielded address section header flag. | Shared UI with PIVX/Sapling note | UI | Low |
| `lib/src/screens/receive/widgets/address_list.dart` | Receive list observes balance changes for PIVX shielded balance. | Shared UI with PIVX branch | UI, receive | Medium |
| `lib/view_model/wallet_new_vm.dart` | New PIVX wallet credentials. Key refs from search: lines 123-124. | Shared wallet creation VM with PIVX branch | create, key | High |
| `lib/view_model/wallet_restore_view_model.dart` | PIVX seed restore credentials. Key refs from search: lines 67, 168-169. | Shared restore VM with PIVX branch | restore, key | High |
| `lib/view_model/restore/wallet_restore_from_qr_code.dart` | Maps PIVX QR restore type aliases. Key refs from search: lines 57-59. | Shared restore VM with PIVX branch | restore | Medium |
| `lib/core/seed_validator.dart` | PIVX seed validation branch. | Shared core with PIVX branch | restore, key | High |
| `lib/core/address_validator.dart` | PIVX transparent and Sapling address validation. Key refs from search: lines 156-157, 298. | Shared core with PIVX branch | validation, send, receive | High |
| `lib/core/payment_uris.dart` | PIVX URI parsing/generation. Key refs from search: lines 256-262. | Shared core with PIVX branch | UI, send, receive | Medium |
| `lib/core/wallet_creation_service.dart` | Creates PIVX wallet type. Key ref from search: line 86. | Shared core with PIVX branch | create | Medium |
| `lib/utils/qr_util.dart` | PIVX QR icon selection. | Shared UI utility | UI | Low |
| `lib/view_model/transaction_details_view_model.dart` | PIVX transaction details/explorer. Key refs from search: lines 101-102, 211-212, 927. | Shared UI with PIVX branch | history, explorer | Medium |
| `lib/view_model/dashboard/transaction_list_item.dart` | PIVX transaction list handling. | Shared UI with PIVX branch | history | Medium |
| `lib/view_model/unspent_coins/unspent_coins_list_view_model.dart` | PIVX transparent UTXO list/balance paths. | Shared UTXO VM with PIVX branch | balance, transaction | Medium |
| `lib/view_model/unspent_coins/unspent_coins_details_view_model.dart` | PIVX UTXO explorer/details paths. | Shared UTXO VM with PIVX branch | UI, explorer | Low |

## Network, Nodes, Exchange, Buy, And Settings

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `lib/entities/default_settings_migration.dart` | Default PIVX node and migration to save node ID. Key refs from search: lines 53, 672-673, 1094-1127, 1203-1206. | Shared settings with PIVX branch | network, release | High |
| `lib/entities/node_list.dart` | Loads PIVX Electrum server list asset. Key refs from search: lines 52-53, 112, 129. | Shared settings with PIVX branch | network | High |
| `lib/entities/preferences_key.dart` | Stores current PIVX node preference key. Key ref from search: line 17. | Shared settings with PIVX branch | storage, network | Medium |
| `lib/store/settings_store.dart` | Loads/saves current PIVX node. Key refs from search: lines 1146-1182, 1282-1283, 1675-1760, 1914-1915. | Shared settings with PIVX branch | network, storage | High |
| `lib/view_model/node_list/node_create_or_edit_view_model.dart` | PIVX node edit behavior. | Shared node VM with PIVX branch | network, UI | Medium |
| `lib/entities/priority_for_wallet_type.dart` | PIVX transaction priorities via facade. Key refs from search: lines 32-33. | Shared with PIVX branch | fee | Medium |
| `lib/exchange/provider/sideshift_exchange_provider.dart` | PIVX exchange support. | Shared exchange with PIVX branch | exchange, privacy | Medium |
| `lib/view_model/exchange/exchange_view_model.dart` | PIVX exchange model handling. | Shared exchange VM with PIVX branch | exchange, UI | Medium |
| `lib/view_model/exchange/exchange_trade_view_model.dart` | PIVX URI for exchange trade send. | Shared exchange VM with PIVX branch | exchange, send | Medium |
| `lib/buy/robinhood/robinhood_buy_provider.dart` | PIVX buy-provider branch. | Shared buy flow with PIVX branch | buy, UI | Low |
| `lib/view_model/settings/privacy_settings_view_model.dart` | PIVX privacy settings branch. | Shared settings VM with PIVX branch | privacy, UI | Medium |
| `lib/view_model/settings/other_settings_view_model.dart` | PIVX settings branch. | Shared settings VM with PIVX branch | UI | Low |
| `lib/view_model/advanced_privacy_settings_view_model.dart` | PIVX privacy setting behavior. | Shared settings VM with PIVX branch | privacy | Medium |

## Build Scripts And Release Paths

| File path | Purpose | Specific/shared | Category | Later-audit risk |
| --- | --- | --- | --- | --- |
| `cw_pivx/scripts/build_android.sh` | Builds PIVX Android native libraries. | PIVX-specific | build, native, release | Critical |
| `cw_pivx/scripts/build_ios.sh` | Builds PIVX iOS native library. | PIVX-specific | build, native, release | Critical |
| `cw_pivx/scripts/build_macos.sh` | Builds PIVX macOS native library. | PIVX-specific | build, native | Medium |
| `cw_pivx/scripts/build_linux.sh` | Builds PIVX Linux native library. | PIVX-specific | build, native | Low |
| `cw_pivx/scripts/build_all.sh` | Builds all PIVX native targets. | PIVX-specific | build, native | High |
| `scripts/build_pivx_android_apk.sh` | App-level Android APK build for PIVX testing. Key refs from search: lines 3-33. | PIVX-specific release script | build, release | High |
| `scripts/build_pivx_ios.sh` | App-level iOS build for PIVX testing. Key refs from search: lines 3-47. | PIVX-specific release script | build, release | High |
| `scripts/build_android_macos.sh` | Shared build script includes PIVX native library build and `--pivx` configure flag. Key refs from search: lines 102-112, 156. | Shared build script with PIVX branch | build, release | High |
| `scripts/PIVX_BUILD_GUIDE.md` | PIVX build guide for APK/iOS testing. | PIVX-specific docs | build, release | Medium |
| `docs/builds/ANDROID_MACOS_DEV.md` | Shared Android/macOS dev docs include PIVX library steps. | Shared docs with PIVX branch | build | Low |
| `ios/Podfile.lock` and `macos/Podfile.lock` | Lockfiles include PIVX pod references. | Shared build output/config | build, release | Medium |

## Existing PIVX Audit/Planning Documents Discovered

These may be useful background, but Stage 1 did not trust or verify their conclusions:

- `PIVX_SAPLING_IMPLEMENTATION.md`
- `PIVX_SAPLING_SECURITY_AUDIT.md`
- `PIVX_SAPLING_CONCURRENCY_ANALYSIS.md`
- `PIVX_SAPLING_CONCURRENCY_FIX.md`
- `PIVX_SAPLING_TEST_RESULTS.md`
- `READY_TO_COMMIT.md`
- `COMMIT_PLAN.md`
- `GIT_COMMIT_PLAN.md`
- `audit/RUST_CODE_REVIEW_PIVX_SAPLING_20251227.md`
- `cw_pivx/README.md`
- `cw_pivx/SAPLING.md`
- `cw_pivx/PIVX_CORE_VERIFICATION.md`
- `cw_pivx/CRITICAL_ACTIONS_REQUIRED.md`
- `cw_pivx/CRITICAL_FIXES_REQUIRED.md`
- `cw_pivx/CRITICAL_FIXES_COMPLETED_OLD.md`
- `cw_pivx/CRITICAL_FIXES_SESSION_SUMMARY.md`
- `cw_pivx/COMPREHENSIVE_AUDIT_2025.md`
- `cw_pivx/CONSENSUS_AUDIT_TX02.md`
- `cw_pivx/ERROR_HANDLING_IMPROVEMENTS.md`
- `cw_pivx/FFI_INPUT_VALIDATION.md`
- `cw_pivx/PRODUCTION_AUDIT_REPORT.md`
- `cw_pivx/TESTNET_VALIDATION_CHECKLIST.md`
- `cw_pivx/TEST_SUMMARY.md`

## Initial Risk Hotspots For Later Stages

These are not findings yet; they are areas selected for later audit:

- Sapling receive path: address generation, storage persistence, note detection, scan start height, nullifier handling, restart restore, pending/confirmed state.
- Sapling send path: note selection, witness/anchor selection, proving params, shielded-to-shielded support, shielded-to-transparent support, transparent-to-shielded support, broadcast/pending state.
- Network/release safety: hardcoded mainnet in wallet constructor, testnet selection plumbing, default node handling, Sapling activation heights, native library provenance.
- Balance correctness: mapping PIVX transparent and shielded pools into `BalanceRecord` second balance fields and send screen balances.
- Restore: seed validation, transparent derivation, Sapling derivation, birthday/restore height, scan coverage.
- Mobile security: native library packaging, JSON note storage location/encryption, logs containing note metadata or addresses, proving params download/update behavior.

