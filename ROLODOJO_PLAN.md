# 🗺️ ROLODOJO Roadmap (Current)

This roadmap focuses on current behavior and near-term work.

## Implemented foundations

- Clean architecture with Data / Domain / Presentation separation
- Encrypted SQLCipher storage with secure key storage
- URI-based records and audited attribute updates (`last_rolo_id`)
- Summoning pipeline (`DojoService.processSummoning`) wired to repositories
- Vault inspection, edit, and soft-delete flows
- Search (`LibrarianService` + `SearchPage`)
- Journal mode with follow-ups and daily/weekly summaries
- Sensei response persistence (`tbl_sensei`)
- Local-first LLM routing with health checks and parser fallback
- Backup/export and optimization tooling

## In progress / open

- Tighten biometric lock controls in Settings (currently informational toggle)
- Improve coverage with more unit tests around services/repositories
- Expand normalization/validation for parsed values

## Planned (not implemented yet)

- Gmail integration (OAuth + labeled message ingestion)
- Telephony integration (call/SMS ingestion)
- Voice input for summonings
- Optional encrypted cloud backup path
