# URI Ledger Structure: `ledger_structure.md`

This document defines how local inference output is written into a local ledger without any cloud data transfer.

## 1) Ledger Scope

- Ledger is **local-only**.
- Storage backend can be:
  - encrypted SQLite (primary path),
  - or local JSON ledger export/import representation.
- The LLM does not write raw records directly.  
  The orchestrator validates and writes through repository/service layers.

## 2) Canonical Ledger URI

Example activity URI:

`ledger://local/2026/02/16/activity_01`

URI parts:

- `ledger://` -> ledger scheme
- `local` -> explicit local authority/scope
- `2026/02/16` -> date partition for audit browsing
- `activity_01` -> deterministic or sequence activity token

## 3) Mapping to Dojo Data Model

The app uses dot-notation Dojo subject URIs for entities (example: `dojo.con.joe`) and can additionally track ledger event URIs for activity partitioning.

Recommended mapping:

- `ledger://local/.../activity_xx` -> source event reference
- `tbl_rolos.id` -> immutable event primary key
- `tbl_rolos.target_uri` -> subject URI (`dojo.con.*`, `dojo.ent.*`, etc.)
- `tbl_attributes.last_rolo_id` -> mandatory audit link back to the source event

Result:

- Every attribute mutation has a cryptographic/storage trail and source event.
- Ledger URI can be stored in metadata for import/export or forensic replay.

## 4) Local Write Contract

Write pipeline:

1. Receive user input or local LLM extraction.
2. Validate extraction (subject/key/value/query).
3. Create immutable Rolo entry.
4. Upsert record and attribute.
5. Attach `last_rolo_id` for every attribute change.

Safety rules:

- Reject writes missing audit linkage.
- Never allow LLM to bypass validation.
- Never write secrets/keys to logs.

## 5) Privacy Boundary

Explicit privacy statement:

- **No ledger payload leaves the local URI scope.**
- `ledger://local/...` is treated as a strict local trust boundary.
- Inference, parsing, and persistence remain local by default.
- Any future sync/export must be explicit, user-triggered, and encrypted.

## 6) Optional JSON Ledger Representation

When serializing to local JSON, preserve both ledger URI and Dojo URI context:

```json
{
  "ledger_uri": "ledger://local/2026/02/16/activity_01",
  "rolo_id": "uuid-v4",
  "target_uri": "dojo.con.jane_doe",
  "attribute_key": "coffee_preference",
  "attribute_value": "espresso",
  "last_rolo_id": "uuid-v4",
  "timestamp_utc": "2026-02-16T12:30:00Z"
}
```

## 7) Enforcement Checklist

- [ ] Local endpoint only for inference (`localhost` by default)
- [ ] Immutable event creation before attribute mutation
- [ ] `last_rolo_id` set on all attribute writes
- [ ] No cloud transmission of ledger payloads
- [ ] Encrypted-at-rest local store remains default

