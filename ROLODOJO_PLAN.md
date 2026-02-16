# 🗺️ ROLODOJO Development Roadmap

## Phase 1: The Foundation (White Belt)
- [x] Initialize Flutter project with Clean Architecture (data, domain, presentation).
- [x] Setup `SecurityService`: SQLCipher initialization and Flutter Secure Storage key management.
- [x] Implement the "Rockstone" Schema: `tbl_rolos`, `tbl_records`, and `tbl_attributes` with FK constraints and `updated_at` columns.
- [x] Implement URI Routing: `DojoUri` entity with `InputParser` mapping strings to `dojo.con.*` and `dojo.ent.*` paths.
- [x] Create the "Sensei Bar": Persistent floating bottom-bar with Pulse icon and text input.
- [x] Wire presentation layer to data layer via `DojoProvider` (InheritedWidget-based dependency injection).

## Phase 2: The Scribe & The Card (Blue Belt)
- [x] **Input Logic:** `DojoService.processSummoning()` parses natural language into Input Rolos and updates the Attribute Vault.
- [x] **Audit Trail:** `FlipCard` / `AttributeFlipCard` UI shows source Rolo's `summoningText` for any given fact.
- [x] **Soft-Delete:** `Attribute.softDelete()` sets value to `NULL` with audit trail via `last_rolo_id`.
- [x] **UI Aesthetics:** "Dojo Dark" theme applied (`DojoColors`, `DojoTheme.dark`), 16px card radius throughout.

## Phase 3: The Connected Dojo (Purple Belt)
- [ ] **Gmail Sync:** Implement OAuth2 and "Dojo" label polling.
- [ ] **Telephony:** Setup Call Log monitoring and Caller ID URI matching.
- [x] **Biometrics:** `BiometricGatePage` locks the app behind FaceID/Fingerprint on cold start (with dev-mode skip).
- [x] **Search:** `LibrarianService` + `SearchPage` for full-text search across URIs, attributes, and Rolos.

## Phase 4: Mastery & Synthesis (Black Belt)
- [x] **Sensei Synthesis:** `SynthesisService` detects patterns (repetition, co-occurrence) and presents suggestion cards with Accept/Reject in the home page.
- [x] **Encrypted Backup:** `BackupService` exports/imports as AES-256-CBC encrypted `.dojo` files using the device master key.
- [x] **Optimization:** `OptimizationService` ghosts Rolos older than 90 days, compressing `summoning_text` while preserving audit trail.
- [x] **Local LLM:** `SenseiLlmService` / `LocalLlmService` wraps Llama 3.2 via `fllama` (llama.cpp FFI). Falls back to rule-based `InputParser` when model file unavailable.

## Remaining Work
- [ ] **Gmail Sync:** OAuth2 integration with "Dojo" label polling (Phase 3).
- [ ] **Telephony:** Call log monitoring and caller ID matching (Phase 3).
- [ ] **Voice Input:** Add speech-to-text for the Sensei Bar.
- [ ] **Google Drive Sync:** Optional encrypted cloud backup to hidden app-data folder.
