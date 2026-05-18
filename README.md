# AndeReminders

A lightweight World of Warcraft addon (The War Within) that nudges you about the small things you forget right before pulls — talent build, missing enchants, low durability, wrong weapon — plus a few quality-of-life utilities for combat and encounters.

## Features

### Talents
- Flashes your active talent loadout name + icon on screen when a ready check fires.
- Uses [TalentLoadoutEx](https://www.curseforge.com/wow/addons/talent-loadout-ex) names and icons if installed; otherwise falls back to the native saved-config name.
- Configurable font, size, and color. Shows `unknown talent loadout` if none is detected.

### Gear
On login, zone change, and equip, checks for:
- **Wrong weapon type** for your spec
- **Wrong primary stat** on your weapon
- **Item level below a configurable threshold**

Notifications can be on-screen, in chat, or both.

### Repair
Continuous durability monitor. A large on-screen banner appears the moment any slot drops below 50% durability (out of combat).

### Enchants
- Checks every enchantable slot for missing enchants on login/zone/equip.
- Per-slot or global item-level floor so you don't get nagged about leveling greens.
- On-screen alert and/or chat output.

### Encounter Utilities
- **Combat in/out text** — flashes `+Combat` / `-Combat` when you enter or leave combat. Independent size and color per direction. Off by default.
- **Midnight Falls graphics overrides** (Encounter ID 3183) — optionally drops `graphicsParticleDensity` / `RaidGraphicsParticleDensity` and/or projected-textures CVars to `0` for the duration of the fight, then restores your original values on `ENCOUNTER_END`. Saved values are written to SavedVariables, so a mid-encounter `/reload` or disconnect still restores the originals on next login.

## Anchors

Every notification type has its own draggable anchor frame. Open settings, click **Toggle Anchors**, and drag the colored boxes wherever you want them. Positions are saved per account.

## Slash commands

| Command | Action |
| --- | --- |
| `/ar` | Toggle the settings window |
| `/ar anchors` | Show / hide the anchor frames |

## Optional dependencies

- **LibSharedMedia-3.0** — extra font choices. Falls back to four built-in WoW fonts if missing.
- **TalentLoadoutEx** — adds loadout names and icons to the talent reminder. Falls back to native saved-config names if missing.

## Installation

1. Download the latest release.
2. Extract the `AndeReminders` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Restart the game or `/reload`.

## Saved Variables

All settings live in `AndeRemindersDB`, scoped per account.
