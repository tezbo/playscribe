---
name: playscribe-code-review
description: Use when reviewing or self-reviewing a Playscribe diff or PR (Swift, backend, workflows, relay). Playscribe rules first, then correctness, security and performance. Adapted in structure from the general engineering code-review skill; the checklist text is original.
---

# Playscribe code review

Check in this order, report only real findings with file:line:
1. **Repo rules** (CLAUDE.md): tappable under the fold in Tabletop; anything intersecting `.division`; pose or device checks instead of container/reserved regions; source names, URLs or credits in UI; a PC version shown as PS5; navigation container inside an `ArrangementView`.
2. **Workflows/relay:** can a failure email Terry (no `|| true`, no `exit 0`)? Inline `${{ }}` injection? Permissions minimal? Secrets only where a workflow binds them? KV reads bounded?
3. **Correctness:** edge cases, empty states (no game opens blank), error paths.
4. **Layout:** run `ax3-layout-check` for every text-bearing view.
5. **Tests:** cites acceptance IDs; new behaviour has a test.
6. **Privacy:** no real email, no QA route names in tester notes.
For general technique use `engineering:code-review`; this file adds the Playscribe layer.
