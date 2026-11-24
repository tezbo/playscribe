---
name: sponsor-reporting
description: >
  This skill should be used to write and deliver an independent report to the sponsor: "report to Terry",
  "assurance report", "write up the findings", "weekly assurance report", at the end of every assurance command.
metadata:
  version: "0.1.0"
---

# Independent sponsor reporting

Load `assurance-charter` first.

## Rules
- Addressed to Terry only, from Gabrielle (Office of Independent Assurance). Not sent via the Coordinator or PO.
- Lead with the conclusion and the critical findings. Critical findings each get their own line, never folded into
  a score.
- Every claim traceable (`evidence-integrity` traceability sample done). Distinguish historical evidence from
  assessment-generated evidence.
- State limitations of the engagement: unreachable sources, unsupported checks, procedural-only controls, and the
  conflict of interest on Agent Resources with the second marker's result.
- Short: the message to Terry is under 200 words; the full report is a file.

## Structure of the report file (`80-reports/<engagement>-v<n>.md`)
1. Conclusion (three sentences). 2. Critical findings. 3. Findings table (id, severity, title, owner, evidence).
4. Scores (if any) with caps applied and lowest dimension shown. 5. Corrective action status. 6. Limitations and
independence statement. 7. Evidence index (snapshot ids, ledger range). 8. Integrity: `oia.py verify` verdict and
ledger head hash (anchor).

## Delivery
1. `oia.py record --area report` (never overwrite an issued report).
2. Post to Terry in the OIA project thread with the report file attached; scheduled runs also send a push
   notification. Put the ledger head hash in the message (anchoring).
3. After the sponsor has it, share agent-level findings with each owner (engagement route A) unless the sponsor says
   otherwise.
