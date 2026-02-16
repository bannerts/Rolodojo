# 🔐 ROLODOJO_SECURITY: Encryption & Privacy Protocol

## 1. Local-First Lockdown
- **Database:** SQLite with **SQLCipher** (AES-256 encryption).
- **The Key:** The database master key is generated on first boot (two concatenated UUIDs) and stored in the **Flutter Secure Storage** (Keychain for iOS / Keystore for Android).
- **Access:** Biometric Authentication (FaceID/Fingerprint) is required to unlock the Secure Storage and provide the decryption key to the database. No biometrics = No database access. Implemented via `BiometricGatePage` with a blurred overlay.

## 2. Privacy Guardrails
- **Zero-Cloud Default:** No data is sent to external servers. The local LLM (`SenseiLlmService`) runs entirely on-device via Llama 3.2 / llama.cpp FFI bindings.
- **LLM Privacy:** All inference runs locally. No PII tokenization is needed since data never leaves the device. External AI APIs are strictly forbidden per the Zero-Cloud policy.

## 3. Data Integrity & Auditing
- **Immutable Ledger:** Records in `tbl_rolos` are never modified or deleted (except Ghost optimization which replaces only the summoning text); they serve as the permanent "black box" for the Dojo.
- **Audit Requirement:** No change can occur in the Attribute Vault (`tbl_attributes`) without a corresponding `last_rolo_id` linking to the source event.
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
