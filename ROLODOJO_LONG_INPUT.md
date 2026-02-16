# 📑 ROLODOJO Long Input Notes

## Current behavior

Long-form document ingestion is **not implemented** in the current app.
Inputs are processed as standard summonings through `DojoService.processSummoning()`.

## Future direction (design only)

If batch/document ingestion is added later, it should:

- preserve full audit lineage back to the source input
- avoid bypassing validation/repository layers
- emit standard Rolo events so downstream features continue to work
