# swiftui-skill-packs

Short form. 2026-11-12 / Gabrielle / asked by Terry ("look into SwiftUI / Xcode skill packs"). Skill: decision-review.

1. Why. Pain points: AX5 and Duo layout misses reach the Mac (learnings 13, 14, 33, 34), and logic tests are needed first for the 3-day builds (Nadia's plan).
3. Value and worth. Three free MIT skills, descriptions only in context until used; read in full before vendoring (no commands, no network calls). `swiftui-pro` names iPhone Duo and size-class layout, `swiftui-accessibility-auditor` checks Dynamic Type/VoiceOver from code, `swift-testing-pro` fits the 19 test files that `import Testing`. Worth = fewer Mac rounds caught before a push. Not measured yet.
4. Alternatives. Install by plugin marketplace (npx or /plugin): skipped, a vendored copy keeps licence and review in the repo and works for cloud agents with no Node. Skipped packs: dpearson2699/swift-ios-skills (PolyForm Perimeter licence, not a plain open licence), rshankras (app generators, not review), AvdLee swiftui-expert-skill (MIT, overlaps swiftui-pro; keep as a swap if swiftui-pro disappoints), XcodeBuildMCP and Maestro (the screen-testing thread skipped them), snapshot libraries (that thread owns pick 1).
5. Decision. Do it: vendor the three. Measure: count PRs citing "Skill: swiftui-pro" and AX5/Duo defects found in review per PR; scrap a skill if unused in the next 3 trains.
6. Learning. Read a third-party skill in full and check its licence before vendoring; prefer a vendored copy over an installer when agents have no Node.
