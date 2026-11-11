# r053-sort-recent-updated

Short form. Goal: sorted by "Recently updated on PS5", the top of the Library never shows games that have no update (Terry, 8 Nov: "all the titles at the top still say no updates"; v0.5.3 blocker).
Cause (read from the code and Terry's two screenshots): the sort key was the newest On PS5 update's date, falling back to the date the game was ADDED when it has none. Terry's Library has 47 games and none has an update, so every row used the fallback and the order was the order they were added: Oct 2025, Mar 2025, Aug 2025, May 2025, Mar 2025, 31 Dec, 10 Nov. Ninja Gaiden 4 ("No updates yet", checked 7 Nov) came first only because it was added last. Not reproduced on a device.
Smaller alternative: name order for games with no update (rejected: it hides which are newly out). Do nothing: not allowed.
Decision: three groups. Games with an On PS5 update first (newest update first); then games with none that are already out (newest release first, the date their tile pill shows); then games not out yet (soonest first) and undated ones last. Ties by name. One pure function (`AppModel.updatedFirst`), tested in RecentlyUpdatedSortTests. Same B-3 sort name, no UI change. This touches only AppModel.swift, not LibraryView (the tile owner's #424).
Not fixed here: "No updates yet" for a game that is out may be a feed gap (no patch notes found), a separate data question.
Weighed in: Terry reported it; Iris and Quinn to sign the Library stills.
Learning: a sort fallback that borrows an unrelated date orders the rows that lack the key by an accident of history; use the date the row itself shows.
