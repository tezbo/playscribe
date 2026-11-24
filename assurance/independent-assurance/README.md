# independent-assurance (Cowork plugin)

Gabrielle's independent assurance operating mode for the Playscribe agentic team. In this mode Gabrielle heads the
Office of Independent Assurance (OIA) and reports directly to the sponsor, Terry, not through the Coordinator or
Product Owner. The plugin gives her the method (skills), the commands, specialist corroborating agents, a records
tool with integrity checks, and a guard on the records.

This folder is outside `.claude/skills/`, so it does not load into the team's sessions. It changes nothing in the app,
CI or TestFlight.

## Install

- Cowork / claude.ai: zip this folder (`zip -r independent-assurance.plugin . -x '*.DS_Store'`) and upload it as a
  custom plugin, or accept the `.plugin` file shared in the OIA project thread. Enable it for the OIA project's work.
- Claude Code: `claude --plugin-dir assurance/independent-assurance` (local test), or add this repo as a plugin
  marketplace later.
- Validate: `claude plugin validate assurance/independent-assurance`.

## Operational guide

| When | Run | What happens |
|---|---|---|
| Once, after install | `/independent-assurance:bootstrap` | Records tree, mandate, registry, first snapshots, health (done 24 Nov 2026) |
| After the sponsor has read the limitations | `/independent-assurance:baseline` | First full assessment; findings and maturity baseline; report to Terry |
| Mondays 18:43 Sydney (scheduled) | `/independent-assurance:audit weekly` | Weekly assurance review |
| 3rd of each month 19:17 (scheduled) | `/independent-assurance:maturity` | Monthly maturity assessment |
| Thursdays 18:29 (scheduled) | `/independent-assurance:follow-up` | Corrective action verification; silent when nothing is due |
| 17th of each month 19:11 (scheduled, paused until baseline) | `/independent-assurance:challenge design` | Designs and seals a challenge, asks Terry to approve the launch |
| Any time | `/independent-assurance:competency <agent> [--demo]` | One agent, with a live demonstration if asked |
| Any time | `/independent-assurance:audit <topic>` | Targeted audit |
| Any time | `/independent-assurance:report status` | Open findings, corrective actions, next runs |
| Any time | `/independent-assurance:health --boundaries` | Environment and access-boundary checks |

Every command loads `assurance-charter` first. Its table in each command's SKILL.md gives inputs, outputs,
permissions, evidence requirements and completion criteria.

## Contents

- `skills/assurance-charter/`: mandate, principles, evidence standard, rating scales, sources, engagement routes,
  independence assessment; `scripts/oia.py` (records tool: init, snapshot, record, ledger, verify, lock, finding,
  health).
- Method skills: directive-compliance, evidence-collection, evidence-integrity, agent-competency,
  leadership-accountability, cloud-ios-testing-assurance, multidisciplinary-qa, behavioural-challenge,
  organisational-maturity, root-cause-analysis, corrective-actions, sponsor-reporting.
- Commands (skills): bootstrap, baseline, audit, competency, challenge, maturity, follow-up, report, health.
- Agents: gabrielle-assurance-lead, evidence-provenance-auditor, ios-testing-assessor, product-quality-assessor,
  independent-second-marker, root-cause-analyst.
- `hooks/`: PreToolUse guard that blocks edits to snapshots, the ledger, the findings register and issued reports.
- `project/project-instructions.md`: text for the OIA project's instructions.
- `scheduled-tasks/schedules.json`: the operating rhythm as configured.

## Records

Kept in the OIA project's files (`/mnt/project-files/oia/`), not in this repo, so the team's sessions cannot see
them. Layout and rules: `skills/assurance-charter/references/records.md`.

## Limits

Read `skills/assurance-charter/references/independence.md`. The main ones: all agents, OIA included, run on the
sponsor's account, so there is no read-only credential; separation of records is by project boundary; the ledger is
tamper-evident only once its head hash is quoted in a sponsor report.
