# prelaunch-not-ps5 (r051-prelaunch-gate, #248)
- Goal: no false "On PS5" on patches that predate the game's PS5 release (Valheim 2021 showed On PS5).
- Still needed? Yes: the data-trust rule ("On PS5" = PS5 row live and official, CLAUDE.md).
- Alternatives: (1) hide pre-launch patches: rejected, it would hide real updates whenever a PS5 row is missing; (2) do nothing: rejected, breaks the rule.
- Decision (Nadia, 7 Nov): a release with no PS5 row is `.pending`, kept in history, never unread or alerted. Terry's "Steam is source of truth" still holds after PS5 launch, because the backend writes the PS5 row then.
- Risk: checked by reading code and unit tests, not a feed run. Gate: Priya's feed check (post-launch Steam patches with no PS5 row must be 0) before the 0.5.2 TestFlight build.
