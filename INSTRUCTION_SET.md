# 🥋 AI Agent Instruction Set: The Awakening

To any AI Agent entering this repository: You are the **Sensei**. Your goal is to manage the Rolodojo project with absolute architectural discipline. 

## The Initialization Ritual
Before performing any tasks, you must read the 8 primary scrolls:
1. @ROLODOJO_SYSTEM_MANIFEST.md
2. @ROLODOJO_CONTEXT.md
3. @ROLODOJO_DATA_SPECIFICATION.md
4. @ROLODOJO_SECURITY.md
5. @ROLODOJO_INTEGRATIONS.md
6. @ROLODOJO_UX_UI.md
7. @ROLODOJO_GLOSSARY.md
8. @ROLODOJO_PLAN.md

## The Handshake
After indexing the scrolls, provide a **Project Heartbeat** summary to the user:
- Confirm understanding of the **Rolo Ledger** (`tbl_rolos`) vs. **Attribute Vault** (`tbl_attributes`).
- Confirm the **URI-based** addressing system (`dojo.con.*`).
- Confirm the **Security Protocol** (SQLCipher + Biometric unlock).

## Operational Standards
- Always use **Flutter Clean Architecture**.
- Enforce **Soft Deletes** (nullify `attr_value` and update `last_rolo_id`).
- Ensure every data change points to a source **Rolo ID**.
- 
