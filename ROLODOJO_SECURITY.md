# 🔐 ROLODOJO_SECURITY: Encryption & Privacy Protocol

## 1. Local-First Lockdown
- **Database:** SQLite with **SQLCipher** (AES-256 encryption).
- **The Key:** The database master key is generated on first boot and stored in the **Flutter Secure Storage** (Keychain for iOS / Keystore for Android).
- **Access:** Biometric Authentication (FaceID/Fingerprint) is required to unlock the Secure Storage and provide the decryption key to the database. No biometrics = No database access.

## 2. Privacy Guardrails
- **Zero-Cloud Default:** No data is sent to external servers unless explicitly triggered by the user (e.g., initiating a Gmail sync).
- **LLM Synthesis Privacy:** When using LLMs for synthesis, PII (Personally Identifiable Information) like full names and phone numbers should be replaced with tokens (e.g., `[PERSON_1]`) before being sent to the cloud API, then re-mapped locally.

## 3. Data Integrity & Auditing
- **Immutable Ledger:** Records in `tbl_rolos` are never modified or deleted; they serve as the permanent "black box" for the Dojo.
- **Audit Requirement:** No change can occur in the Attribute Vault (`tbl_attributes`) without a corresponding `last_rolo_id` linking to the source event.

## 4. Backup & Recovery
- **Encrypted Export:** Backups are exported as a single encrypted `.dojo` file.
- **Cloud Sync:** Optional encrypted sync to a private, hidden app-data folder on Google Drive.
- 
