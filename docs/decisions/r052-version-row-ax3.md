# r052-version-row-ax3

Short form. Goal: a readable version at the gate size (AX5); "01.001.000" never breaks after a dot or clips (Quinn, Closed portrait AX5).
Smaller alternative: a word joiner only (no layout change). Larger: rebuild the row (rejected, Theo's tip). Do nothing: not allowed, it is a visible bug.
Decision: both. At accessibility sizes the date sits over the version; the version is one token (a word joiner after each dot), one line, shrinking to 60% before it would clip. Standard sizes keep one row. VoiceOver reads the plain version. A PC version is never shown here; the row only ever shows a PS5 version. Test: UnbreakableVersionTests. Stills: Closed portrait, Open portrait and Book at AX5.
Weighed in: Quinn (found it), Iris to sign the stills.
Learning: for a token that must not break, join it; do not hope it fits.
