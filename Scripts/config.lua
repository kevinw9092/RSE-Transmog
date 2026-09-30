-- RSE-Transmog user settings. Edit with any text editor, then restart the game,
-- or change them in game with RSE-ModMenu (Esc > MODS; Debug applies at once).
return {
    -- "native": the wardrobe opens as its own window beside the inventory,
    --           in the inventory's frame art, with icon slots and icon tabs.
    -- "classic": the original compact list with names, over the inventory grid.
    UIStyle = "native",

    -- Share your looks with other players who run the mod, and see theirs.
    -- Works when the host (or the dedicated server) also runs the mod;
    -- otherwise the mod quietly stays client-side.
    Multiplayer = true,

    -- false: always show other players' real gear, even if they share a look.
    ShowOthers = true,

    -- Extra log lines in ue4ss\UE4SS.log (useful for bug reports).
    Debug = false,
}
