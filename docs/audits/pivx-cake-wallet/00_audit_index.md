# PIVX Cake Wallet Audit Index

Audit workspace: `docs/audits/pivx-cake-wallet/`

Scope: audit-only review of PIVX integration before test APK distribution and iOS TestFlight preparation. Highest-risk area is PIVX Sapling/shield support, including shielded receiving and shielded sending.

Repository state note: this audit workspace was originally created without modifying production code. A wallet-side implementation pass began on 2026-05-27; production-code changes and follow-up documentation are now tracked in the release gate checklist, findings register, next-session context, and ElectrumX follow-up notes.

## Stage Status

| Stage | Area | Artifact | Status |
| --- | --- | --- | --- |
| 0 | Create audit workspace | `00_audit_index.md`, all artifact files | Complete |
| 1 | Repository discovery and integration map | `01_integration_map.md` | Complete |
| 2 | Sapling receive audit | `02_sapling_receive_audit.md` | Complete |
| 3 | Sapling send audit | `03_sapling_send_audit.md` | Complete |
| 4 | Balance and wallet state audit | `04_balance_wallet_state_audit.md` | Complete |
| 5 | Restore and key derivation audit | `05_restore_key_derivation_audit.md` | Complete |
| 6 | Network and configuration audit | `06_network_config_audit.md` | Complete |
| 7 | Mobile security audit | `07_mobile_security_audit.md` | Complete |
| 8 | UI/UX audit | `08_ui_ux_audit.md` | Complete |
| 9 | Release gate and test plan | `09_release_gate_checklist.md`, `10_test_plan.md` | Complete |

## Implementation Tracking

Status as of 2026-05-28: wallet-side work has started on the highest-risk Critical/High PIVX release blockers. The implementation ledger is maintained in `09_release_gate_checklist.md`; detailed finding status is maintained in `11_findings_register.md`; carry-forward context is maintained in `13_next_session_context.md`; server/indexer work is maintained separately in `14_electrumx_followups.md`.

Current release posture remains unchanged: PIVX is not ready for external APK distribution or iOS TestFlight. Do not begin external APK/TestFlight preparation until the release gates and manual tests pass.

## Required Audit Artifacts

- `00_audit_index.md`: staged audit plan and status.
- `01_integration_map.md`: repository discovery and PIVX integration map.
- `02_sapling_receive_audit.md`: shielded receiving audit.
- `03_sapling_send_audit.md`: shielded sending audit.
- `04_balance_wallet_state_audit.md`: balance and wallet state audit.
- `05_restore_key_derivation_audit.md`: seed, key derivation, and recovery audit.
- `06_network_config_audit.md`: network/configuration/release safety audit.
- `07_mobile_security_audit.md`: Android/iOS storage, logging, privacy, lifecycle audit.
- `08_ui_ux_audit.md`: user-facing PIVX wallet behavior audit.
- `09_release_gate_checklist.md`: readiness gates.
- `10_test_plan.md`: manual and platform test plan.
- `11_findings_register.md`: cumulative findings register.
- `12_open_questions.md`: unresolved verification items.
- `13_next_session_context.md`: compact context for future sessions.
- `14_electrumx_followups.md`: separate server-side ElectrumX prompts and required RPC/indexer work.

## Severity Rules

- Critical: likely loss of funds, seed/private key leak, wrong-network send, permanent restore failure, or unrecoverable shielded funds.
- High: likely incorrect shielded send/receive behavior, incorrect balance, privacy leak, stuck funds, broken restore, or unsafe release behavior.
- Medium: edge-case sync failure, lifecycle issue, confusing UI, incomplete recovery, reorg issue, tester confusion.
- Low: cleanup, maintainability, logging, minor UX, documentation gaps.

## Stage 1 Discovery Summary

Searches found:

- 152 direct PIVX-referencing files/code paths, excluding generated build outputs and the new audit workspace.
- 66 dedicated `cw_pivx` package source/native/build/test paths under the package areas searched.
- 227 Sapling/shield keyword hits in the narrowed `cw_pivx`, `lib`, `cw_core`, and `cw_bitcoin` search set; this includes relevant PIVX paths plus expected false positives from shared wallet code and generic words.

Stage 1 mapped the high-signal PIVX-related paths and explicitly deferred behavioral review to later stages.
