# Access and independence assessment

What separates OIA from the team, and whether the platform enforces it. Re-test with
`/independent-assurance:health` and record the results in `setup/`.

| Control | Mechanism | Enforced by platform? |
|---|---|---|
| Separate instructions | OIA project's own project instructions and this plugin; the team's coordinator instructions live in the team project | **Yes**, project instructions are per project. Plugin skills load wherever the plugin is enabled |
| Separate memory | Project memory is per project | **Yes** (per project). Anyone in the OIA project, and Terry, can edit it |
| Separate records | OIA records in the OIA project's files; the team's sessions mount their own project's files | **Yes, by project boundary**: a team thread cannot see the OIA project's files. Not by per-agent permission inside the OIA project |
| Coordinator has no control of papers or reports | The Coordinator is the team project's ambient session; it has no thread or file access in the OIA project | **Yes** for project files and threads. **No** for shared account tools: every session on Terry's account can read other sessions' transcripts (`list_events`) and could message the OIA session |
| Reports go straight to the sponsor | OIA threads post to Terry; scheduled runs notify by push | **Yes** inside the OIA project. The OIA project's own coordinator relays thread results to Terry's project chat; it is a different Claude from the team Coordinator |
| Read-only access to team evidence | Instructions, records guard hook | **No.** OIA uses Terry's account and GitHub identity, which can write to the repo and board. There is no read-only credential |
| Tamper evidence on records | SHA-256 manifests, read-only file modes, hash-chained ledger, guard hook | **Partly.** Detects edits made without recomputing the chain. Someone with file access could rebuild the whole chain; anchoring the head hash in each sponsor report makes that detectable |
| Challenge secrecy | Sealed plans in the OIA project only; the plugin's method is generic | **Partly.** Plugin source in the product repo is visible to the team; specific challenge plans are not |
| No overlapping runs | `oia.py lock` (one live lock) | **Procedural** (honoured by OIA sessions, not by the scheduler) |
| Spend control | No paid services, no purchase tools; scheduled tasks bounded | **Procedural**, plus platform plan limits |

Conflict of interest: Gabrielle assesses the Agent Resources function she also runs. Mitigation: the
`independent-second-marker` agent re-marks every judgement about Agent Resources from the evidence alone; both
marks are reported; Terry is told where they differ.

Never describe a procedural control as an access control in a report.
