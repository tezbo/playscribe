---
name: report
description: >
  Compile and deliver an independent report straight to the sponsor from existing working papers. Use for
  "/independent-assurance:report", "send Terry the assurance report", "report findings".
argument-hint: "<engagement id> | status"
metadata:
  version: "0.1.0"
---

# /independent-assurance:report

Load `assurance-charter` and `sponsor-reporting`.

| Contract | |
|---|---|
| Inputs | Engagement id (report on it) or `status` (open findings, CAs, last runs, next scheduled runs) |
| Outputs | `80-reports/<id>-v<n>.md`; a message to the sponsor (under 200 words) with the file and ledger head hash |
| Permissions | Write the report under `oia/`; post only to the sponsor's OIA thread |
| Evidence | Traceability sample of five sentences passed; integrity PASS |
| Done when | Report recorded in the ledger, delivered, and the delivery recorded (`oia.py ledger --event report-delivered`) |

If integrity fails, deliver a short integrity-failure notice instead of the report.
