# Rolodojo Documentation vs. Implementation Review

**Date:** 2026-02-10
**Branch:** claude/review-rolodojo-docs-UQV3o
**Scope:** Cross-reference all .md specification files against implemented code

---

## Phase 1: The Foundation (White Belt) — ~90% Complete

| Spec Item | .md Source | Status | Files |
|---|---|---|---|
| Flutter + Clean Architecture | PLAN, CLAUDE | Done | `lib/data/`, `lib/domain/`, `lib/presentation/` |
| SecurityService: SQLCipher + Secure Storage | SECURITY | Done | `lib/core/services/security_service.dart` |
| Rockstone Schema: 3 tables | CONTEXT | Done | `security_service.dart:39-97` |
| URI Routing | CONTEXT | Done | `lib/domain/entities/dojo_uri.dart`, `lib/core/services/uri_router.dart` |
| Sensei Bar (basic input) | UX_UI | Done | `lib/presentation/widgets/sensei_bar.dart` |

### Gaps

- **No FK constraints.** `ROLODOJO_CONTEXT.md` specifies `ON DELETE SET NULL` for `last_rolo_id`, but the schema defines no `FOREIGN KEY` clauses. Additionally, `tbl_attributes.last_rolo_id` is `NOT NULL`, which contradicts the soft-delete flow requiring `ON DELETE SET NULL`.
- **Empty layers.** `core/error/` and `core/usecases/` contain only `.gitkeep` files. Clean Architecture expects use cases in the domain layer.

---

## Phase 2: The Scribe & The Card (Blue Belt) — ~60% Complete

| Spec Item | .md Source | Status | Files |
|---|---|---|---|
| Input parsing | PLAN | Done | `lib/core/services/input_parser.dart` |
| Audit trail (`last_rolo_id`) | CONTEXT, SECURITY | Done | `lib/domain/entities/attribute.dart` |
| Flip Card UI | UX_UI | Done | `lib/presentation/widgets/flip_card.dart` |
| Soft-delete (NULL values) | CONTEXT | Done | Attribute entity supports it |
| Dojo Dark theme + 16px cards | UX_UI | Done | `lib/core/constants/dojo_theme.dart` |

### Gaps

- **UI is not connected to the database.** `dojo_home_page.dart` uses in-memory `_RoloPreview` objects and `Future.delayed()` to simulate processing. Parsed input is never written to `tbl_rolos` or `tbl_attributes` via the repository layer.
- **`data_payload` mismatch.** `ROLODOJO_DATA_SPECIFICATION.md` defines a JSON payload structure (header, entities, context) and references a `data_payload` column, but the schema uses `summoning_text` + `metadata` instead.
- **Conflict resolution unimplemented.** The "Rule of Recency" with a `history` array (DATA_SPECIFICATION) has no code.
- **Formatting standards unenforced.** E.164 phone numbers, ISO 8601 dates, Title Case names (DATA_SPECIFICATION) are not validated in the input parser or models.

---

## Phase 3: The Connected Dojo (Purple Belt) — ~25% Complete

| Spec Item | .md Source | Status | Files |
|---|---|---|---|
| Gmail Sync (OAuth2) | INTEGRATIONS | Stubbed | `lib/core/services/gmail_service.dart` (abstract + MockGmailService) |
| Telephony (Call/SMS) | INTEGRATIONS | Stubbed | `lib/core/services/telephony_service.dart` (abstract + MockTelephonyService) |
| Biometric Gate | SECURITY | Done | `lib/presentation/pages/biometric_gate_page.dart` |
| Librarian Search | MANIFEST | Partial | `lib/core/services/librarian_service.dart`, `lib/presentation/pages/search_page.dart` |

### Gaps

- **Gmail is abstract-only.** No `googleapis` package in `pubspec.yaml`. Calendar integration for `dojo.sys.schedule` (INTEGRATIONS) has no code.
- **Telephony is abstract-only.** `MockTelephonyService.parseSmsForData()` has some regex, but actual call log monitoring is unimplemented.
- **Biometric gate is bypassed.** `main.dart:41` sets `_devMode = true`, skipping biometrics.
- **System Alarms/Notifications** (INTEGRATIONS) have zero implementation.
- **Integration rule violation.** INTEGRATIONS states "Every integrated event MUST generate a Rolo" — the data models prepare metadata but the Rolo creation pipeline doesn't exist.

---

## Phase 4: Mastery & Synthesis (Black Belt) — ~40% Complete

| Spec Item | .md Source | Status | Files |
|---|---|---|---|
| Sensei Synthesis | PLAN, GLOSSARY | Implemented | `lib/core/services/synthesis_service.dart` |
| Encrypted Backup (.dojo) | SECURITY | Partial | `lib/core/services/backup_service.dart` |
| Ghost Rolo Optimization | PLAN | Partial | `lib/core/services/optimization_service.dart` |

### Gaps

- **No local LLM.** `CLAUDE.md` mandates `llama_flutter` for local LLM inference. No such dependency exists in `pubspec.yaml` and no LLM code exists.
- **Backup is not encrypted.** `backup_service.dart:219` uses `base64Encode` as a placeholder. SECURITY spec requires actual encryption for `.dojo` files.
- **Optimization is a no-op.** `optimization_service.dart:183` has the database update commented out. It calculates stats but doesn't modify anything.
- **`ROLODOJO_LONG_INPUT.md` is unimplemented.** The Master Rolo / `MASTER_INPUT` type / recursive child Rolo system described there has no code.

---

## Cross-Cutting Issues

### Documentation Inconsistencies

| Issue | Detail |
|---|---|
| `data_payload` column | DATA_SPECIFICATION references it; schema uses `summoning_text` + `metadata` |
| `INSTRUCTION_SET.md` | Describes an initialization ritual with no corresponding automation |
| `ROLODOJO_LONG_INPUT.md` | Not referenced in PLAN phases; entirely unimplemented |
| No state management | `presentation/bloc/` is empty; no BLoC, Provider, or Riverpod |

### Missing Dependencies (pubspec.yaml)

Phase 3+ would require: `googleapis`, `google_sign_in`, `call_log`, `telephony`, `permission_handler`, `workmanager`, `llama_flutter`

### Testing Gaps

- Only 1 integration test exists (`system_integrity_test.dart`)
- No unit tests for services, repositories, or domain logic
- The integration test import (`package:rolodojo/core/security_service.dart`) doesn't match the actual path (`lib/core/services/security_service.dart`)
- Test creates its own `tbl_attributes` schema with different columns than the real schema

### Security Concerns

- Master key generation (`security_service.dart:17`) concatenates two UUID v4 strings. UUIDs contain predictable structure (hyphens, version bits) and are not ideal cryptographic keys. A CSPRNG via `Random.secure()` would be more appropriate per SECURITY spec.
- `_devMode = true` in production-path code (`main.dart:41`)

---

## Summary

| Phase | Est. Completion | Primary Blocker |
|---|---|---|
| Phase 1 (White Belt) | ~90% | FK constraints, empty use-case layer |
| Phase 2 (Blue Belt) | ~60% | UI disconnected from database layer |
| Phase 3 (Purple Belt) | ~25% | Gmail/Telephony are stubs; no notifications |
| Phase 4 (Black Belt) | ~40% | No local LLM; backup not encrypted; optimization no-op |

**Systemic gap:** The presentation layer is not wired to the data layer. All UI interactions use in-memory mock data rather than reading/writing through repositories. Fixing this would substantially advance Phase 2 and enable Phases 3-4 to operate on real data.
