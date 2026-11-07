# Decision note: should Precheck run the unit tests?

Date / owner / card: 2026-11-07, Theo, Gabrielle's risk 8.

1. **Why.** Precheck is the cloud engineers' compiler (no Xcode there). Gabrielle asked whether it should also run the unit tests, so a failing test shows before a PR exists.
2. **Goal still needed.** Yes: fast, quiet, pre-PR feedback keeps broken heads out of PRs. Running the tests before a PR is the only part in question.
3. **Value vs cost (measured on #348, 7 Nov).** Precheck compile job: 1 m 48 s (build-for-testing of both schemes). The `unit` job in ios.yml: 8 m 34 s of build and test, plus about 1 m 40 s for `ui-build` (ios.yml has since merged the two into one job). Adding the tests to Precheck would take it from about 2 minutes to about 10 on every push to claude/**, and agents push several times an hour, so on the shared macOS runner it would roughly quintuple the load. ios.yml runs the same tests as soon as a PR exists, so each head would run them twice. A test failure also needs a PR-level fix anyway. Guess: most pushes are compile-only fixes, so most of the extra minutes would be wasted.
4. **Alternatives.** (a) Stay compile-only: fastest, tests come with the PR. (b) Run tests on every push: earliest signal, about 5x runner cost, duplicates ios.yml. (c) Compile-only by default, tests on `workflow_dispatch` or when a commit message has `[tests]`: opt-in, small change. (d) Do nothing and rely on ios.yml.
5. **Decision.** Stay compile-only (a/d). If an engineer wants early tests on a risky change, run the iOS workflow by hand on the branch (it has `workflow_dispatch`), or open a draft PR; ios.yml runs on drafts too. Revisit if more than 1 in 4 PRs fail unit tests that Precheck could have caught (count from the last 20 PRs).
6. **Learning.** Measure the minutes before widening a check that runs on every push; the cheap gate stays cheap, and the full run waits for the PR.
