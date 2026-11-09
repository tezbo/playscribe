# r053-search-text-persists-relaunch

Decided by Nadia and Iris (v0.5.3 blocker). On a cold launch the Library search starts empty and shows every game; the text typed in the last launch is not restored. A fold or unfold keeps the typed text (the model stays alive). The selected game, scroll anchors and live filters (Owned, Wishlist, sort) are restored as before.

Change: `AppModel.init` clears `data.nav.query` after it decodes the saved state. Nothing else about navigation persistence moves, and the Library views are untouched, so this does not collide with #424.

Tests (`SearchTextColdLaunchTests`): a saved model with a typed query reopens with an empty search, the same selected game, filter and scroll anchor, and with the filter back on All it lists every game; a model keeps its typed text through a pose-change tick. No stills (nothing visual changes beyond an empty field).

Learning: persist state by what it means to the person, not by what is easy to encode; a half-typed search is a task, not a place.
