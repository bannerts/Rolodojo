# 🏛️ ROLODOJO_CONTEXT: Architectural Spine & URI Standards

## 1. The URI Hierarchy (The "Dojo Paths")
All data objects must be addressed using a dot-notation URI. This allows the Sensei to perform "semantic drilling."

* **`dojo.con.*` (Contacts):** People, family, and professional relations.
    * *Example:* `dojo.con.jane_doe`
* **`dojo.ent.*` (Entities):** Physical places, businesses, or landmarks.
    * *Example:* `dojo.ent.railroad_land_gate`
* **`dojo.med.*` (Medical/Health):** Health logs, mood tracking, and symptoms.
* **`dojo.sys.*` (System):** Internal app state, sync logs, and mastery levels.

## 2. The "Rockstone" Schema (SQLite + SQLCipher)

### **A. tbl_rolos (The Ledger)**
*The immutable history of every interaction.*
- `rolo_id`: UUID (Primary Key)
- `type`: TEXT (INPUT, REQUEST, or SYNTHESIS)
- `summoning_text`: TEXT (The raw input or AI output)
- `target_uri`: TEXT (The URI this Rolo interacts with)
- `parent_rolo_id`: UUID (Self-reference for threading)
- `metadata`: JSON (GPS, weather, source_id for Email/Calls)
- `timestamp`: DATETIME (ISO8601)

### **B. tbl_records (The Dojo Data)**
*The current "State of Truth" for a URI.*
- `uri`: TEXT (Primary Key - e.g., `dojo.con.joe`)
- `display_name`: TEXT (Friendly label)
- `payload`: JSON (Standardized blob via Data Spec)
- `last_rolo_id`: UUID (FK to tbl_rolos)

### **C. tbl_attributes (The Vault)**
*Flexible key-value storage for "soft data."*
- `subject_uri`: TEXT (FK to tbl_records)
- `attr_key`: TEXT (e.g., "gate_code", "coffee_order")
- `attr_value`: TEXT (The data - NULL if soft-deleted)
- `last_rolo_id`: UUID (FK to tbl_rolos - The "Audit Receipt")
- `is_encrypted`: INT (Boolean 1/0 for sensitive rows)

## 3. Audit & Deletion Logic
- **Soft Deletes Only:** To "delete" an attribute, the Sensei sets `attr_value` to `NULL` and updates the `last_rolo_id` to the ID of the Rolo that requested the deletion.
- **Traceability:** Every fact in the Vault must point to a Rolo. This allows the Sensei to answer "Why do you know this?" by replaying the source Rolo's `summoning_text`.
- **Integrity:** `last_rolo_id` uses `ON DELETE SET NULL` to ensure database health if a Rolo is ever purged (though purging is discouraged).
- 
