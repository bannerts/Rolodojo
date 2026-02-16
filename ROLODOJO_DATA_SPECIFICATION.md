# 💾 ROLODOJO Data Specification (Current Implementation)

This file describes the data shapes currently used by the app.

## 1) Rolo row (`tbl_rolos`)

Rolo events are stored as table columns, not in a `data_payload` column.

Core fields:

- `rolo_id` (TEXT, UUID, PK)
- `type` (`input | request | synthesis`)
- `summoning_text` (TEXT)
- `target_uri` (TEXT, nullable)
- `parent_rolo_id` (TEXT, nullable)
- `metadata` (TEXT JSON)
- `timestamp` (TEXT ISO8601 UTC)

Example `metadata` JSON:

```json
{
  "trigger": "Manual_Entry",
  "confidence_score": 0.91,
  "location": "29.1234,-95.5678",
  "weather": "Clear",
  "source_id": "optional-external-id",
  "source_device": "optional-device-id"
}
```

## 2) Record + Attribute model

### `tbl_records`

- `uri` (PK, e.g. `dojo.con.joe`)
- `display_name`
- `payload` (optional JSON blob)
- `last_rolo_id` (FK to source rolo)
- `updated_at` (ISO8601)

### `tbl_attributes`

- `subject_uri` + `attr_key` (composite PK)
- `attr_value` (nullable for soft delete)
- `last_rolo_id` (FK to source rolo)
- `is_encrypted` (0/1 flag)
- `updated_at`

Soft delete behavior: `attr_value` becomes `NULL`, while key + `last_rolo_id` are retained for auditability.

## 3) Owner profile (`tbl_user`)

Owner identity/preferences are stored outside contact records.

```json
{
  "user_id": "owner",
  "display_name": "Dojo User",
  "preferred_name": "Scott",
  "profile_json": {
    "timezone": "America/Chicago",
    "locale": "en_US"
  },
  "created_at": "2026-02-16T12:00:00Z",
  "updated_at": "2026-02-16T12:00:00Z"
}
```

## 4) Sensei response row (`tbl_sensei`)

Each user input can persist a linked Sensei response.

```json
{
  "sensei_id": "uuid-v4",
  "input_rolo_id": "uuid-v4",
  "target_uri": "dojo.con.joe",
  "response_text": "Updated Joe's coffee preference to Espresso",
  "provider": "llama",
  "model": "llama3.3",
  "confidence_score": 0.91,
  "created_at": "2026-02-16T12:01:00Z"
}
```

## 5) Normalization guidance

The parser and UI should prefer:

- snake_case attribute keys
- lowercase URI segments with underscores
- ISO8601 timestamps
- normalized whitespace in user-entered values
