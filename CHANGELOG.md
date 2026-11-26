# Changelog

## 0.23.0
Calmer, more guided main window – step 1 of the UI overhaul.

- **Menu by role:** raiders only see *My gear*, *Loot history* and *Settings*. Council, master looter and raid lead (and anyone while no council is set up yet) also see *Getting started*, *Loot*, *Reservations*, *Players* and *Log*.
- **My gear** replaces “Gear sets” and looks like the character window: a 3D model of your character with the slots around it (armor left, hands to trinkets right, weapons below). The model wears your set – drag to rotate, wheel to zoom, “Now” shows what you wear today. Next to it, a list of all slots with boss and reserve dice.
- **Reserve with the dice** in the list (like “Need” when looting); the slot in the character sheet shows a small dice once it is picked. Clicking a slot opens its options: important, reserve the upgrade, remove the upgrade, choose another item, remove.
- **Next step:** one line at the top says what to do now (pick items, reserve with the dice, save, change request pending …) with at most one main button. It replaces the description, the summary line, the hint at the bottom and the reservation bar.
- Switching, creating, renaming and deleting sets moved into one drop-down. *My reservation* no longer has its own menu entry – it opens from the hint (“View”, “Full raid list”).
- **Bigger windows:** the main window is wider, and all Light Council windows are shown at 120 % by default (*Settings → Options → Window size*: 100–130 %; never larger than your screen). Rows in *My gear* are taller with bigger icons; an upgrade is shown in the list with an arrow next to its icon (no longer in the character sheet).

## 0.22.2
Fixes from a code review (also released as 0.22.1 on GitHub only).

- **Reserve by whisper:** while a change request is still open, `!lc` replies that the council has to decide first. Before, a second request only reached one council member, and another member could approve the old one.
- **Equipped item:** a player who doesn't answer inspect no longer blocks everyone else – they are retried after 90 seconds. Ranged weapons are shown from the main hand on clients without a separate ranged slot. Addon data always wins over inspect data, even if the name arrives in a different format.
- Smoother vote window while a raid forms; whisper commands no longer scan the guild roster several times per message.

## 0.22.0
- **Upgrade per slot:** next to the best item, every slot in a gear set can hold an **upgrade** – a second choice that is not as good, but still better than what you wear now. Tick “Upgrade” in the “Items” view; it shows up under the slot in “My set” and can be reserved there as well.
- The council sees “upgrade” in the vote window and tooltips (best items first: ★ important, in set, then upgrade). The raider loot window and “My reservation” show it too.
- “Take from gear set” adds upgrades last, and only if the best item for that slot is still missing.
- Upgrades don't count towards set progress (“4 of 10”). They are shared in a separate message, so older versions keep working (they just don't see upgrades). The JSON export has an `upgrade` field.

## 0.21.0
- **Reserve by whisper:** players without the addon whisper a council member `!lc [item]` and are entered automatically (same rules as in the addon: limit per raid, only items from a loot source). `!lc - [item]` removes, `!lc` shows their reservations and the commands.
- If the reservation is already locked, the whisper becomes a change request; the player gets a whisper once the council decides.
- Only council members process the commands; a raid lead without a council seat replies with the council names. Senders must be in your group or guild; at most one command every 3 seconds per player. Commands and replies are hidden from chat.
- New option under *Settings → Options*: “Reserve by whisper (!lc)” (on by default).

## 0.20.0
- **Vote window: equipped item.** A new “Equipped” column shows what each candidate currently wears in the item's slot (both slots for rings, trinkets and one-handers) with icon and item level; hovering shows the full item. Raid lead: hover the reservers in the loot window.
- Players with the addon share their equipped items with the group (only when they change). For players without the addon, council and raid lead look them up in the background via inspect (out of combat, in range); otherwise it says “unknown”. Inspect data older than 30 minutes is marked as outdated.

## 0.19.5
- **Settings are saved right away:** rules and score weights as soon as you leave a field or press Enter, the options as soon as you tick them. Before, changes were lost if you switched tabs without clicking “Save” (which is now only needed for the council names).
- Settings: the “Number of members” label no longer overlaps the 3/5 buttons, and long labels in the rules section no longer run into the next field (“Score: performance (parse) %” is now “Score: parse %”).

## 0.19.4
Security fixes.

- **First council list:** a raid lead is only accepted as the source of the first council list if they are in your guild. The lead of a pug raid can no longer set a fake council for new players (which then blocked the real council until `/lc councilreset`).
- **Own reservation:** a council member can no longer change their own locked reservation via “Enter for a player” – like a change request, another council member decides.
- **Privacy:** parse and engagement are only whispered to the raid lead if they are in your guild – no longer to the lead of a pug raid.
- Loot window messages without a valid item number are ignored instead of causing a Lua error.

## 0.19.3
Security fixes.

- **Free rolls** only count rolls from members of your own group – players standing nearby can no longer win an item.
- **Parse/engagement** from a raid lead without a council seat are only accepted if the raid lead is in your guild – the lead of a pug raid can no longer change your ratings.
- **Reservations:** if a raid is missing from the council's check (loot sources still loading after login), the list is rebuilt at most once a minute instead of rejecting valid reservations until the next reload.
- Names in council votes and in parse/engagement messages are cleaned of WoW formatting codes.

## 0.19.2
Security fixes.

- **Rolls:** a roll from a player with a similar name (e.g. “Ann Amüller” for “Anna Müller”) no longer counts as the eligible player's roll. The space-less name comparison is gone everywhere – also for score, loot cooldown, attendance and gear sets.
- **Reservations:** the council only accepts reservations for raids that exist in an installed loot source. Invented raid names can no longer fill the limit of 40 raids and block reservations for new raids.
- Names received from other players (council list, reservations, winners, reservers, vote candidates) are cleaned of WoW formatting codes.

## 0.19.1
Fixes from a code review.

- **Security:** permissions (council, raid lead, list owner, votes) no longer match names written without a space – a character called “Ann Amüller” could pass as “Anna Müller”.
- **Re-opening a corpse:** items keep their number in the raider window and their state (winner, council vote), even when loot slots move up. No more second council vote for an item that was already decided, and awards are no longer lost in the loot history.
- **Loot history:** every loot list gets a unique ID (full server time, counter and master looter), so awards from different raids can't collide and get dropped.
- **Raid evening:** syncing reservations no longer delays council votes – sync answers now use the low-priority queue.
- **Raid keys:** reservations are stored under a language-independent raid key (AtlasLoot). Players with clients in different languages now share the same raid, Russian clients can reserve with AtlasLoot, and the current raid is also recognized by instance ID. Existing reservations are moved over automatically.
- Tooltips: the Light Council block now also shows up again in comparison tooltips.
- Loot cooldown 0 weeks now really means no cooldown; the settings explain the cooldown and attendance period.
- Attendance: the sync request always fits into one message; the period is limited to 20 weeks (what the council syncs).
- Loot history sync fetches large gaps page by page instead of always sending the same 90 entries.
- Vote window: a player list that arrives late no longer clears your ticks and reason.
- Parse/engagement entered by a raid lead without a council seat now reach the council.
- Roll detection handles positional placeholders in the client's roll message; “waiting” in the raider window is translated.

## 0.19.0
- **Gear sets reworked:** sets are laid out by slot like the character window (armor, jewelry, weapons) with “4 of 10” per group and a green mark for items you already have. One item per slot (two rings, two trinkets) – a new item replaces the old one.
- Instead of ordering with arrows, mark important items with a star. The council sees “★ important”, “in set” or “has it” in the vote window and tooltips.
- **Reserve straight from your set:** every item in “My set” has a “Reserve” tick for the raid it drops in; a bar below shows the reservation for that raid and saves it (same selection as “My reservation”).
- “My reservation”: council and raid lead also get the “Council” tick on every item.
- New “Items” view in the gear sets tab: raids → bosses → items, pick items for your set with a tick; includes the item search.
- The “Raid loot” tab is gone: council and raid lead mark council items right in the “Items” view; the list of council items is under “Gear sets → Council items”.
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
- New: **JSON export** of all data – loot history, attendance, sit-outs, players and their wins, council items, reservations, gear sets and the decision log. Open it with `/lc json` or under Loot history → Export → “JSON (all data)”.
- On logout or `/reload` the JSON is also written to the SavedVariables (`LightCouncilExport.json`), ready for a future website or upload tool. Turn it off with `/lc json auto`.
- Privacy: parse, engagement and the log are only included in a council member's export; votes are exported without voter names; test runs are left out.
- Exported texts no longer contain WoW color and link codes; one log message that was still German-only is now translated.
- Removed leftover code from the old softres.it and council item text imports (no longer used since reservations moved into the addon).

## 0.16.1
- Fairness: an item counts as owned in a gear set if the loot history shows the player received it (nobody can look needier by reporting false data).
- Other players' sets show when they were last updated; sets older than 14 days are marked “(old)” in the council window.
- Performance: “do I have this item?” is cached; set changes are only broadcast when something actually changed.
- Version requests (`/lc check`) are only answered from your own group, at most every 30 seconds.
- Long sets are no longer cut off in the middle of an item; “Rename” shows the current name.

## 0.16.0
- New: **gear sets**. Raiders build one or more named sets (e.g. one per biome) and mark the items that matter most. The addon detects what you already have (equipped, bags, bank).
- The active set is shared with everyone; “Gear sets → All sets” shows everyone's progress.
- The council vote window has a new “Set” column showing whether the item is in the player's set; tooltips show the whole set.
- “My reservation”: “+ Set” on every item; optional “Take from gear set” (the council turns this on under “Raid days” – pugs without a set reserve as usual).
- Item tooltips and the loot window show who has the item in their set and its place in your own set.

## 0.15.0
- Deleted loot history entries are synced and no longer come back.
- Version check: notice about newer versions; `/lc check` lists all versions in the raid.
- Item tooltips show council item and reservers (`/lc tooltip` to turn off).
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
