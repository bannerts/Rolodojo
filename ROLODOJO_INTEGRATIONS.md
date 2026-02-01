# 🔌 ROLODOJO_INTEGRATIONS: System & Service Hooks

## 1. Google Ecosystem (Gmail & Calendar)
- **Service:** Gmail API via OAuth2 (Local authentication).
- **Trigger:** Poll for messages with the "Dojo" label or specific keywords.
- **Action:** Convert email body into an "Input Rolo." Store `message_id` in Rolo metadata to prevent duplicates.
- **Calendar:** Create/Read events specifically for the `dojo.sys.schedule` URI.

## 2. Telephony (Calls & SMS)
- **Call Log:** Monitor incoming numbers via system permissions.
- **Spam Defense:** Cross-reference `caller_id` with `dojo.con.*` URIs. If no match is found, query the Attribute Vault for secondary matches.
- **SMS:** Parse specific structured texts (e.g., "Gate code is 1234") directly into the Attribute Vault via an Input Rolo.

## 3. System Alarms & Notifications
- **Alarms:** The Sensei can set system alarms based on Rolo requests (e.g., "Remind me to check the gate at 8 PM").
- **Local Notifications:** Used for "Sensei Synthesis" prompts—asking the user to confirm a fact extracted from a recent integration event.

## 4. Integration Logic
- Every integrated event MUST generate a Rolo in `tbl_rolos`.
- The `source_id` (e.g., Gmail Message ID or Call Log ID) must be stored in the Rolo metadata to ensure the "Librarian" can link back to the source.

