# Records tree

Root: `/mnt/project-files/oia/` in the Office of Independent Assurance project (override with `OIA_ROOT`).
Created by `oia.py init`. Nothing here is written by the team.

| Folder | Holds | Rules |
|---|---|---|
| `00-mandate/` | Sponsor brief (verbatim), charter version, strategic directives register | New versions are new files |
| `01-agent-registry/` | Roster (name, role, session id, thread id, model), definition snapshots, capability inventories | Dated files |
| `10-historical-evidence/<UTC stamp>-<kind>/` | Frozen copies of pre-existing evidence with `provenance.json` and `MANIFEST.json` | Immutable (read-only files, hook guard, ledger hash) |
| `20-working-papers/<engagement>/` | Method, samples, test steps, notes, evidence index | One folder per engagement id |
| `30-agent-assessments/<agent>/` | Competency assessments with rubric scores and evidence | One file per assessment |
| `40-demonstrations/<id>/` | Practical demonstration briefs, outputs, observations | Assessment-generated |
| `50-challenges/sealed/` | Challenge plans written before launch (hash recorded) | Sealed: never edited after launch |
| `50-challenges/evidence/` | What the team did in response | Assessment-generated |
| `60-maturity/` | Maturity assessments | Dated |
| `70-findings/findings.jsonl` | Findings register and corrective actions (append-only events) | Only via `oia.py finding` |
| `80-reports/` | Reports issued to the sponsor | Never rewritten; new version = new file |
| `90-follow-up/` | Corrective action verification records | Cite finding ids |
| `ledger/evidence-ledger.jsonl` | Hash-chained log of every capture, record, lock and finding event | Append-only via `oia.py` |
| `ops/locks/` | One live lock at a time | `oia.py lock` |
| `setup/` | Bootstrap, acceptance tests, access assessment | |

Engagement ids: `BL-YYYYMMDD` baseline, `WK-YYYY-Www` weekly, `MM-YYYY-MM` monthly maturity, `CH-YYYYMMDD-n`
challenge, `FU-YYYYMMDD` follow-up, `AU-YYYYMMDD-<topic>` targeted audit, `CO-YYYYMMDD-<agent>` competency.
Finding ids: `F-<engagement>-<nn>`. Corrective actions: `CA-<finding id>`.
