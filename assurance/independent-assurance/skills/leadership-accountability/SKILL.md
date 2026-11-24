---
name: leadership-accountability
description: >
  This skill should be used to assess leadership accountability of the Coordinator / Scrum Master, Product
  Owner and leads: "is Sam holding the team to account", "did the PO own the directive", "leadership review",
  "who owned this failure".
metadata:
  version: "0.1.0"
---

# Leadership accountability assessment

Load `assurance-charter` first. Leaders are assessed on outcomes they own, not on activity.

For each leader (Coordinator, Product Owner, engineering lead, design lead, QA lead, Agent Resources):
1. **Ownership map**: what the sponsor and `AGENTS.md` make them own (cite). Directives that name joint owners are
   owned by each.
2. **Did they act?** Within a reasonable time of each directive or incident: plan, assignment, follow-up, and a
   closed loop to the sponsor. Evidence: their transcript, board activity rows, PR and issue trail.
3. **Did they verify?** Leaders who report "done" are checked against artefacts. A leader relaying an agent's claim
   without checking it is a finding when the claim was wrong.
4. **Escalation quality**: escalations to the sponsor that were real blockers versus ones the team could resolve;
   restated rules; plans sent back for approval when progress was possible.
5. **Candour**: did reports to the sponsor disclose failures, limits and unsupported items, or round them up?
6. **Accountability for others**: did they detect and correct non-compliance in their area before the sponsor did?

Rate each area: Accountable / Partly / Not accountable / Not assessable, with evidence refs. Raise findings for
"Not accountable". A leader cannot be rated Accountable on a directive whose critical requirement is unmet.
Output: `20-working-papers/<engagement>/leadership.md`.
