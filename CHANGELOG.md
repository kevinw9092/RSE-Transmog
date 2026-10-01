# Changelog

## 1.3.2
- **Armour looks in solo and on a listen host no longer touch the equipped-item fields.** Until now every machine swapped the replicated `Current<Slot>Wearable` to the look for one call and ran the game's `OnRep` refresh. On the machine with authority that field is the real state, and its refresh may do more than draw. There the look's mesh, materials and animation class are now put straight on the outfit mesh, the way the inventory preview already was. If that fails, the old route runs. Players joining someone else's game keep the old route, which also hides body parts under the armour the way the game does. The direct route does not, so a look may show some clipping in solo.
- **Owned DLC looks are no longer locked.** Items that need an entitlement now ask the game's own `CanBeEquipped` check. If it can't be asked, the item stays locked as before. Paid and promotional cosmetics that aren't worn yet stay hidden.
- Learning a recipe while the wardrobe is open now unlocks its look straight away. Switching tabs still refreshes the list as well.
- Weapon looks: a hand is fully checked again only when the game reports a weapon change, or once a second as a safety net. Where no such report has arrived yet (for example a host's own character), every tick still checks, as before.
- Item icons are read with the item's own `GetIcon`. The older ways stay as the fallback.
- Weapon looks try the weapon actor's native `MeshComponent` first. Removed calls to engine functions that don't exist in this game (`SetSkeletalMesh`, `SetMasterPoseComponent`, the `SkeletalMeshAsset` property).

## 1.3.1
- **Dedicated servers:** the server is detected once the world has settled, and then only the look relay runs. It looked for a local player every second and ran the wardrobe's ticks for nothing.
- **Removed a crash risk:** `transmog_dumpui` no longer reads widgets' drawn size (passing it to SlateBlueprintLibrary has crashed this game). It logs the desired size only.
- The wardrobe's hover check covers only the tab on screen, not every tab opened so far. Buttons for a tab are made with the widget library, world and owner looked up once per tab.
- The inventory's character preview is re-applied only when the choice, the real item, the body type or the drawn mesh changed (it redid every slot every 240 ms).
- Solo play: other players' looks are not scanned for when nobody has shared one.
- **Saves:** a save interrupted between removing the old file and the rename is finished on the next load, instead of the looks being lost.
- A look that failed to load once (content still streaming in) comes back after the next map load instead of staying hidden until a restart.
- Debug text is built only with Debug on.

## 1.3.0
- **Looks now sync on dedicated servers.** Players' games sent their looks to the server with the engine's `ServerExec` debug command. A release dedicated server drops that command before any mod sees it, so the server never heard from anyone, and nobody saw anyone else's looks. The 1.2.9 logs showed this: a joining player's `ServerAcknowledgePossession` reached the server's mods, but `ServerExec` never did. Players now send with `ServerNotifyLoadedWorld`. It's a reliable engine message that the server acts on only during a seamless map change, and only for the new map's name, which a Transmog message never is. The server still accepts the old `ServerExec` messages from players on older versions.
- **Update both sides.** The server and every player need 1.3.0 for looks to sync.
- Removed the 1.2.9 test hooks. The one-line `relay:` log messages stay.

## 1.2.9
- **More relay diagnostics.** 1.2.8 showed that no player message reaches Transmog on the dedicated server. RSE-Toolbag's server sends "ready" without waiting for a message, so it never showed whether player-to-server messages arrive at all. The server now logs once when any player's `ServerExec` arrives, whatever its text. It also logs once when two messages every game sends while joining arrive (`ServerAcknowledgePossession`, `ServerNotifyLoadedWorld`). Together these show whether only `ServerExec` is lost, or every player message to the server.

## 1.2.8
- **Relay diagnostics.** The server logs one line per session when a player's first message arrives and when it answers a hello, whatever the Debug setting. It also logs one line for each reason it would drop a message silently: the message doesn't count as reaching the server, the player has no player ID, the text can't be read, or the answer can't be sent. The player's game says once when the server never answered, with a pointer to those lines. Before this, "others cannot see my looks" left nothing in either log.

## 1.2.7
- **Fixed freezes when switching item types.** On each switch the mod checked which looks you know. Any look without a known recipe made it re-read all ~900 of the game's recipes, every time (at most every 5 s). It now reads only recipes it has not seen before. It also remembers looks that have no recipe, and checks those again only once a minute.
- With Debug on, any step of a switch that takes 30 ms or more is logged ("slow switch to ...").

## 1.2.6
- Fixed the Transmog window sometimes going dead after a join or world change: hover sounds played, but nothing highlighted and looks could not be clicked. The game keeps the inventory panel across some map loads, and the mod only re-attached to newly made panels. After a load it now also re-attaches to the panel that is already there.

## 1.2.5
- **Fixed crashes from stale cached game objects after the game unloaded them.** The mod kept some game objects in its own memory between uses: item icons, weapon-look mesh templates, fonts and widget classes. The game can unload an object that nothing of its own uses, and the mod's copy then pointed at freed memory. The next use crashed the game. This caused the crashes on rejoining a world, just after the inventory appeared (icon), and during play when a weapon look was applied (weapon template).
- The mod now keeps only names and paths, and looks the object up again each time it needs it. This covers item icons, the inventory and armour looks shown on your character, weapon-look templates, recipes, fonts, widget classes, the inventory slots used for the slot art, and the inventory preview.
- All of these are also cleared on every map load.
- After a map load, the mod now waits for 10 of its own ticks as well as 3 seconds. Right after a load the game can spend several seconds in a single frame, and a time-only wait could end in the very next frame.

## 1.2.4
- The look cells now look like the inventory's empty slots: a slightly darker square over the window's own grain, with no framed slot art. The game's empty slots draw no texture of their own; every slot brush is empty, as `transmog_slotart` showed. The tab column keeps its slot art.

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
