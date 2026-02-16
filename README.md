# 🏯 ROLODOJO

Privacy-first, local-encrypted personal ledger built with Flutter.

ROLODOJO stores user inputs as auditable ledger events ("Rolos"), keeps current facts in a URI-addressed vault, and routes Sensei parsing through a local-first LLM setup with rule-based fallback.

## What the app does now

- Captures user summonings into `tbl_rolos`
- Parses structured facts and upserts `tbl_records` + `tbl_attributes`
- Preserves audit linkage with `last_rolo_id` on attribute changes
- Stores Sensei responses in `tbl_sensei` linked by `input_rolo_id`
- Maintains owner profile in `tbl_user`
- Supports Journal Mode entries and daily/weekly summaries
- Provides search, vault inspection, backup/export, and optimization tools

## Architecture

- **Framework:** Flutter (Dart)
- **Layers:** Data / Domain / Presentation (Clean Architecture)
- **Storage:** SQLCipher via `sqflite_sqlcipher`
- **Secrets:** `flutter_secure_storage`
- **Biometrics:** `local_auth`
- **Backup encryption:** AES-256-CBC via `encrypt`
- **LLM routing:** local-first (`localhost`) with optional online providers

## Local-first LLM behavior

- Default provider is local llama endpoint (`http://localhost:11434/v1`)
- If local LLM is unavailable, the app keeps working with rule-based parsing
- Cloud providers are optional and require explicit API key configuration in Settings

See:
- [`local_inference.md`](./local_inference.md)
- [`ledger_structure.md`](./ledger_structure.md)

## Run and test

```bash
flutter pub get
flutter run
flutter test
flutter test integration_test/system_integrity_test.dart
```

If your checkout does not include `android/` and `ios/` folders yet:

```bash
flutter create --org com.rolodojo .
./configure_platform_permissions.sh .
```

Optional provider override:

```bash
flutter run --dart-define=LLM_PROVIDER=llama
```

## Notes

- Database and secrets remain local to the device by default.
- Summonings may include location metadata when permissions are granted.

