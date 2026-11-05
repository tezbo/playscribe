#!/usr/bin/env python3
"""Put a fixed 0.5.0 gate bug back, or restore it. `mutants.py <toolbar|deck> <apply|restore>`.
Each mutant is one exact-text replacement, so a refactor that moves the code makes it fail loudly, not silently."""
import shutil, sys

MUTANTS = {
    # 551d8ce: a second trailing item was dropped by iOS (Settings missing in every non-Tabletop pose).
    "toolbar": ("Playscribe/UI/LibraryView.swift", '''            ToolbarItem(placement: .topBarTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
                    .disabled(model.addSheetOpen)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("settingsButton")
                    .disabled(model.settingsOpen)
            }''', '''            ToolbarItemGroup(placement: .topBarPinnedTrailing) {
                Button { model.addSheetOpen = true } label: { Label("Add game", systemImage: "plus") }
                    .disabled(model.addSheetOpen)
                Button { model.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("settingsButton")
                    .disabled(model.settingsOpen)
            }'''),
    # 94b17c7: the stacked deck had no bounded height (835 x 727 pt in Open, screen-tall in Closed portrait).
    "deck": ("Playscribe/UI/LatestUpdatesDeck.swift", '''            GeometryReader { g in
                deck(cardWidth: Self.cardWidth(in: g.size.width, perScreen: perScreen), artHeight: stackedArtHeight)
            }
            .frame(height: stackedArtHeight + (cards.count > 1 ? Self.pageEdgeHeight : 0))''',
             '''            deck(cardWidth: nil, artHeight: nil, scrollHeight: nil)'''),
}

name, action = sys.argv[1], sys.argv[2]
path, good, bad = MUTANTS[name]
if action == "apply":
    src = open(path).read()
    if good not in src:
        sys.exit(f"mutant {name}: the fixed code is not where it was; update tools/qa/mutants.py")
    shutil.copy(path, path + ".orig")
    open(path, "w").write(src.replace(good, bad, 1))
else:
    shutil.move(path + ".orig", path)
