# r053-sort-recent-updated

Short form. Goal: sorted by "Recently updated on PS5", the top of the Library never shows games that have no update (Terry, 8 Nov: "all the titles at the top still say no updates"; v0.5.3 blocker).
Cause (read from the code, not reproduced on a device): the sort key was the newest On PS5 update's date, falling back to the date the game was ADDED when it has none. A game added today with no update therefore outranked a game updated last week, and its tile pill read "TBA", "Plays on PS5" or an unreleased date.
Smaller alternative: sort no-update games last by name only (rejected: a game just added is what the reader wants first among the rest). Do nothing: not allowed.
Decision: games with an On PS5 update first, newest update first; games with none after, newest added first, then by name. One pure function (`AppModel.updatedFirst`), tested in RecentlyUpdatedSortTests. Same B-3 sort name; no UI change. Library files are also in #424 (tile owner): this touches only AppModel.swift, not LibraryView.
Weighed in: Terry reported it; Iris and Quinn to sign the Library stills.
Learning: a sort fallback that borrows an unrelated date puts the rows that lack the key at the top.
