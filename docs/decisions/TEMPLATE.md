# Decision note: <short title>

Required for every board card that adds, changes or removes a feature (Terry, 2026-11-06). Max 15 lines. Put the file at
`docs/decisions/<card-id>.md` and link it in the card's `links`. A card without a note cannot move to `backlog` or `doing`.

**Short form (under 1 h of work, or a bug or chore whose fix involves a choice):** answer 1, 3 and 5 in one line each. A bug fix with no choice in it, and a release, need no note. Idea cards may sit without one, but the note is due before the card leaves `review`. Terry said ALL decisions, so when in doubt write the short form.

Date / owner / card:

1. **Why we did it (or are proposing it).** What goal did it serve, who asked, which card or PR?
2. **Do we still need that goal, and why?** Test it against the north star: an award-worthy "made for iPhone Duo" app that keeps PS5 players in the know.
3. **Value, and is it worth the cost?** Say what "worth" means here (north-star fit, player impact, cost in build, QA, complexity and upkeep). Evidence over opinion; mark guesses as guesses.
4. **Another way to reach the same goal?** List at least two alternatives, each with one line of pros and cons.
5. **Decision.** Do it, change it, or scrap it. Scrapping is a valid result; do not be afraid to scrap.
6. **Learning.** One line for `docs/learnings.md` (Gabrielle logs it), whatever the outcome.

## Outcomes
- **Kept:** the goal still stands and this is the best way to reach it. Example: the Latest updates deck stays because it answers "what changed since I looked" in one glance.
- **Changed:** the goal stands but another way is better. Example: Also new becomes a "+N more updates" chip instead of a second panel.
- **Scrapped:** the goal is gone, or the value is not worth the cost. Say so plainly, keep the note, and log the learning. A scrapped idea is a good result, not a failure.
