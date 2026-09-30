local I = {}

local strings = {
    en = {
        wardrobe = 'Transmog', back = '« Inventory', close = 'Close',
        dockDesc = 'Change how your armour and weapons look. Stats stay the same.',
        Head = 'Head', Body = 'Body', Legs = 'Legs', Cape = 'Cape', MainHand = 'Weapon', OffHand = 'Off-hand',
        search = 'Search appearances...',
        count = '%d / %d appearances',
        original = 'Original look', originalShort = 'Original', hide = 'Hide',
        resetSlot = 'Reset slot', resetAll = 'Reset all', confirm = 'Click again to confirm', confirmShort = 'Confirm?',
        equipped = 'Equipped: %s   |   Look: %s',
        equippedLine = 'Equipped: %s', lookLine = 'Look: %s',
        nothing = 'nothing', hidden = 'hidden',
        empty = 'Nothing equipped here. Your choice applies when you equip an item.',
        emptyHand = 'Hold a weapon or shield in this hand to pick a look for its type.',
        applied = '%s applied',
        resetDone = 'All slots show your real equipment again',
        failed = 'Could not apply this appearance',
        noCharacter = 'Your character is not ready yet',
        notKnown = 'You have not unlocked this look yet',
    },
}

-- Interface text is English only (Turkish was removed). Item names still come
-- from the game, in the game's language.
local active = 'en'

function I.t(key, ...)
    local s = strings[active][key] or strings.en[key] or key
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
end

return I
