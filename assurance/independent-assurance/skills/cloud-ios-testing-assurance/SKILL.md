---
name: cloud-ios-testing-assurance
description: >
  This skill should be used to assure the team's iOS testing, especially autonomous cloud-native iPhone Duo
  testing: "is cloud Duo QA real", "check pose coverage", "assure the test pipeline", "does testing still need
  Terry's Mac", "verify TestFlight builds were tested".
metadata:
  version: "0.1.0"
---

# Cloud-native iOS testing assurance

Load `assurance-charter` first. Results use PASS / FAIL / BLOCKED / UNSUPPORTED / NOT TESTED.

1. **Inventory** at the pinned SHA: workflows under `.github/workflows/` (build, unit, UI, precheck, pose and stills
   workflows, TestFlight), test targets, QA routes, the capability register and pose procedure docs, and any
   third-party simulator services in use. For each: trigger, runner, whether it needs the sponsor's Mac or a paid
   service, and whether its failures are visible (a workflow that "always ends green" hides failure unless its
   verdict is read).
2. **Coverage matrix**: rows = Duo poses and configurations required by the directive and `docs/ux-acceptance.md`
   (Closed portrait/landscape, Book, Open, Tabletop, Open portrait, hinge angles, inner/outer display, standard and
   AX text sizes); columns = how it is tested, in the cloud or on the Mac, last run id and SHA, result. An empty cell
   is NOT TESTED, never PASS.
3. **Re-perform** a sample: open the run, read the job verdict, open the stills or logs, and check that the still
   shows the claimed display and pose (size and content), not just that a file exists. Simulated poses
   (synthetic division) are labelled as such and do not count as real-hinge coverage.
4. **Independence of verification**: for each sampled change, was a second agent the verifier, and did a different
   agent review visuals? Same-session sign-off is a finding.
5. **Release link**: for the latest TestFlight build, trace tag, SHA, the test runs on that SHA and the pose evidence.
   Distribution without that chain is "distributed, not assured".
6. **Mac dependence**: count runs in the period that needed the sponsor's Mac or his presence; compare with the
   directive.
7. **Cost**: list any paid service used, who authorised it (cmsg id), and whether usage stayed inside the approval.

Corroborate with the `ios-testing-assessor` agent. Output: `20-working-papers/<engagement>/ios-testing.md`.
