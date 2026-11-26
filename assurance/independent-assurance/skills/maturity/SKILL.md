---
name: maturity
description: >
  Run a deep maturity and performance assessment, monthly only where justified or when the sponsor asks (the weekly review covers routine monitoring). Use for "/independent-assurance:maturity",
  "monthly maturity assessment", "how mature is the team now".
argument-hint: "[YYYY-MM]"
disable-model-invocation: true
metadata:
  version: "0.2.0"
---

# /independent-assurance:maturity

Load `assurance-charter` and `organisational-maturity`.

| Contract | |
|---|---|
| Inputs | Month (default: the previous calendar month); prior maturity assessment; weekly papers; findings register |
| Outputs | `60-maturity/MM-<YYYY-MM>.md`; findings; report |
| Permissions | Read-only |
| Evidence | Three or more cited items per dimension; sponsor-intervention index with examples |
| Done when | All dimensions scored or not assessable with reason; caps applied; trend shown; second marker on Organisational learning; report delivered; lock released |
| Budget | One session; reuse weekly snapshots, collect fresh only where a dimension has fewer than three items |

Guard: no baseline yet → stop and tell the sponsor. Lock name `monthly`; if `weekly` holds the lock, stop and say so.
Covers: maturity dimensions, skills development, multidisciplinary participation, independent verification, and
reliance on sponsor intervention.
