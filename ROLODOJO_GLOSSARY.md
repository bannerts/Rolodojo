# 📖 ROLODOJO Glossary: The Dojo Lexicon

- **Dojo:** The local, encrypted app environment. It is the "training hall" where your data is refined and stored.
- **Sensei:** The AI agent logic layer (orchestrator). Implemented as `DojoService` with optional `SenseiLlmService` for local LLM inference.
- **Rolo:** The atomic unit of the system. Every interaction—whether a user input, an AI response, or a background system update—is a Rolo. Stored in `tbl_rolos`.
- **Summoning:** The specific act of a user providing input (text, voice, or image) to create a new Rolo. Processed via `DojoService.processSummoning()`.
- **The Master Scroll:** The `tbl_records` table. It serves as the central registry for every URI (People, Places, Things).
- **The Vault:** The `tbl_attributes` table. This is where "soft data" (specific details like gate codes or coffee orders) lives.
- **Synthesis:** An AI-generated suggestion created when the `SynthesisService` detects patterns (repetition, co-occurrence) in existing Rolos. Presented as gold-bordered cards with Accept/Reject.
- **Rockstone:** The architectural philosophy that the database schema must remain permanent and immutable to ensure long-term data integrity.
- **The Scribe:** The Sensei's function of parsing and writing data to the ledger. Implemented via `InputParser` and repository layer.
- **The Librarian:** The Sensei's function of searching, retrieving, and presenting data to the user. Implemented as `LibrarianService`.
- **The Guard:** The security layer. Implemented as `SecurityService` (SQLCipher key management) and `BiometricService` (FaceID/Fingerprint).
- **URI (Uniform Resource Identifier):** The dot-notation address for any object in the Dojo (e.g., `dojo.con.steve`). Implemented via `DojoUri` entity.
- **Ghost:** A compressed version of an old Rolo, created by `OptimizationService`. Preserves the Rolo ID and audit trail while replacing the summoning text with a short summary, prefixed with `[GHOST]`.
- **DojoProvider:** The `InheritedWidget` that serves as the dependency injection container, initialized at app startup with all services and repositories.
- **Flip Card:** The UI interaction that reveals the audit trail (source Rolo) for any fact in the Vault. Implemented as `FlipCard` and `AttributeFlipCard` widgets.
