# 📑 ROLODOJO_LONG_INPUT: Document & Batch Logic

## 1. The Master Rolo
When a text file or long document is ingested:
- Create a single entry in `tbl_rolos` with `type: "MASTER_INPUT"`.
- Store the raw text in `summoning_text`.

## 2. Recursive Parsing (The Scribe's Duty)
The Sensei must split the Master Rolo into "Atomic Truths":
- **Entity Identification:** Isolate `dojo.con.*`, `dojo.ent.*`, etc.
- **Child Creation:** Create individual `type: "SYNTHESIS"` Rolos for each extracted fact.
- **Lineage:** Every child Rolo MUST contain `parent_rolo_id: [Master_Rolo_ID]` in its metadata.

## 3. UI Treatment
- Display the Master Rolo as a "Scroll" icon in the stream.
- Allow the user to "Expand" the scroll to see all associated child updates in a nested list.
