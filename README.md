# Dragonwilds Wardrobe (Transmog)

Wear the look you like while keeping the stats of the armour you actually use.
This is a visual-only transmog for **RuneScape: Dragonwilds**, built on UE4SS.

## Features
- **Wardrobe** button on the inventory's armour panel. It opens a panel with **Head / Body / Legs / Cape** tabs.
- Every appearance is listed with its icon and in-game name. There are 224 looks, including the Dowdun Reach, Umbral Sands and Scorned Wilderness armour.
- **Click to wear.** The choice is saved at once. **Original look** returns the real item.
- **Hide** the helmet or cape.
- **Search** box, plus a **Locked** filter that hides looks you have not unlocked (recipe learned or item worn before).
- The inventory character preview shows your chosen look.
- The look survives gear swaps, loading, respawning and co-op sync.
- Choices are saved **per character**.
- Stats, armour values, inventory and your save files are never changed.
- English and Turkish interface.

## Requirements
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) for RuneScape: Dragonwilds. Use a recent **experimental** build. The mod was tested with `v3.0.1-1140` and `v3.0.1 Beta (f6d5f942)`.
- Tested on game build CL-240163.

## Installation
1. Install UE4SS if you have not already. After this step, `RSDragonwilds\Binaries\Win64\ue4ss\` exists.
2. Extract the archive so this folder exists:
   ```
   RSDragonwilds\Binaries\Win64\ue4ss\Mods\DragonwildsWardrobe\
       Scripts\  saves\  enabled.txt
   ```
3. Start the game and open your inventory. The **Wardrobe** button sits at the top right of the armour panel.

Vortex: install as a normal mod. If the button does not appear, check that the folder landed in `ue4ss\Mods\`.

## Uninstall
Delete the `DragonwildsWardrobe` folder. Your character immediately shows the real gear again, and nothing needs to be cleaned up.

## Settings
Open `Scripts\config.lua` in a text editor:

| Setting | Default | Meaning |
|---|---|---|
| `Language` | `"auto"` | `"en"` or `"tr"` to force a language |
| `ShowLockedByDefault` | `true` | Start with locked looks visible |
| `Debug` | `false` | Extra lines in `ue4ss\UE4SS.log` |

## Multiplayer
The transmog is **client-side**. You see your chosen look, while other players see your real armour. Nothing is sent to the host or server.

## Paid and promotional items
Items that need an entitlement (for example Early Adopter, Community, Gilded or Deluxe items) are only listed if your character has worn them. The mod never unlocks paid content.

## FAQ
**The button is missing.** Make sure UE4SS loads: `ue4ss\UE4SS.log` should contain `[DragonwildsWardrobe] v1.0.0 loaded`.

**A slot says "Nothing equipped here".** The transmog changes the look of an equipped item. Equip any item in that slot and your saved choice applies automatically.

**How do I reset one character?** Use **Reset all** in the wardrobe, or delete that character's file in `saves\`.

## Bug reports
Please attach `RSDragonwilds\Binaries\Win64\ue4ss\UE4SS.log`. Turning on `Debug = true` first makes the log more useful.

---

## Development
- `tools\Deploy-Scripts.ps1 [-GameRoot <path>]` copies the mod into a UE4SS installation.
- `tools\Package.ps1` builds `dist\DragonwildsWardrobe-v<VERSION>.zip`. The version comes from `VERSION` and must match `main.lua`.
- Module overview:
  - `visual.lua`: pointer swap, `OnRep` refresh and restore; watchdog; hooks; preview sync.
  - `catalog.lua`: appearance list, runtime discovery, recipe/unlock lookup.
  - `ui.lua`: wardrobe panel.
  - `store.lua`: per-character files.
  - `i18n.lua`: interface strings.
  - `config.lua`: user settings.

### QA checklist
1. After launch, the log shows `v1.0.0 loaded` and no `UI:`/`visual:` errors.
2. Opening the inventory shows the button. Closing it hides the button and the panel. The panel covers the inventory grid exactly at 1080p, 1440p and ultrawide.
3. Every tab lists icons and names in two columns. The active tab and the worn look are highlighted in gold, and cells highlight on hover. Search filters the list, and the count updates.
4. Clicking a look changes both the world model and the inventory preview. Character stats and armour values stay the same.
5. With the Locked filter off, only unlocked or previously worn looks are listed.
6. Hide works for Head and Cape. The game's own "hide helmet" setting keeps working.
7. The look is restored after changing gear, unequipping and re-equipping, dying and respawning, leaving and rejoining the world, and restarting the game.
8. Two characters keep separate choices, one file each in `saves\`.
9. In co-op, both as host and as client, the look persists and the other player sees the real armour.
10. After the mod folder is deleted, the game runs normally with the real gear.
11. Every button in the wardrobe works with a gamepad.
12. `tools\Package.ps1` produces a zip that contains only the release files.
