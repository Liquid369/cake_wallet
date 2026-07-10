# Stage 7 - Mobile Security Audit

Status: Complete.

Scope:
- Android/iOS local storage, secure storage, wallet files, backup/restore exposure, logs/crash reports, FFI/native memory handling, native library loading and packaging, TLS/proxy/Tor privacy behavior, clipboard/QR/payment URI flows, screenshot/app switcher controls, and release configuration relevant to PIVX.
- Production code was not modified.

## Verdict

PIVX is not ready for external APK distribution or TestFlight from a mobile security perspective.

Cake's shared mobile security baseline has useful controls: wallet key files use the shared encrypted `.keys` mechanism, wallet passwords and app secrets use `flutter_secure_storage`, Android application backup is disabled, and screenshot blocking exists as a user setting. PIVX Sapling, however, adds a separate plaintext sidecar storage file, verbose shielded metadata logs, native FFI key paths, proving-parameter downloads, native binary artifacts, and shielded QR/payment flows that do not yet meet a privacy-wallet release bar.

## Evidence Reviewed

### Secure Storage And Encrypted Wallet Files

- Shared wallet key files are encrypted through `WalletKeysFile.saveKeysFile()` and `WalletKeysFile.createKeysFile()` using `EncryptionFileUtils.write()`.
- `XChaCha20EncryptionFileUtils` encrypts file contents before writing to disk.
- Wallet passwords and app secrets use `FlutterSecureStorage` with Android encrypted shared preferences and iOS `KeychainAccessibility.first_unlock`.

Code references:
- `cw_core/lib/wallet_keys_file.dart:21-31`
- `cw_core/lib/wallet_keys_file.dart:34-49`
- `cw_core/lib/encryption_file_utils.dart:28-41`
- `lib/core/secure_storage.dart:23-26`

Assessment:
This protects the existing wallet-key file path, but PIVX Sapling note/address state does not use this mechanism.

### PIVX Sapling Local Storage

- `StoredSaplingNote` persists values, heights, txids, output indexes, tree positions, cmu, nullifier, memo, rseed, diversifier, pk_d, address, and tx index.
- `StoredShieldedAddress` persists diversified shielded addresses, labels, and creation time.
- `SaplingNoteStorage` writes JSON directly under `getApplicationDocumentsDirectory()` as `pivx_sapling_${walletId}_$network.json`.
- Loading and saving use raw `readAsString()` and `writeAsString(jsonEncode(data))`.

Code references:
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:50-64`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:111-131`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:166-213`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:271-287`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:313-320`

Assessment:
This is the highest Stage 7 mobile risk. It bypasses the shared encrypted wallet file path and stores shielded note metadata and note-restoration material in a normal app document file.

### Backup And Restore Exposure

- Android manifest disables OS backup with `android:allowBackup="false"` and `android:fullBackupContent="false"`.
- Cake's own backup export enumerates all first-level app-directory entities, adds directories/files to the archive, then encrypts the archive as `data.bin`.
- Because PIVX Sapling state lives in the app documents directory and is not in the backup ignore list, it is likely included in Cake backup archives.
- Backup encryption is good, but the sidecar state is not protected at rest before backup and is not explicitly modeled as sensitive PIVX Sapling state.

Code references:
- `android/app/src/main/AndroidManifest.xml:32-41`
- `lib/core/backup_service_v3.dart:348-361`
- `lib/core/backup_service_v3.dart:380-397`
- `lib/core/backup_service_v3.dart:399-423`
- `cw_pivx/lib/src/sapling/sapling_note_storage.dart:260-264`

Assessment:
OS backup exposure is mitigated on Android, but app-level backup includes the same plaintext Sapling sidecar unless explicitly excluded or encrypted before archive creation.

### Logs, Crash Reports, And Error Copying

- `printV()` always prints, and optionally appends to a file.
- PIVX Sapling sync logs note counts, values, heights, positions, balance, restore metadata, partial cmu/witness data, and errors.
- PIVX invalid mnemonic handling includes the full seed phrase in the thrown exception; shared wallet creation logs the exception and stack.
- The shared exception popup allows copying the full error text to system clipboard.

Code references:
- `cw_core/lib/utils/print_verbose.dart:8-25`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:178-212`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:374-377`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:444-464`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:762-796`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:875-896`
- `cw_pivx/lib/src/pivx_wallet_service.dart:167-169`
- `lib/view_model/wallet_creation_vm.dart:137-145`
- `lib/utils/exception_handler.dart:396-423`

Assessment:
Mobile logs and copied error text can leak seed phrases or shielded receive/spend metadata. This is not acceptable for a privacy coin release.

### FFI Memory And Native Key Handling

- PIVX derives a BIP39 seed, passes it to the Sapling key manager, and zeroes the Dart `Uint8List` after initialization.
- `SaplingKeys.fromSeed()` copies that seed into a native `malloc` buffer and frees it without first overwriting it.
- Rust receives the seed as a borrowed slice and stores key manager handles in global vectors.
- Rust `Drop` attempts to zero key manager fields using `ptr::write_bytes`, but comments note optimization, swap, core-dump, and upstream `Zeroize` limitations.
- FFI result buffers and strings carrying transaction JSON, viewing keys, addresses, and error text are freed, but not scrubbed before free.

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

Assessment:
There is a good intent to zero key material, but current Dart FFI copies and Rust/Dart buffers do not provide a consistent zeroization boundary.

### TLS, Proxy, Tor, And Network Privacy

- Electrum connections use the shared proxy socket path, but SSL sockets accept any bad certificate.
- The PIVX proving parameter downloader now uses Cake's `ProxyWrapper` and verifies size/SHA-256 before promoting temp files, but release-canonical PIVX hosts, conflicting parameter metadata, interruption/low-storage behavior, and device Tor/proxy proof are still unresolved.
- Per-node proxy support exists on `Node`, but Stage 6 found PIVX Electrum connections effectively rely on global CakeTor/proxy behavior rather than node-specific proxy selection.

Code references:
- `cw_core/lib/utils/proxy_socket/abstract.dart:18-39`
- `cw_bitcoin/lib/electrum.dart:67-85`
- `cw_bitcoin/lib/electrum_wallet.dart:671-685`
- `cw_core/lib/node.dart:282-305`
- `cw_pivx/lib/src/pivx_wallet.dart:775-793`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:630-684`
- `cw_pivx/lib/src/sapling/sapling_factories.dart:687-714`

Assessment:
PIVX mobile users can still be deanonymized or MITM'd during Electrum network activity, especially when they expect Tor or TLS validation to protect them. Proving-parameter downloads have wallet-side proxy/hash/temp-file hardening, but they still need release-source evidence and mobile Tor/interruption tests before this risk can close.

### Clipboard, QR, And Payment URI Behavior

- A sensitive clipboard helper exists and is used for seed, backup password, 2FA secrets, and wallet keys.
- Receive QR/address copy uses normal `Clipboard.setData`, including address URI copy.
- The PIVX send page has a shielded-balance toggle, but payment URI parsing is generic and does not carry PIVX Sapling-specific memo/privacy semantics beyond the shared `note` field.
- Shielded transaction UR encoding returns an empty map.

Code references:
- `lib/utils/clipboard_util.dart:6-14`
- `lib/src/screens/seed/wallet_seed_page.dart:30-31`
- `lib/src/screens/wallet_keys/wallet_keys_page.dart:399`
- `lib/src/screens/receive/widgets/qr_widget.dart:225-229`
- `lib/src/screens/receive/widgets/qr_widget.dart:263-265`
- `lib/utils/payment_request.dart:8-67`
- `lib/src/screens/send/widgets/send_card.dart:762-790`
- `lib/src/screens/send/widgets/send_card.dart:900-945`
- `cw_pivx/lib/src/pending_pivx_shielded_transaction.dart:88-91`

Assessment:
Shielded addresses are not secret like seeds, but they are privacy-sensitive metadata. PIVX should define whether shielded addresses, payment URIs, and memos use normal clipboard, sensitive clipboard, auto-clear behavior, or an explicit user warning.

### Screenshot And App Switcher Protection

- Android has a native `FLAG_SECURE` bridge.
- iOS has a secure text-field based bridge.
- The setting is present under privacy settings, but defaults to false.

Code references:
- `cw_core/lib/set_app_secure_native.dart:3-8`
- `android/app/src/main/java/com/cakewallet/cake_wallet/MainActivity.java:52-58`
- `ios/Runner/AppDelegate.swift:76-89`
- `lib/store/settings_store.dart:327-333`
- `lib/store/settings_store.dart:1048-1050`
- `lib/src/screens/settings/privacy_page.dart:76-83`

Assessment:
The control exists, but PIVX seed, key, shielded note, and viewing-key contexts currently depend on a global opt-in defaulting off.

### Native Library Packaging And Release Configuration

- Dart loads platform-specific `cw_pivx_sapling` native libraries dynamically or via process/framework lookup.
- Android plugin also calls `System.loadLibrary("cw_pivx_sapling")`.
- iOS podspec copies and force-loads static libraries from a checked-in xcframework.
- Checked-in Android `.so` files exist for arm64-v8a, armeabi-v7a, x86_64, and x86.
- Build script only rebuilds PIVX Android native libraries when one arm64 file is missing; otherwise it reuses existing binaries.
- Android debug builds use the release signing config.
- iOS ATS allows arbitrary loads globally.

Code references:
- `cw_pivx/lib/src/sapling/sapling_ffi.dart:20-43`
- `cw_pivx/android/src/main/kotlin/com/cakewallet/cw_pivx/CwPivxPlugin.kt:19-25`
- `cw_pivx/ios/cw_pivx.podspec:23-42`
- `scripts/build_android_macos.sh:98-114`
- `android/app/build.gradle:79-94`
- `ios/Runner/InfoBase.plist:350-354`

Assessment:
Release provenance is not yet deterministic enough for a native Sapling library that handles private key material and proof generation.

## Findings

Stage 7 findings are recorded in `11_findings_register.md`:

- `PIVX-MOB-001` High: Sapling note/address sidecar is plaintext in app documents storage.
- `PIVX-MOB-002` High: Cake backup can include plaintext PIVX Sapling sidecar state without a dedicated sensitive-state policy.
- `PIVX-MOB-003` Critical: PIVX errors/logs can leak seed phrases and shielded metadata, then expose them through crash/support/copy flows.
- `PIVX-MOB-004` High: FFI/native key and transaction buffers are freed without a consistent zeroization policy.
- `PIVX-MOB-005` High: PIVX network privacy is weakened by permissive TLS and proving downloads that bypass Tor/proxy policy.
- `PIVX-MOB-006` Medium: Shielded receive/payment clipboard and URI flows lack a PIVX privacy policy.
- `PIVX-MOB-007` Medium: Screenshot/app-switcher protection exists but is opt-in and not enforced on PIVX sensitive screens.
- `PIVX-MOB-008` High: Native Sapling library artifacts are not release-provenanced or rebuilt deterministically.
- `PIVX-MOB-009` Medium: iOS ATS permits arbitrary loads globally, conflicting with a strict PIVX network-security posture.

## Recommended Release Gates

Before external APK/TestFlight:

1. Encrypt PIVX Sapling sidecar state at rest, or move it into an encrypted database/key-file model aligned with the existing wallet password architecture.
2. Redact all PIVX seed, note, nullifier, cmu, witness, balance, and address-history logs by default.
3. Sanitize PIVX restore exceptions so seed text never enters logs, UI error strings, crash reports, or clipboard.
4. Route proving parameter downloads through the same Tor/proxy policy as user-selected network traffic, with pinned hashes and release-canonical hosts.
5. Stop accepting bad TLS certificates for PIVX Electrum SSL nodes unless the user explicitly opts into a dangerous custom-node mode.
6. Zero native FFI seed copies and other sensitive buffers before free, and document the Rust/Dart memory-hardening boundary.
7. Define the PIVX clipboard/QR/payment URI privacy policy for shielded addresses and memos.
8. Make native Sapling library builds reproducible in release CI, with per-ABI hashes/version checks.
9. Decide whether PIVX-sensitive screens must force screenshot protection even when the global setting is off.
