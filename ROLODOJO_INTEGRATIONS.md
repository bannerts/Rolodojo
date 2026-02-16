# 🔌 ROLODOJO Integrations

This document tracks external integrations.

## Current status

The app currently operates on local/manual inputs and does not yet ingest live Gmail, telephony, or alarm streams.

## Planned integrations

1. **Google ecosystem**
   - Gmail ingestion via OAuth and label-based polling
   - Calendar event read/write for `dojo.sys.schedule`

2. **Telephony**
   - Call log and SMS ingestion (permission-gated)
   - Caller matching against `dojo.con.*` and known attributes

3. **System reminders**
   - Alarm/reminder scheduling from user requests
   - Local notifications for synthesis confirmations

## Integration invariants

- Every integration event must create a Rolo in `tbl_rolos`.
- External source identifiers (for example message/call IDs) should be stored in Rolo metadata (`source_id`) for replay and deduplication.

