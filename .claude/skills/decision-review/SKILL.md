---
name: decision-review
description: Use before deciding to add, change, remove or reverse anything (a feature, card, workflow, rule, PR scope), and again before closing a decision. Applies Terry's critical-thought rule through docs/decisions/TEMPLATE.md and logs the outcome in docs/learnings.md. For every agent and the coordinator.
---

# Decision review (Terry, 2026-11-07 10:02 AEDT)

Terry's standing rule: every decision gets critical thought, the way the "Also new" card did. Say "Skill: decision-review" in your reply so use is visible.

## When
- A card adds, changes or removes a feature (note required; short form under 1 h of work, or a bug or chore with a choice in it).
- You are about to scrap, revert or reverse something already shipped or agreed.
- You are about to pick one of several routes, or accept a scope increase.
- Skip: a bug fix with no choice in it, and a release.

## The six questions (same numbers as `docs/decisions/TEMPLATE.md`)
1. **Why** did we do it, or propose it? Goal, who asked, which card or PR.
2. **Still needed?** Test the goal against the north star (an award-worthy "made for iPhone Duo" app that keeps PS5 players in the know). If the goal is gone, stop here and scrap.
3. **Worth it?** Say what "worth" means this time: north-star fit, player impact, cost in build, QA, complexity and upkeep. Evidence over opinion; label guesses as guesses. Cost in time comes from `playscribe-estimate`, never invented.
4. **Another way?** At least two alternatives, one line of pros and cons each. Include "do nothing" and "do a smaller version".
5. **Decide:** keep, change or scrap. Scrapping is a good result, not a failure.
6. **Learning:** one line, whatever the outcome.

## Steps
1. Copy `docs/decisions/TEMPLATE.md` to `docs/decisions/<card-id>.md` (max 15 lines). Link it in the card's `links`.
2. Product (Nadia) and design (Iris) both weigh in where the change touches the product or the screens. Cite names and times.
3. Stress-test the pick in two lines: "What would make this fail?" (pre-mortem) and "What is the best case for the option we rejected?" (steelman).
4. Record the decision on the card and tell Gabrielle the one-line learning, with the link. She appends it to `docs/learnings.md` each cycle. A scrapped idea is logged the same as a kept one.

## Coordinator checklist (keep in project memory, apply to every decision)
1. Name the goal and who asked.
2. Is the goal still needed, tested against the north star?
3. What does it cost and what does it deliver; is that worth it, and what does "worth" mean here?
4. Two alternatives, including a smaller version and doing nothing.
5. Pick one; scrapping is allowed.
6. Product and design weighed in, with names.
7. Note filed in `docs/decisions/`, card linked, learning sent to Gabrielle.
Do not start the work, or let a thread start it, before steps 1 to 5 have an answer.

## Do not
- Ask Terry to make a call the team can make; bring the recommendation.
- Run a multi-agent debate for a small decision. Token discipline applies; use the short form.
