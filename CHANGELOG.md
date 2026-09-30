# Changelog

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
