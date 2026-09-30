# Changelog

## 1.2.3
- **Grid slots match the inventory's empty slots.** The look cells now copy what an empty inventory slot draws (plain dark with a faint grain) instead of the item slot frame. The tab column keeps the item slot frame. If no empty inventory slot is found (full bag), the cells fall back to the frame, then to flat dark.
- **RSE-ModMenu support.** New `modmenu.json`: Window style, Share looks, Show other players' looks and Debug log can be changed in game (Esc > MODS). Debug applies at once; the others after a restart. The settings stay in `Scripts\config.lua`.
- **Quieter log.** With `Debug = false` (the default), the log only shows the version line, errors and warnings. Mount, slot art, character load, server handshake and weapon-look step lines need `Debug = true`. The weapon crash guard message still always shows.
- New console command `transmog_slotart` (for developers): logs every candidate slot brush of a live empty and filled inventory slot. Open the inventory first.

## 1.2.2
- Fixed the same crash risk as RSE-Dock 1.2.1. An inventory panel queued during a map load could belong to the previous world (the main menu). Each load now empties the queue and drops panels made before it started.

## 1.2.1
- Fixed a crash when leaving and rejoining a world. While the new world loaded, the mod kept calling into characters and inventory widgets from the old one, and attached to the new inventory panel before the load had settled. It now forgets all of them when a map starts loading (characters, inventory views, the cached inventory slot used for slot art, and multiplayer controllers). It pauses until 3 s after the load finishes, then attaches to any inventory panel made during the load.

## 1.2.0
- **Game-style slots.** The look and tab squares now use the inventory's own slot art, copied from a live inventory slot, instead of flat grey boxes with a light outline. Hover and selection still show the tan fill and gold outline. The game's hover sparkle is not reproduced. If the slot art cannot be found, the squares stay flat dark.
- **Same spacing as RSE-Toolbag.** The window content now starts at the frame's inner edge, as in the Toolbag window, which leaves more room for the grid. Rows are 6 apart and cells 4 apart in both windows.
- **English only.** The Turkish interface text and the `Language` setting were removed. Item names still follow the game language. An old `config.lua` with a `Language` line keeps working; the line is ignored.
- **RSE-Dock support.** With RSE-Dock installed, the Transmog button becomes an icon in the dock's bar on the armour panel, next to other RSE mods' icons. Only one RSE window is open at a time. Without RSE-Dock, the Transmog button works as before.

## 1.1.0
- **Renamed to RSE-Transmog**, the first mod of the RSE (RuneScape Enhanced) family. The mod folder is now `ue4ss\Mods\RSE-Transmog\`: move your `saves\` folder over from `DragonwildsWardrobe\` to keep your choices, and remove the old folder. Console commands are now `transmog_status` and `transmog_dumpui`, and the inventory button reads **Transmog**.
- **Weapon and shield looks.** New Weapon and Off-hand tabs cover about 150 looks: swords, scimitars, maces, daggers, greatswords, great axes, mauls, staves, wands, bows, crossbows and shields. Each weapon type keeps its own look, and weapons can be hidden. The real weapon keeps working exactly as before: its meshes only stop drawing, and a local copy of the chosen weapon is drawn in their place.
- **Multiplayer looks.** Players who run the mod now see each other's armour and weapon looks. The host, or a dedicated server running the mod, relays the choices. Without the mod on the server, everything stays client-side as in 1.0.0.
- **Only known looks.** Transmog lists and accepts only appearances your character has unlocked: the recipe is learned, or the item was worn or held. The "Locked" filter button and the `ShowLockedByDefault` setting are gone. Saved looks from 1.0.0 that the character provably does not know are dropped on load.
- **Native-looking window.** Transmog now opens as its own window beside the inventory, in the inventory's frame art, with slot tabs down the left, a grid of look icons, the game's buttons, and the hovered look's name under the grid. `UIStyle = "classic"` keeps the 1.0 layout. If the game closes while the new wardrobe is open, the next launch falls back to the classic look once.
- New settings: `Multiplayer`, `ShowOthers`, `UIStyle`.
- Fixed: "Reset all" never asked for confirmation (and so never reset), and the filter button label and cell colours stopped updating after the first change.
- Fixed: UE4SS hot reload (Ctrl+R) with the inventory already created could crash the game. Leftover buttons, panels and weapon meshes from before the reload are now cleaned up.
- New console command `transmog_status` for bug reports.
- The local player is now found reliably when hosting, and the mod no longer scans every object each tick.

## 1.0.0
First public release.

- Wardrobe button on the inventory's armour panel. The panel has Head, Body, Legs and Cape tabs.
- The catalogue has 224 appearances: base game, Dowdun Reach, Umbral Sands, Scorned Wilderness, Agility and Fishing content. Wearables added by later game patches are picked up automatically.
- Item icons and in-game names are shown in your game language.
- Search box and a "Locked" filter. Locked means the recipe is not learned and the item was never worn.
- Clicking a look applies and saves it at once. "Original look" is at the top of every list.
- Hide option for Head and Cape.
- The inventory's character preview shows your chosen look.
- The look stays after loading, respawning, swapping gear and co-op sync.
- Choices are saved per character in `DragonwildsWardrobe\saves\`. Game save files are never touched.
- Paid, promotional and developer-only cosmetics are only offered if your character already owns them.
- English and Turkish interface.
