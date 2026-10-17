# AndeReminders

A lightweight World of Warcraft addon (Midnight, patch 12.1.5) that nudges you about the small things you forget right before pulls — talent build, missing enchants, low durability, wrong weapon — plus quality-of-life utilities and a custom boss-mod alert builder for BigWigs / DBM.

## Features

### Talents
- Flashes your active talent loadout name + icon on screen when a ready check fires.
- Uses [TalentLoadoutEx](https://www.curseforge.com/wow/addons/talent-loadout-ex) names and icons if installed; otherwise falls back to the native saved loadout name (or "Starter Build" while that is active).
- Configurable font, size, and color. Shows `unknown talent loadout` if none is detected.
- **Expected loadout by content**: on the Talents tab, switch to the loadout you want, pick the content (any raid, a raid difficulty, Mythic+, a dungeon difficulty, Delves, or the instance you are standing in) and click **Add rule**. On a ready check you get a red "Wrong talent loadout! Switch to: ..." warning if the active loadout differs. Rules are per spec, the most specific one wins, and the tab shows your active loadout, where you are, and whether the rule for here matches.

### Gear
On login, zone change, and equip, checks for:
- **Wrong weapon type** for your spec (2H / 1H / shield, judged by equip location so new weapon types just work)
- **Wrong primary stat** on your weapon
- **Item level below a configurable threshold** (uses the item's effective level, so upgraded gear is judged correctly)
- **Missing Goblin Glider cloak tinker** for Engineers (language independent)

Notifications can be on-screen, in chat, or both. Equipment changed mid-fight is re-checked when combat ends.

### Repair
Continuous durability monitor. A large on-screen banner appears the moment any slot drops below a configurable durability threshold (default 50%, out of combat), including right after login if you log in damaged.

### Enchants & Gems
- Checks every enchantable slot for missing enchants on login/zone/equip.
- Optionally warns about empty gem sockets on any equipped item.
- Per-slot or global item-level floor so you don't get nagged about leveling greens.
- On-screen alert and/or chat output.

### Encounter Utilities
- **Combat in/out text** — flashes `+Combat` / `-Combat` when you enter or leave combat. Independent size and color per direction. Off by default.
- **Midnight Falls graphics overrides** (Encounter ID 3183) — optionally drops `graphicsParticleDensity` / `RaidGraphicsParticleDensity` and/or projected-textures CVars to `0` for the duration of the fight, then restores your original values on `ENCOUNTER_END`. Saved values are written to SavedVariables, so a mid-encounter `/reload` or disconnect still restores the originals on next login.

### Quality of Life
- **Great Vault minimap button** — hover for the example reward item levels of your Raid, Mythic+ and Delve slots; click to open the vault. The icon changes when rewards are waiting.
- **Auto-accept LFG role checks** — uses your assigned role, or your spec role if none is assigned. Off by default.

### World markers
Keybinds for the eight world markers and "clear all". Markers are placed at your feet, or at the mouse cursor if you enable that option. Bindings are re-applied every login, and retried after combat if a reload happened mid-fight.

### Target markers
Keybinds for the eight raid target icons (applied to your current target) and a "clear all" that unmarks every unit it can reach: you, your group and their targets, nameplates, boss frames, target, focus and mouseover. Needs group leader or assist when grouped.

### BossMods
Build your own alerts on top of BigWigs or DBM:
- Entry types: **Icon**, **Text**, **Progress bar**, and **Group** (stacks its members).
- Triggers: a boss-mod announce message or a boss-mod timer, filtered by spell ID, text (contains / equals / Lua pattern), count, and boss stage; timers can appear only when N seconds remain.
- Load conditions: class, role, encounter, zone (or zone group), difficulty.
- Display options: font, size, color, icon override (with a searchable icon picker), progress swipe, a `%m` message / `%c` count / `%t` time template, anchor point and offset.
- Conditions: on show, on hide, or at a remaining time — glow (pixel / proc / auto-cast), play a sound, scale, recolor, or flash.
- Export and import entries (or whole groups) as copy-pasteable strings.

Boss-mod text that the game marks as secret (12.x) is never read by the addon; those entries simply fall back to their own name.

## Snooze and ignore

Gear, enchant and gem alerts list each problem on its own row:
- **Ignore** stops reminding you about that one item. Enchant slots are unticked in the Enchants table, ignored gem slots and gear issues are listed on their tab with a button to turn them back on.
- **Snooze** hides the alert until something new is wrong or you reload the UI. `/ar unsnooze` brings snoozed alerts back.

## Anchors

Every notification type has its own draggable anchor frame. Open settings, click **Toggle Anchors**, and drag the colored boxes wherever you want them. Positions are saved per account.

## Slash commands

| Command | Action |
| --- | --- |
| `/ar` | Toggle the settings window (Escape closes it) |
| `/ar anchors` | Show / hide the anchor frames |
| `/ar reset` | Put every anchor back at its default position |
| `/ar unsnooze` | Show snoozed alerts again |
| `/ar help` | List the commands |
| `/arbm list` | List BossMods entries and their trigger types |
| `/arbm trigger` | Fire a 10s test timer to check which entries would match |

## Optional dependencies

- **LibSharedMedia-3.0** — extra font, bar texture and sound choices. Falls back to four built-in WoW fonts if missing.
- **TalentLoadoutEx** — adds loadout names and icons to the talent reminder. Falls back to native saved-loadout names if missing.
- **BigWigs** or **DBM** — required for BossMods entries to trigger.

## Installation

1. Download the latest release.
2. Extract the `AndeReminders` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Restart the game or `/reload`.

## Saved Variables

All settings live in `AndeRemindersDB`, scoped per account.
