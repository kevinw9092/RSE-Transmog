# RSE-Transmog

*Part of **RSE** (RuneScape Enhanced), a family of UE4SS mods for RuneScape: Dragonwilds.*

Wear the look you like while keeping the stats of the gear you actually use.
This is a visual-only transmog for **RuneScape: Dragonwilds**, built on UE4SS.

## Features
- **Transmog** button on the inventory's armour panel. It opens a window with **Head / Body / Legs / Cape / Weapon / Off-hand** tabs.
- **Looks like the game.** Transmog opens as its own window beside the inventory, drawn with the inventory's frame art: slot tabs down the left, a searchable grid of look icons, and the game's buttons and click sounds. The inventory stays visible and usable next to it. The name of the hovered look is shown below the grid. Set `UIStyle = "classic"` for the original compact list with names.
- Every appearance is listed with its icon and in-game name. There are 224 armour looks and about 150 weapon and shield looks, including the Dowdun Reach, Umbral Sands and Scorned Wilderness items.
- **Weapons and shields**: each weapon type keeps its own look: sword, scimitar, mace, dagger, greatsword, great axe, maul, staff, wand, bow, crossbow and shield. A sword can only look like another sword, so grips and animations always fit. The Weapon and Off-hand tabs list looks for whatever you are holding in that hand.
- **Multiplayer**: other players who run the mod see your look, and you see theirs. The host or dedicated server needs the mod too.
- **Click to wear.** The choice is saved at once. **Original look** returns the real item.
- **Hide** the helmet, the cape or any weapon type (for example your shield).
- **Only looks you know**: an appearance is offered once your character has learned its recipe, or has worn or held the item. Looks you have not unlocked are never listed and cannot be chosen.
- **Search** box.
- The inventory character preview shows your chosen armour look.
- The look survives gear swaps, loading, respawning and co-op sync.
- Choices are saved **per character**.
- Stats, armour values, damage, hit detection, inventory and your save files are never changed.
- English interface. Item names are shown in your game language.

## Requirements
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for RuneScape: Dragonwilds. Use a recent **experimental** build. The mod was tested with `v3.0.1-1140` and `v3.0.1 Beta (f6d5f942)`.
- Tested on game build CL-240163.

## Installation
1. Install UE4SS if you have not already. After this step, `RSDragonwilds\Binaries\Win64\ue4ss\` exists.
2. Extract the archive so this folder exists:
   ```
   RSDragonwilds\Binaries\Win64\ue4ss\Mods\RSE-Transmog\
       Scripts\  saves\  enabled.txt
   ```
3. Start the game and open your inventory. The **Transmog** button sits at the top right of the armour panel.
4. For multiplayer, the host needs the mod as well. On a **dedicated server**, install UE4SS on the server and copy the same `RSE-Transmog` folder into its `ue4ss\Mods\`. The server only relays choices and needs no configuration.

Vortex: install as a normal mod. If the button does not appear, check that the folder landed in `ue4ss\Mods\`.

## Uninstall
Delete the `RSE-Transmog` folder. Your character immediately shows the real gear again, and nothing needs to be cleaned up.

## Settings
With **RSE-ModMenu** installed, change them in game: Esc > MODS > RSE-Transmog. Otherwise open `Scripts\config.lua` in a text editor. Only `Debug` applies at once; the others apply after restarting the game.

| Setting | Default | Meaning |
|---|---|---|
| `UIStyle` | `"native"` | `"native"`: its own window beside the inventory, in the inventory's frame art. `"classic"`: the compact list with names, over the inventory grid. If the game closes while the native window is open, the next launch uses the classic look once and says so in the log. |
| `Multiplayer` | `true` | Share your looks with other mod users and see theirs |
| `ShowOthers` | `true` | `false` always shows other players' real gear |
| `Debug` | `false` | Extra lines in `ue4ss\UE4SS.log`. Off: only the version line, errors and warnings |

## Multiplayer
Looks are shared between players who run the mod:

| You | Host / server | Other player | What the other player sees |
|---|---|---|---|
| mod | mod | mod | your chosen look |
| mod | mod | no mod | your real gear |
| mod | no mod | anything | your real gear (the mod stays client-side) |

Only the ids of the looks you chose travel over the network. They use two built-in engine messages (`ServerExec` and `ClientMessage`) that the game itself does not use. Your equipment, stats and the game's replicated state are never changed, so players without the mod are not affected. When the host or server has no mod, your game sends six short hello messages after joining and then stays silent.

The host or server checks every message: known slots, well-formed ids, and length and rate limits. It relays messages only to players who run the mod. Players who join later receive everyone's current looks.

## Paid and promotional items
Items that need an entitlement (for example Early Adopter, Community, Gilded or Deluxe items) are only listed if your character has worn them. The mod never unlocks paid content.

## FAQ
**The button is missing.** Make sure UE4SS loads: `ue4ss\UE4SS.log` should contain `[RSE-Transmog] v1.2.3 loaded`.

**A slot says "Nothing equipped here".** The transmog changes the look of an equipped item. Equip any item in that slot and your saved choice applies automatically.

**The Weapon tab asks me to hold a weapon.** Weapon looks are chosen per weapon type. Equip the type you want to change, then pick its look. The choice applies to every weapon of that type.

**My friend does not see my look.** You, your friend and the host (or dedicated server) all need v1.1.0 or newer with `Multiplayer = true`. Open the console (UE4SS console enabler) and type `transmog_status`. If it shows `server answered: true`, sharing works.

**The enchantment glow is missing on my weapon look.** Imbue and enchantment glows are drawn on the real weapon, which is hidden while a look is active. Effects that are attached to the weapon, such as staff orbs or fire, still show.

**A look I own is missing from the list.** Looks appear once your character has learned the item's recipe, or has worn or held the item. For dropped items without a recipe, equip the item once.

**Can I reload the mod without restarting?** Yes, with UE4SS hot reload (`EnableHotReloadSystem = 1` in `UE4SS-settings.ini`, then Ctrl+R). The mod removes its old button, panel and weapon meshes and sets itself up again. Reloading at the main menu is still the safest.

**How do I reset one character?** Use **Reset all** in the Transmog window, or delete that character's file in `saves\`.

## Bug reports
Please attach `RSDragonwilds\Binaries\Win64\ue4ss\UE4SS.log`. Turning on `Debug = true` first makes the log more useful. For weapon or multiplayer problems, hold the weapon and run `transmog_status` in the console before closing the game. The command writes what the mod sees to the log.

## Credits
RSE-Transmog is based on [Dragonwilds Wardrobe](https://www.nexusmods.com/runescapedragonwilds) by ColonelCousland, released under the MIT license. The original copyright notice is kept in `LICENSE`.

---

## Development
- `tools\Deploy-Scripts.ps1 [-GameRoot <path>]` copies the mod into a UE4SS installation.
- `tools\Package.ps1` builds `dist\RSE-Transmog-v<VERSION>.zip`. The version comes from `VERSION` and must match `main.lua`.
- Module overview:
  - `visual.lua`: per-character renderer for the local player and other players. Armour pointer swap, `OnRep` refresh and restore; watchdog; hooks; preview sync.
  - `held.lua`: weapon looks. The real weapon meshes stop rendering and nothing else about them changes. Local ghost meshes, built from the chosen weapon Blueprint's component templates, are attached in their place.
  - `net.lua`: multiplayer relay over `ServerExec` and `ClientMessage`.
  - `catalog.lua`: armour and weapon appearance lists, weapon categories, runtime discovery, recipe/unlock lookup.
  - `ui.lua`: Transmog window (native and classic).
  - `store.lua`: per-character files.
  - `i18n.lua`: interface strings.
  - `config.lua`: user settings.

### QA checklist
1. After launch, the log shows `v1.2.3 loaded` and no `UI:`/`visual:`/`net:` errors.
2. Opening the inventory shows the button. Closing it hides the button and the panel. The panel covers the inventory grid exactly at 1080p, 1440p and ultrawide.
3. Native look: the game's panel frame, icon tabs that follow the equipped item's icon, and a grid of crafting-style icon slots. Hover shows the look's name below the grid. The worn look is shown selected, and Original and Hide carry a label. No recipe tooltip appears on hover. Classic look (`UIStyle = "classic"`): icons and names in two columns with a gold highlight. In both looks, search filters the list and the count updates.
4. Clicking a look changes both the world model and the inventory preview. Character stats and armour values stay the same.
5. Only looks with a learned recipe or a previously worn or held item are listed. A look becomes available after learning its recipe and reopening the tab. A look saved by an older version that the character provably does not know is dropped on load, with a log line when `Debug` is on.
6. Hide works for Head and Cape. The game's own "hide helmet" setting keeps working.
7. The look is restored after changing gear, unequipping and re-equipping, dying and respawning, leaving and rejoining the world, and restarting the game.
8. Two characters keep separate choices, one file each in `saves\`.
9. In co-op, both as host and as client, the look persists. With the mod on both sides, the other player sees your look, and it updates when you change it. Without the mod on the other side, they see the real gear.
10. After the mod folder is deleted, the game runs normally with the real gear.
11. Every button in the Transmog window works with a gamepad.
12. `tools\Package.ps1` produces a zip that contains only the release files.
13. Weapon tab: holding a sword lists only swords. Picking a look replaces the held sword. Attacks, blocking and hit detection are unchanged, and the look follows the weapon being hidden (emotes, climbing).
14. Bows and crossbows: the look draws and fires with the real weapon's animation. Loaded arrows and bolts still show.
15. Switching weapon type while the Transmog window is open switches the list. Each type remembers its own look.
16. A dedicated server with the mod relays looks. Players who join later see existing looks, and looks of players who leave are cleaned up. `transmog_status` shows `server answered: true` on clients.
17. With a vanilla host, the log shows no errors and the game behaves exactly as with v1.0.0.
