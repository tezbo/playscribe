# Decision note: superpowers plugin alongside repo skills

Short form. 2026-11-09 / Gabrielle (asked by the coordinator) / no card, SKILLS.md change.

1. **Why.** Terry installed obra/superpowers v7.0.2 at user scope on his Mac; the coordinator asked where repo skills live, whether names collide, and whether the hook's token cost fits token discipline.
3. **Value and worth.** Read from the plugin source: the SessionStart hook (startup, clear, compact) injects `skills/using-superpowers/SKILL.md`, 3,192 chars (about 800 tokens) plus about 1 to 2k tokens of skill descriptions; within token discipline. Worth = debugging and verification habits we already want (learnings 25, 41) at a cost of one precedence line. Risk is behavioural: four of its skills overlap ours and two push subagent workflows.
4. **Alternatives.** Disable for this repo (`enabledPlugins` in `.claude/settings.json`): no cost, but loses the useful three. Keep unscoped: free, but `finishing-a-development-branch` could merge without Quinn/Iris sign-off.
5. **Decision.** Kept, scoped: a precedence line in SKILLS.md (Playscribe skill wins on overlap; subagent skills only when Terry asks; merges via review-merge-handoff). Revisit if a PR cites a superpowers skill where a repo skill applied.
6. **Learning.** Measure a plugin's cost from its hook source before judging it; then scope by precedence, not by disabling.
