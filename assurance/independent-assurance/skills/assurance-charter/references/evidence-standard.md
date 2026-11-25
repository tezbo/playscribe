# Evidence standard

## Classes

| Class | Meaning | Where |
|---|---|---|
| historical | Existed before the assessment began (commits, PRs, CI runs, transcripts, board rows, docs, project files) | `10-historical-evidence/<snapshot>/` |
| assessment-generated | Created by OIA during an assessment (interview replies, demonstration outputs, challenge responses, re-runs) | `20-…` to `90-…` via `oia.py record` |
| assertion | A statement by an agent about its own or its team's work, with no artefact | Quoted in working papers, never relied on alone |

An assessment-generated item produced by a team agent in response to OIA (for example a demonstration) is still
assessment-generated: it shows what the agent can do when asked, not what it did unprompted.

## Provenance fields (every snapshot and record)

`source` (system), `source_ref` (SHA, run id, session id + event uuid, cmsg id, URL + doc id), `captured_at` (UTC),
`capture_method`, `class`, SHA-256 of every file, ledger sequence. `oia.py` writes all of these.

## Strength of evidence (strongest first)

1. Re-performed by OIA or observed live (for example: OIA re-ran a workflow, opened the still, read the log line).
2. System-of-record artefact (git object, CI run log, session transcript event, artifact database row).
3. Team document that is versioned (repo file at a SHA).
4. Unversioned team document (project file, message text).
5. Agent assertion.

A PASS needs level 1 or 2. Levels 3 to 5 can support a finding of absence ("no evidence that …") but not a pass.

## Sampling

State the population and the sample. Default: the whole population when it is under 30 items; otherwise 25 items
chosen at random with the seed recorded, plus every item the sponsor named. Never sample only items an agent
pointed you to.

## Chain of custody

1. Capture to a scratch folder.
2. Redact secrets; record what was redacted (pattern, count), never the value.
3. `oia.py snapshot` (historical) or `oia.py record` (assessment-generated).
4. Cite the snapshot id and ledger sequence in the working paper.
5. At report time run `oia.py verify` and put the ledger head hash and verdict in the report (anchoring).

## Traceability test

Pick any sentence in a report: it must lead to a finding id, the finding to a working paper, the working paper to
snapshot or record ids, and those to original system references. If any link breaks, the sentence is withdrawn.
