# Roadmap

## In progress
- **Native-looking Transmog UI (option 1.B).** Its own window beside the inventory, drawn with the inventory frame's art (copied brushes), slot tabs down the left, and an icon grid. Cells are plain UMG in the inventory's style: the game's crafting slot and tab widgets crashed the game without the recipe data their C++ expects. Polishing from in-game screenshots. `transmog_dumpui` writes widget trees, reflection data and sizes to `ui-dump.txt`.

## Later
- **Transmog as a buildable.** The most viable route is the low-risk one: hook an existing placeable (for example the Armour Mannequin, `BP_BaseBuilding_ArmourMannequin` with `BP_ArmourMannequin_InteractionComponent`) so an extra interaction opens Transmog.
  - Nothing new goes into world saves, and vanilla players are unaffected.
  - The Transmog window must then also work as a standalone screen (cursor and input mode), not only inside the inventory.
  - It must not replace the mannequin's own function.
- A brand-new buildable piece (its own build-menu entry, for example with a Wild Anima cost) is not planned. It needs a cooked pak on the server and every client, and removing the mod would leave broken pieces in world saves.

## Rejected
- Reusing `WBP_Crafting_MainPanel` directly: it is driven by crafting station and recipe data, and its buttons call real crafting RPCs.
