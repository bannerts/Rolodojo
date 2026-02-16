# 🏛️ ROLODOJO_CONTEXT: Architectural Spine & URI Standards

## 1. The URI Hierarchy (The "Dojo Paths")
All data objects must be addressed using a dot-notation URI. This allows the Sensei to perform "semantic drilling."

* **`dojo.con.*` (Contacts):** People, family, and professional relations.
    * *Example:* `dojo.con.jane_doe`
* **`dojo.ent.*` (Entities):** Physical places, businesses, or landmarks.
    * *Example:* `dojo.ent.railroad_land_gate`
* **`dojo.med.*` (Medical/Health):** Health logs, mood tracking, and symptoms.
* **`dojo.sys.*` (System):** Internal app state, sync logs, and mastery levels.

**Implementation:** The `DojoUri` entity (`lib/domain/entities/dojo_uri.dart`) and `InputParser` (`lib/core/services/input_parser.dart`) handle URI construction from natural language. The `DojoCategory` enum maps to each prefix.

## 2. The "Rockstone" Schema (SQLite + SQLCipher)

### **A. tbl_rolos (The Ledger)**
*The immutable history of every interaction.*
- `rolo_id`: TEXT PRIMARY KEY (UUID)
- `type`: TEXT NOT NULL (INPUT, REQUEST, or SYNTHESIS)
- `summoning_text`: TEXT (The raw input or AI output)
- `target_uri`: TEXT (The URI this Rolo interacts with)
- `parent_rolo_id`: TEXT (FK to `tbl_rolos` — `ON DELETE SET NULL` — for threading)
- `metadata`: TEXT (JSON — GPS, weather, source_id, confidence_score, trigger)
- `timestamp`: TEXT NOT NULL (ISO8601)

**Indexes:** `idx_rolos_target_uri`, `idx_rolos_timestamp` (DESC), `idx_rolos_parent`

### **B. tbl_records (The Dojo Data)**
*The current "State of Truth" for a URI.*
- `uri`: TEXT PRIMARY KEY (e.g., `dojo.con.joe`)
- `display_name`: TEXT NOT NULL (Friendly label)
- `payload`: TEXT (JSON — Standardized blob via Data Spec)
- `last_rolo_id`: TEXT (FK to `tbl_rolos` — `ON DELETE SET NULL`)
- `updated_at`: TEXT (ISO8601 timestamp of last modification)

**Indexes:** `idx_records_display_name`

### **C. tbl_attributes (The Vault)**
*Flexible key-value storage for "soft data."*
- `subject_uri`: TEXT NOT NULL (FK to `tbl_records` — `ON DELETE CASCADE`)
- `attr_key`: TEXT NOT NULL (e.g., "gate_code", "coffee_order")
- `attr_value`: TEXT (The data — NULL if soft-deleted)
- `last_rolo_id`: TEXT (FK to `tbl_rolos` — `ON DELETE SET NULL` — The "Audit Receipt")
- `is_encrypted`: INTEGER DEFAULT 0 (Boolean 1/0 for sensitive rows)
- `updated_at`: TEXT (ISO8601 timestamp of last modification)
- PRIMARY KEY (`subject_uri`, `attr_key`)

**Indexes:** `idx_attributes_key`

## 3. Audit & Deletion Logic
- **Soft Deletes Only:** To "delete" an attribute, the Sensei sets `attr_value` to `NULL` and updates the `last_rolo_id` to the ID of the Rolo that requested the deletion. Implemented via `Attribute.softDelete(roloId)`.
- **Traceability:** Every fact in the Vault must point to a Rolo. This allows the Sensei to answer "Why do you know this?" by replaying the source Rolo's `summoning_text`. The `FlipCard` UI provides this on tap.
- **Integrity:** `last_rolo_id` uses `ON DELETE SET NULL` to ensure database health if a Rolo is ever purged (though purging is discouraged).
- **Foreign Keys:** `PRAGMA foreign_keys = ON` is set at database open time. `subject_uri` cascades on record deletion.

## 4. Dependency Injection & Service Wiring
The `DojoProvider` (an `InheritedWidget`) is initialized at app startup via `DojoProvider.initialize()`. It:
1. Opens the encrypted SQLCipher database via `SecurityService`
2. Creates `LocalDataSource` and all repository implementations
3. Initializes the local LLM (`LocalLlmService`) with fallback to rule-based parsing
4. Constructs all services (`DojoService`, `LibrarianService`, `BackupService`, `SynthesisService`)
5. Exposes everything to the widget tree via `DojoProvider.of(context)`
