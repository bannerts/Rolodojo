# 📜 ROLODOJO System Manifest: The Prime Directive

## 1. Core Mission
The Rolodojo is a privacy-first, local-encrypted "Digital Sensei" designed to manage contacts (Rolos), entities, and personal history with absolute auditing. It replaces messy, fragmented notes with a structured, URI-addressable "Vault of Truth."

## 2. The Golden Rules
- **Privacy First:** Data lives on the device in an encrypted SQLCipher database.
- **Audit Everything:** No fact exists in the Dojo without a "Rolo" (a receipt/event) explaining where it came from.
- **URI Driven:** All entities are addressed via dot-notation (e.g., `dojo.con.steve`, `dojo.ent.railroad_gate`).
- **Local Sovereignty:** The user owns the keys. The Sensei is the servant.
- **Local-First LLM:** AI inference defaults to local Llama. Optional online providers are user-selectable with explicit API key configuration.

## 3. System Components
- **The Sensei (Orchestrator):** `DojoService` — parses inputs via `InputParser` and optional local LLM (`SenseiLlmService`), creates Rolos, and updates the Vault.
- **The Scribe (Database Layer):** Repository implementations (`RoloRepositoryImpl`, `RecordRepositoryImpl`, `AttributeRepositoryImpl`) backed by `LocalDataSource` writing to SQLCipher.
- **The Librarian (Search/Retrieval):** `LibrarianService` — full-text search across URIs, attributes, and Rolo history.
- **The Guard (Security):** `SecurityService` — SQLCipher master key management via Flutter Secure Storage, biometric gate via `BiometricService`.
- **The Synthesizer:** `SynthesisService` — detects patterns in Rolo data and suggests new attributes with confidence scores.
- **The Optimizer:** `OptimizationService` — compresses old Rolos into Ghost records to reduce storage.
- **The DojoProvider:** `InheritedWidget`-based dependency injection that initializes the encrypted DB and wires all services at app startup.

## 4. Operational Persona: The Sensei
When interacting with the user, the AI must act as the "Sensei":
- **Tone:** Grounded, concise, and professional.
- **Goal:** Minimize data entry friction while maximizing data integrity.
- **Method:** "Trust, but Verify." Always confirm synthesis with the user before committing to the Vault.
- **Confirmation UI:** Synthesis suggestions are presented as gold-bordered cards with Accept/Reject buttons.
