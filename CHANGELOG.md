# Changelog

## 0.19.0
- **Gear sets reworked:** sets are laid out by slot like the character window (armor, jewelry, weapons) with “4 of 10” per group and a green mark for items you already have. One item per slot (two rings, two trinkets) – a new item replaces the old one.
- Instead of ordering with arrows, mark important items with a star. The council sees “★ important”, “in set” or “has it” in the vote window and tooltips.
- **Reserve straight from your set:** every item in “My set” has a “Reserve” tick for the raid it drops in; a bar below shows the reservation for that raid and saves it (same selection as “My reservation”).
- “My reservation”: council and raid lead also get the “Council” tick on every item.
- New “Items” view in the gear sets tab: raids → bosses → items, pick items for your set with a tick; includes the item search.
- The “Raid loot” tab is gone: council and raid lead mark council items right in the “Items” view; the list of council items is under “Gear sets → Council items”.
- **Loot priority removed completely:** the addon is about rolling, and the council assigns single items in a targeted way. No more priority editor, announcements or priority lines in the loot window and tooltips; stored priorities are deleted and the JSON export no longer has `prio`.
- Existing sets are converted automatically. Older addon versions still understand the shared sets.

## 0.18.0
- New: **item search** by name or item ID across all raids of the loot source.
  - “Raid loot” and “My reservation”: search field above the boss list – picking a result jumps to the raid and boss and highlights the item.
  - “Gear sets”, “Council items” and the manual selection: type a name and pick from the list to add the item directly.
  - Arrow keys select, Enter takes the result, Escape closes. Case-insensitive, including umlauts and Cyrillic. Shift-click and typing IDs work as before.

## 0.17.1
- Fix: in the test vote (and whenever the raid lead is also on the council) the vote window could open without any players, so “Restrict” and “Sit out” were impossible. Messages to yourself are now delivered in order, and a player list that arrives late refreshes the window.
- The test vote uses one of your council items instead of an item that may not exist in Forever.

## 0.17.0
- New: **JSON export** of all data – loot history, attendance, sit-outs, players and their wins, council items, priorities, reservations, gear sets and the decision log. Open it with `/lc json` or under Loot history → Export → “JSON (all data)”.
- On logout or `/reload` the JSON is also written to the SavedVariables (`LightCouncilExport.json`), ready for a future website or upload tool. Turn it off with `/lc json auto`.
- Privacy: parse, engagement and the log are only included in a council member's export; votes are exported without voter names; test runs are left out.
- Exported texts no longer contain WoW color and link codes; one log message that was still German-only is now translated.
- Removed leftover code from the old softres.it, priority and council item text imports (no longer used since reservations moved into the addon).

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
