#!/usr/bin/env python3
"""Builds the app's bundled fixture data (Playscribe/Resources/Data) from the web prototype's sources.

Usage: python3 tools/build_fixtures.py <prototype src/data dir> <book.json from book.ts>
       python3 tools/build_fixtures.py --retag    # re-apply the platform rules to releases.json only

Release records follow docs/ps5-patch-data.md. Sources stay in the data and out of the UI.
Note items are tagged by platform with the backend's rules (backend/src/ingest/platform-terms.json),
and no headline, summary, key change or push line may carry a PC-only line (FrameGen, AMD, Steam
Controller…): those fields show on PS5 pages and in pushes.
"""
import json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "Playscribe/Resources/Data"
TERMS = json.loads((root.parent / "backend/src/ingest/platform-terms.json").read_text())
any_of = lambda pats: re.compile("|".join(f"(?:{p})" for p in pats), re.I)
named = {k: any_of(v) for k, v in TERMS.items() if not k.startswith("$")}
named["pcFeature"], named["pc"] = named["pc"], any_of(TERMS["pcNames"] + TERMS["pc"])
PC_PREFIX = re.compile(r"^\s*(\[PC\]|PC:|\(PC\))|\bPC only\b|\(PC\)", re.I)

def platforms_for(text):
    """Mirror of platformsFor in backend/src/ingest/notes.ts."""
    p = []
    if named["ps5"].search(text): p.append("ps5")
    if PC_PREFIX.search(text) or (named["pc"].search(text) and not named["consoles"].search(text)): p.append("pc")
    if named["xboxSeries"].search(text): p.append("xboxSeries")
    return p or None

def tag(releases):
    for r in releases:
        for s in r["notes"]:
            section = platforms_for(s["title"])
            section = section if section and len(section) == 1 else None
            for i in s["items"]:
                i.pop("platforms", None)
                p = section or platforms_for(i["text"])
                if p: i["platforms"] = p
        lines = [r.get("headline"), r.get("summary"), r.get("pushLine"), *(r.get("keyChanges") or [])]
        bad = [l for l in lines if l and named["pcFeature"].search(l) and platforms_for(l) == ["pc"]]
        if bad: sys.exit(f"{r['id']}: PC-only line in a field PS5 pages show: {bad}")
    return releases

if sys.argv[1:] == ["--retag"]:
    path = out / "releases.json"
    releases = tag(json.loads(path.read_text()))
    path.write_text(json.dumps(releases, ensure_ascii=False, indent=1) + "\n")
    print("retagged", len(releases), "releases")
    sys.exit()

src = pathlib.Path(sys.argv[1])
book_json = pathlib.Path(sys.argv[2])
CHECKED = "2026-10-23T00:00:00Z"

def field(value, verification, source):
    return {"value": value, "verification": verification, "sourceId": source, "checkedAt": CHECKED}

def day(d):
    return f"{d}T12:00:00Z"

def plat(platform, status, verification, live=None, source=None, version=None, size=None, bundles=()):
    p = {"platform": platform, "status": status, "verification": verification, "bundles": list(bundles)}
    if live: p["liveAt"] = field(day(live), verification, source)
    if version: p["version"] = version
    if size: p["sizeBytes"] = size
    return p

# ---------------------------------------------------------------- Dawnwalker 1.1 (official post, read 23 Oct 2026)
official = json.loads((src / "dawnwalker-update-1-1.official.json").read_text())
SPOILER_SECTIONS = {"Quests", "Narrative"}
mentions_quest = re.compile(r'quest|event|cinematic|cutscene|“|"', re.I)
def items(texts, spoil=lambda t: False):
    return [{"text": t, "ps5ProOnly": False, **({"spoiler": True} if spoil(t) else {})} for t in texts]
sections = [
    {"title": "New features", "items": items(official["newFeatures"])},
    {"title": "Highlights", "items": items(official["highlights"])},
    *[{"title": s["title"], "items": items(s["items"], lambda t, s=s: s["title"] in SPOILER_SECTIONS or bool(mentions_quest.search(t)))} for s in official["sections"]],
    {"title": "Known issues", "items": items(official["knownIssues"])},
]
listed = sum(len(s["items"]) for s in official["sections"])

releases = [
    {
        "id": "dawnwalker@1.1", "gameId": "dawnwalker", "displayName": "Update 1.1",
        "kind": "major", "kindBasis": "studio", "announcedAt": day("2026-10-22"),
        "notes": sections, "sourceIds": ["dawnwalker-news", "pushsquare"],
        "platforms": [
            plat("ps5", "live", "official", "2026-10-22", "dawnwalker-news",
                 size=field(13_000_000_000, "reported", "pushsquare")),
            plat("pc", "live", "official", "2026-10-22", "dawnwalker-news"),
            plat("xboxSeries", "live", "official", "2026-10-22", "dawnwalker-news"),
        ],
        "headline": "Respec with Draught of Mind Rebirth, a new Story mode and larger subtitles",
        "summary": "The first big update is about refinement rather than new story. You can now forget your Swordmastery, Witchcraft and Vampirism abilities and spend that time on a different build. Difficulty is more flexible: the old Story setting is now Forgiving, with a new Story mode below it that adds combat assistance. Subtitles can be larger and cover every line of dialogue, targeting and lock-on are improved, and Shadowstep and Planeshift respond better.",
        "keyChanges": [
            "Draught of Mind Rebirth: reset Swordmastery, Witchcraft and Vampirism abilities",
            "New Story mode with extra combat assist; the old Story setting is now Forgiving",
            "Larger subtitles, and subtitles for all dialogue lines",
            "Better targeting, lock-on and disengaging; more responsive Shadowstep and Planeshift",
            f"{listed} listed fixes and changes across quests, combat and stability",
        ],
        "pushLine": "respec with Draught of Mind Rebirth, and a new Story mode",
        "video": {"youtubeID": "Y7F-0CLzvXE", "label": "Update 1.1 overview", "duration": "0:52", "posted": "2026-10-22", "posterAsset": "dw-u11-video"},
    },
    {
        "id": "dawnwalker@1.0", "gameId": "dawnwalker", "displayName": "Launch",
        "kind": "major", "kindBasis": "inferred", "announcedAt": day("2026-09-03"),
        "notes": [], "sourceIds": ["shacknews"],
        "platforms": [plat(p, "live", "reported", "2026-09-03", "shacknews") for p in ("ps5", "pc", "xboxSeries")],
        "headline": "Available on PC, PlayStation 5 and Xbox Series X|S",
        "summary": "The game launched worldwide. Playscribe has not tracked any launch-window hotfixes, so this entry marks where the journal starts rather than listing changes.",
        "keyChanges": [],
    },
]

def pc_release(id, game, name, version, date, kind, headline, summary, keys, source, size=None, note=None):
    r = {
        "id": id, "gameId": game, "displayName": name, "kind": kind, "kindBasis": "studio",
        "announcedAt": day(date), "notes": [], "sourceIds": [source],
        "platforms": [plat("pc", "live", "official", date, source, version=field(version, "official", source),
                           size=field(size, "official", source) if size else None)],
        "headline": headline, "summary": summary, "keyChanges": keys,
    }
    if note: r["videoNote"] = note
    return r

releases += [
    pc_release("control-resonant@1.4.2", "control-resonant", "Hotfix 1.4.2", "1.4.2", "2026-10-08", "hotfix",
        "Fixes several quest blockers and a missing quest reward",
        "A follow-up to Game Update 1.4.0 that unblocks The House in Distress and other quests, and restores an Artifact reward for Every Dog Has Her Day.",
        ["Quest progression fixes after 1.4.0", "Missing Artifact reward restored"], "control-resonant-steam"),
    pc_release("control-resonant@1.4.1", "control-resonant", "Hotfix 1.4.1", "1.4.1", "2026-10-02", "hotfix",
        "Fixes The Park Resonant quest and dash momentum into Elevate",
        "Repairs two issues introduced by 1.4.0: a blocked quest step in The Park Resonant, and dash momentum no longer carrying into Elevate.",
        ["The Park Resonant quest can progress again", "Dash momentum carries over again"], "control-resonant-steam"),
    pc_release("control-resonant@1.4.0", "control-resonant", "Game Update 1.4.0", "1.4.0", "2026-10-01", "major",
        "New Game++ and quality-of-life fixes",
        "The first larger post-launch update adds New Game++ and a broad set of fixes and polish.",
        ["New Game++", "Quality-of-life fixes and polish"], "control-resonant-steam",
        note="No official video for this update found (searched 24 Oct 2026)."),
    pc_release("kcd2@1.5.6", "kcd2", "Patch 1.5.6", "1.5.6", "2026-06-25", "patch",
        "A Jester’s visit: a new quest and fixes",
        "Adds a short new quest that begins outside the Hangman’s Halter tavern, and Hardcore mode and control-scheme fixes.",
        ["New Jester quest", "Hardcore mode fixes"], "kcd2-steam"),
    pc_release("kcd2@1.5.5", "kcd2", "Patch 1.5.5", "1.5.5", "2026-04-20", "patch",
        "Three Crusader Kings book, a Crusader Kings III collaboration",
        "A small update that adds the book Three Crusader Kings around Trosky and Kuttenberg.",
        ["New collectible book"], "kcd2-steam"),
    pc_release("wukong@1.0.21.23831", "wukong", "Patch 1.0.21.23831", "1.0.21.23831", "2026-01-14", "patch",
        "Version 1.0.21.23831, about 2.0 GB on PC",
        "The most recent patch, out on PC so far.",
        [], "wukong-steam", size=2_000_000_000),
    pc_release("wukong@1.0.20.22023", "wukong", "Patch 1.0.20.22023", "1.0.20.22023", "2025-10-16", "patch",
        "Version 1.0.20.22023, about 5.7 GB on PC",
        "An earlier patch, out on PC so far.",
        [], "wukong-steam", size=5_700_000_000),
]
for r in releases:
    for p in r["platforms"]:
        if p.get("sizeBytes") is None: p.pop("sizeBytes", None)

# ---------------------------------------------------------------- catalogue
snap = json.loads((src / "catalog.snapshot.json").read_text())["games"]
igdb = lambda gid: (snap.get(gid, {}).get("igdb") or {}).get("id")
catalog = [
    {"id": "dawnwalker", "name": "The Blood of Dawnwalker", "developer": "Rebel Wolves", "publisher": "Bandai Namco Entertainment",
     "platforms": ["ps5", "pc", "xboxSeries"], "releaseDate": "2026-09-03", "igdbID": igdb("dawnwalker"),
     "coverAsset": "dw-cover", "heroAsset": "dw-gameart-16x9", "featureAsset": "dw-wall-1736593755", "tones": ["#b2300f", "#1a0906"], "coverage": "full",
     "chapterArt": {"updates": ["dw-update-1-1-16x9", "dw-update-1-1-2x3"], "companion": ["dw-kv-16x9", "dw-kv-9x16"],
                    "world": ["dw-wall-1736593755", "dw-wall-1736593755"], "default": ["dw-gameart-16x9", "dw-gameart-9x16"]}},
    {"id": "kcd2", "name": "Kingdom Come: Deliverance II", "developer": "Warhorse Studios", "publisher": "Deep Silver",
     "platforms": ["ps5", "pc", "xboxSeries"], "releaseDate": "2025-02-04", "igdbID": igdb("kcd2"),
     "coverAsset": "kcd2-cover", "heroAsset": "kcd2-hero", "tones": ["#6d7f99", "#1d1a16"], "coverage": "partial"},
    {"id": "control-resonant", "name": "CONTROL Resonant", "developer": "Remedy Entertainment", "publisher": "Remedy Entertainment",
     "platforms": ["ps5", "pc", "xboxSeries"], "releaseDate": "2026-09-24", "igdbID": igdb("control-resonant"),
     "coverAsset": "control-cover", "heroAsset": "control-hero", "tones": ["#8a1f1a", "#141416"], "coverage": "partial"},
    {"id": "wukong", "name": "Black Myth: Wukong", "developer": "Game Science", "publisher": "Game Science",
     "platforms": ["ps5", "pc"], "releaseDate": "2024-08-19", "igdbID": igdb("wukong"),
     "coverAsset": "wukong-cover", "heroAsset": "wukong-hero", "tones": ["#4a4238", "#0e0d0b"], "coverage": "partial"},
    {"id": "bg3", "name": "Baldur's Gate 3", "developer": "Larian Studios", "publisher": "Larian Studios",
     "platforms": ["ps5", "pc", "xboxSeries"], "releaseDate": "2023-08-03", "igdbID": igdb("bg3"),
     "coverAsset": "bg3-cover", "tones": ["#3b2a52", "#0d1020"], "coverage": "none"},
    {"id": "astro-bot", "name": "Astro Bot", "developer": "Team Asobi", "publisher": "Sony Interactive Entertainment",
     "platforms": ["ps5"], "releaseDate": "2024-09-06", "igdbID": igdb("astro-bot"), "tones": ["#1b2a4a", "#0b0d12"], "coverage": "none"},
    {"id": "yotei", "name": "Ghost of Yōtei", "developer": "Sucker Punch Productions", "publisher": "Sony Interactive Entertainment",
     "platforms": ["ps5"], "releaseDate": "2025-10-02", "igdbID": igdb("yotei"), "tones": ["#4a1b1b", "#0b0d12"], "coverage": "none"},
]
for g in catalog:
    if g["igdbID"] is None: g.pop("igdbID")
    if (snap.get(g["id"], {}).get("igdb") or {}).get("cover") and not g.get("coverAsset"):
        g["coverImageID"] = snap[g["id"]]["igdb"]["cover"]["imageId"]

def art(i, asset, title, alt, kind="artwork", href=None):
    a = {"id": i, "gameID": "dawnwalker", "kind": kind, "asset": asset, "title": title, "alt": alt}
    if href: a["href"] = href
    return a
gallery = [
    art("g-u11", "dw-update-1-1-16x9", "Update 1.1", "Update 1.1 illustration in a medieval manuscript style"),
    art("g-key", "dw-gameart-16x9", "Key art", "Coen holding a sword before a burning sun"),
    art("g-kv", "dw-kv-16x9", "Day and night", "Coen split between night and day across the valley"),
    art("g-cathedral", "dw-wall-1736593755", "Cathedral at night", "A gothic cathedral under construction, lit by moonlight"),
    art("g-moon", "dw-wall-1736595215", "Moonlit peaks", "Mountains under a bright full moon"),
    art("g-street", "dw-wall-1736593900", "Town street", "A figure walking down a narrow medieval street towards a church tower"),
    art("g-roofs", "dw-wall-1736687326", "Rooftops", "A figure crouched on a rooftop beneath a red moon"),
    art("g-village", "dw-wall-1736593958", "Village", "A quiet village with a well and bare autumn trees"),
    art("g-elder", "dw-wall-1736595126", "Portrait", "A pale, aged vampire looking out of the darkness"),
    art("g-fire", "dw-wall-1736593922", "Burning forest", "Fire spreading through a forest at dusk"),
    art("g-highland", "dw-wall-1736593984", "Highland settlement", "Stone houses on a rocky hillside"),
    art("v-launch", "yt-pNTT7lknCE0", "Launch Trailer", "Launch Trailer thumbnail", "video", "https://www.youtube.com/watch?v=pNTT7lknCE0"),
    art("v-story", "yt-Fn7aYRVyRMM", "Story Trailer", "Story Trailer thumbnail", "video", "https://www.youtube.com/watch?v=Fn7aYRVyRMM"),
    art("v-everything", "yt-_U88fNicSPg", "Everything You Need to Know", "Everything You Need to Know thumbnail", "video", "https://www.youtube.com/watch?v=_U88fNicSPg"),
    art("v-overview", "yt-1XOa0JYJv8g", "Gameplay Overview", "Gameplay Overview thumbnail", "video", "https://www.youtube.com/watch?v=1XOa0JYJv8g"),
    art("v-cinematic", "yt-te73UInH8H8", "Cinematic Trailer & Gameplay Teaser", "Cinematic Trailer thumbnail", "video", "https://www.youtube.com/watch?v=te73UInH8H8"),
]

book = json.loads(book_json.read_text())
for e in book:
    e["gameID"] = e.pop("gameId")
    e["spoiler"] = e.get("spoiler") == "story"

seed = [
    {"gameID": "dawnwalker", "status": "owned", "addedAt": "2026-09-03T09:00:00Z"},
    {"gameID": "kcd2", "status": "owned", "addedAt": "2026-02-04T09:00:00Z"},
    {"gameID": "control-resonant", "status": "owned", "addedAt": "2026-09-24T09:00:00Z"},
    {"gameID": "wukong", "status": "watching", "addedAt": "2026-05-01T09:00:00Z"},
]

def dump(name, data):
    (out / name).write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n")
dump("releases.json", tag(releases))
dump("catalog.json", {"games": catalog, "seedCollection": seed})
dump("gallery.json", gallery)
dump("book.json", book)
print("wrote", len(releases), "releases,", len(catalog), "games,", len(gallery), "gallery items,", len(book), "book entries")
