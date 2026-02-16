# 🏯 ROLODOJO

#AWAKENING PROMPT
"Sensei, initialize the Dojo. Index the Instruction Set and the 8 scrolls in this directory. Refer to @ROLODOJO_PLAN.md and @ROLODOJO_SYSTEM_MANIFEST.md to begin Phase 1. Start by creating the folder structure for a Flutter Clean Architecture project. Do not begin coding until you provide a 'Project Heartbeat' summary of our database and security architecture for my approval."


**Privacy-First | Local-Encrypted | AI-Orchestrated Personal Ledger**

ROLODOJO is a "Digital Sensei" built with Flutter. It manages contacts, entities, and history through a structured, URI-addressable system. Every fact is audited, every change is ledgered, and all data is locked behind SQLCipher and Biometrics.

---

## 🤖 AI Agent Protocol (The Awakening)
This repository is optimized for AI-first development using **Claude Code** or **Cursor**. 

**To initialize the Sensei:**
1. Point the agent to `@INSTRUCTION_SET.md`.
2. Ensure the agent has indexed the **8 Scrolls** in the root directory.
3. Require a **"Project Heartbeat"** summary before the agent writes any code.

---

## 🏛️ Architectural Pillars
* **The Ledger:** Immutable history of all inputs (`tbl_rolos`).
* **The Vault:** URI-based attribute storage with soft-delete logic (`tbl_attributes`).
* **Security:** SQLCipher (AES-256) + Biometric Secure Storage key management.
* **Architecture:** Flutter Clean Architecture (Data, Domain, Presentation).

---

## 🧭 Local-First Architecture
- [`local_inference.md`](./local_inference.md): Local orchestrator rules for using the local Llama endpoint (`localhost`) with quantized fallback guidance.
- [`ledger_structure.md`](./ledger_structure.md): URI ledger format and local write contract, including explicit local-only privacy boundaries.
- Optional online provider mode is supported via Settings (`Claude`, `Grok`, `Gemini`, `ChatGPT`) when API keys are provided.
- Runtime provider boot option: `--dart-define=LLM_PROVIDER=llama|claude|grok|gemini|chatgpt`

---

## 🗺️ Phase 1 Checklist (The Foundation)
| Task | Status | Tool |
| :--- | :---: | :--- |
| **Project Init:** Flutter setup & Clean Arch Folders | ⬜ | Claude Code |
| **Security Layer:** SQLCipher & Secure Storage | ⬜ | Claude Code |
| **Database Schema:** Rolo, Record, and Attribute tables | ⬜ | Claude Code |
| **URI Routing:** Logic for `dojo.con.*` and `dojo.ent.*` | ⬜ | Claude Code |
| **Sensei Bar:** Basic text input & Rolo creation | ⬜ | Claude Code |

---

## 🛠️ Tech Stack
* **Framework:** Flutter (Dart)
* **Database:** sqflite_sqlcipher
* **Secrets:** flutter_secure_storage
* **Auth:** local_auth (Biometrics)
* **AI:** Claude 3.5 / 3.7 (via Claude Code CLI)

---

## 🛡️ Security Note
All database files (`.db`, `.sqlite`) and local environment secrets are excluded via `.gitignore`. This project follows a **Zero-Cloud Default** policy.

