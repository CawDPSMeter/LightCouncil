# Changelog

## 0.16.1
- Fairness: an item counts as owned in a gear set if the loot history shows the player received it (nobody can look needier by reporting false data).
- Other players' sets show when they were last updated; sets older than 14 days are marked “(old)” in the council window.
- Performance: “do I have this item?” is cached; set changes are only broadcast when something actually changed.
- Version requests (`/lc check`) are only answered from your own group, at most every 30 seconds.
- Long sets are no longer cut off in the middle of an item; “Rename” shows the current name.

## 0.16.0
- New: **gear sets**. Raiders build one or more named sets (e.g. one per biome) and put the items in their own priority order. The addon detects what you already have (equipped, bags, bank).
- The active set is shared with everyone; “Gear sets → All sets” shows everyone's progress.
- The council vote window has a new “Set” column showing the item's place in the player's priority; tooltips show the whole set.
- “My reservation”: “+ Set” on every item; optional “Take from gear set” (the council turns this on under “Raid days” – pugs without a set reserve as usual).
- Item tooltips and the loot window show who has the item in their set and its place in your own set.

## 0.15.0
- Deleted loot history entries are synced and no longer come back.
- Version check: notice about newer versions; `/lc check` lists all versions in the raid.
- Item tooltips show council item, priority and reservers (`/lc tooltip` to turn off).
- The language menu closes when clicking elsewhere.
- The version number lives only in the `.toc`.
- README, CHANGELOG and a translation check script; unused images removed.
- `UI_Main.lua` split into several files.

## 0.14.1
- Security: raiders can no longer raise the reservation round (previously anyone could delete all reservations).
- Votes and the raider window are accepted only from the raid leader or master looter; a loot list can only be changed by its creator.
- Sync requests throttled, raid keys limited, received texts sanitized.

## 0.14.0
- Multilingual: German, English, French, Spanish, Russian; language selection in the settings and via `/lc lang`.

## 0.13.0
- Attendance is synced between all council members.
- The first council list is only accepted from the raid lead, guild leadership or two council members; `/lc councilreset`.
- Parse/engagement are only whispered to the council and raid lead.
- Awards from the council or master looter only are added to the loot history.
- Texts are truncated UTF-8 safely.

## 0.12.0
- Configurable raid days with a login reminder to reserve.
- Loot history with sync and export, automatic awarding, Main/Off Spec rolls.
