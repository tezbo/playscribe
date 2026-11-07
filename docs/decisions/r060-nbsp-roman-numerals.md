# r060-nbsp-roman-numerals

Short form. Goal: "Deliverance II" never leaves "II ✓" alone on a line (Open portrait, Iris).
Smaller alternative: do nothing (a stranded numeral reads as a different title). Larger: a general no-break rule for the last two words of every title (rejected: it would also glue ordinary words and make long names wrap worse).
Decision: a no-break space before a trailing Roman numeral up to XX, after at least one other word, on the game page title (standard and accessibility layouts). VoiceOver still reads the plain name. Test in RomanNumeralGlueTests.
Weighed in: Iris (raised it); Nadia via the card.
Learning: tie only what reads as one name (word plus numeral), not the last two words of everything.
