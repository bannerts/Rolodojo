# 🔐 ROLODOJO_SECURITY: Encryption & Privacy Protocol

## 1. Local-First Lockdown
- **Database:** SQLite with **SQLCipher** (AES-256 encryption).
- **The Key:** The database master key is generated on first boot (two concatenated UUIDs) and stored in the **Flutter Secure Storage** (Keychain for iOS / Keystore for Android).
- **Access:** Biometric Authentication (FaceID/Fingerprint) is required to unlock the Secure Storage and provide the decryption key to the database. No biometrics = No database access. Implemented via `BiometricGatePage` with a blurred overlay.

## 2. Privacy Guardrails
- **Local-First Default:** Inference defaults to local Llama (`SenseiLlmService`) via localhost endpoint.
- **Optional Online Providers:** Claude, Grok, Gemini, and ChatGPT can be user-selected in Settings. These modes require explicit API-key configuration.
- **LLM Privacy Modes:** In local mode, prompts never leave device/loopback. In online mode, prompt payloads are sent only to the selected provider endpoint.

## 3. Data Integrity & Auditing
- **Immutable Ledger:** Records in `tbl_rolos` are never modified or deleted (except Ghost optimization which replaces only the summoning text); they serve as the permanent "black box" for the Dojo.
- **Audit Requirement:** No change can occur in the Attribute Vault (`tbl_attributes`) without a corresponding `last_rolo_id` linking to the source event.
- **Sensei Journal Linkage:** Responses stored in `tbl_sensei` must reference an existing `input_rolo_id`.
- **Owner Profile Isolation:** User identity/preferences are stored in `tbl_user`, not mixed into contact records.
- **Foreign Key Enforcement:** `PRAGMA foreign_keys = ON` is set at database initialization. FK constraints use `ON DELETE SET NULL` for audit links and `ON DELETE CASCADE` for attribute-to-record links.

## 4. Backup & Recovery
- **Encrypted Export:** Backups are exported as a single `.dojo` file encrypted with **AES-256-CBC** using a key derived from the device master key. Format: `[16-byte IV][AES-256-CBC ciphertext]`. Implemented in `BackupService`.
- **Import/Merge:** The `BackupService.importBackup()` method supports merging with existing data or full replacement.
- **Cloud Sync:** Optional encrypted sync to a private, hidden app-data folder on Google Drive (planned, not yet implemented).

## 5. Key Implementation Files
- `lib/core/services/security_service.dart` — Master key management, SQLCipher database opening, schema initialization.
- `lib/core/services/backup_service.dart` — AES-256-CBC encrypted export/import of `.dojo` files.
- `lib/core/services/biometric_service.dart` — Biometric availability check and authentication.
- `lib/presentation/pages/biometric_gate_page.dart` — Blurred gate UI requiring biometric auth.
