-- Appearance catalogue.
-- Static list: every WearableEquipmentData and weapon HeldEquipmentData found
-- in game build CL-240163 (base game plus the DowdunReach, UmbralSands,
-- ScornedWilderness, Agility and Fishing content plugins). Items added by later
-- patches are picked up at runtime from loaded objects (see discover()).
--
-- Lists are keyed by "slot key": Head/Body/Legs/Cape for armour, and
-- "Held:<Category>" (Held:Sword, Held:Shield, ...) for weapons. A weapon look
-- can only replace a weapon of the same category, so grips and animations fit.
local C = {}
local EQUIPMENT = '/Gameplay/Character/Player/Equipment/'
C.HELD_PREFIX = 'Held:'

-- Paid, promotional or developer-only cosmetics are never offered unless the
-- character already owns them (has worn them). Keeps the mod within Nexus rules.
local EXCLUDE = { 'AlphaTest', 'EarlyAdopter', 'Community', 'GildedPaladin', '_DE_', '_Test' }

-- Weapon categories offered in the wardrobe. The category is the folder under
-- Equipment/Held/, so it is known for any weapon, including future ones.
local WEAPON_CATEGORIES = {
    Sword = true, Scimitar = true, Mace = true, Dagger = true, Greatsword = true, GreatAxe = true,
    Maul = true, Staff = true, Wand = true, Bow = true, Crossbow = true, Shield = true,
}
local CATEGORY_ALIAS = { ScarabStaff = 'Staff' }
local UNIQUE_ALIAS = { Club = 'Mace', Hammer = 'Maul', Shortbow = 'Bow' }

-- Held/<rel> paths per content mount, grouped by folder.
local HELD_SOURCES = {
    Game = [[
        Bow/ITEM_Longbow_Garou Bow/ITEM_Longbow_Hunter Bow/ITEM_Longbow_Oak Bow/ITEM_Longbow_Ulvs Bow/ITEM_Longbow_Willow
        Bow/ITEM_Longbow_Wood Bow/ITEM_Shortbow_Hunter Bow/ITEM_Shortbow_Oak Bow/ITEM_Shortbow_Skeleton Bow/ITEM_Shortbow_WildScout
        Bow/ITEM_Shortbow_Willow Bow/ITEM_Shortbow_Wood
        Crossbow/ITEM_Crossbow_Blurite Crossbow/ITEM_Crossbow_Bronze Crossbow/ITEM_Crossbow_Dorgeshuun Crossbow/ITEM_Crossbow_Iron
        Crossbow/ITEM_Crossbow_Steel Crossbow/ITEM_Crossbow_Test
        Dagger/ITEM_Dagger_Bone Dagger/ITEM_Dagger_Bronze Dagger/ITEM_Dagger_DragonboneBone Dagger/ITEM_Dagger_Iron
        Dagger/ITEM_Dagger_Steel Dagger/ITEM_Dagger_Stone Dagger/ITEM_Dagger_Wolfbane
        GreatAxe/ITEM_GreatAxe_Iron GreatAxe/ITEM_GreatAxe_Steel GreatAxe/ITEM_GreatAxe_Thane
        Greatsword/ITEM_GreatSword_Bronze Greatsword/ITEM_GreatSword_Iron Greatsword/ITEM_GreatSword_Shadow Greatsword/ITEM_GreatSword_Steel
        Mace/ITEM_Club_Bone Mace/ITEM_Club_Stone Mace/ITEM_Club_SwingSlash Mace/ITEM_Club_Wood Mace/ITEM_Club_ZombieAxe
        Mace/ITEM_Mace_Bronze Mace/ITEM_Mace_Iron Mace/ITEM_Mace_Skullsplitter Mace/ITEM_Mace_Steel
        Scimitar/ITEM_Scimitar_Imaru Scimitar/ITEM_Scimitar_Steel
        Shield/ITEM_Masterworks_Shield_Anti_Dragon Shield/ITEM_Masterworks_Shield_Dragonfire Shield/ITEM_Masterworks_Shield_Dragonfire_Imaru
        Shield/ITEM_Shield_Bronze Shield/ITEM_Shield_Iron Shield/ITEM_Shield_Leather Shield/ITEM_Shield_Skeleton Shield/ITEM_Shield_Steel
        Shield/ITEM_Shield_Wood
        Staff/ITEM_Staff_Ash Staff/ITEM_Staff_Battlestaff Staff/ITEM_Staff_Draconic Staff/ITEM_Staff_Garou Staff/ITEM_Staff_Necromancer
        Staff/ITEM_Staff_Oak Staff/ITEM_Staff_Splitbark
        Sword/ITEM_Sword_Bronze Sword/ITEM_Sword_Chieftans Sword/ITEM_Sword_Iron Sword/ITEM_Sword_Steel Sword/ITEM_Sword_Training
        UniqueWeapons/Club/AbyssalWhip/ITEM_Club_AbyssalWhip UniqueWeapons/Club/AbyssalWhip/ITEM_Club_AbyssalWhip_Masterwork
        UniqueWeapons/Hammer/GraniteMaul/ITEM_Hammer_GraniteMaul UniqueWeapons/Shortbow/CrystalBow/ITEM_Shortbow_CrystalBow
        UniqueWeapons/Staff/StaffOfLight/ITEM_Staff_StaffOfLight
        Wand/ITEM_Wand_Ancestral Wand/ITEM_Wand_Ash Wand/ITEM_Wand_Blightwood Wand/ITEM_Wand_KuldrasWrath Wand/ITEM_Wand_Maple
        Wand/ITEM_Wand_Master Wand/ITEM_Wand_Oak Wand/ITEM_Wand_Splitbark
    ]],
    DowdunReach = [[
        Bow/ITEM_Longbow_Maple Bow/ITEM_Shortbow_Maple Crossbow/ITEM_Crossbow_Black Crossbow/ITEM_Crossbow_Mithril
        Dagger/ITEM_Dagger_Mithril GreatAxe/ITEM_GreatAxe_Black GreatAxe/ITEM_GreatAxe_Mithril Greatsword/ITEM_GreatSword_Mithril
        Greatsword/ITEM_Masterworks_GreatSword_TitansWrath Mace/ITEM_Mace_Mithril Mace/ITEM_Mace_ZombieClub
        Scimitar/ITEM_Scimitar_Mithril Shield/ITEM_Shield_Black Shield/ITEM_Shield_Mithril Staff/ITEM_Masterwork_Staff_Zamorak
        Staff/ITEM_Staff_Maple Staff/ITEM_Staff_Subjugation Sword/ITEM_Sword_Black Sword/ITEM_Sword_Mithril
    ]],
    ScornedWilderness = [[
        Bow/ITEM_Longbow_MagicWood Bow/ITEM_Shortbow_MagicWood Crossbow/ITEM_Crossbow_Dragon Crossbow/ITEM_Crossbow_Rune
        Dagger/ITEM_Dagger_Rune GreatAxe/ITEM_Greataxe_Rune Greatsword/ITEM_Greatsword_Rune Mace/ITEM_Mace_Rune
        Scimitar/ITEM_Scimitar_Dragon Scimitar/ITEM_Scimitar_Rune Shield/ITEM_Shield_Dragon Shield/ITEM_Shield_Rune
        Staff/ITEM_Staff_Ancestral Sword/ITEM_Sword_Rune
    ]],
    UmbralSands = [[
        Bow/ITEM_Longbow_BowofElidinis Bow/ITEM_Longbow_Yew Bow/ITEM_Shortbow_Yew Crossbow/ITEM_Crossbow_Adamant
        Dagger/ITEM_Dagger_Adamant Dagger/ITEM_Dagger_Keris GreatAxe/ITEM_GreatAxe_Adamant Greatsword/ITEM_GreatSword_Adamant
        Mace/ITEM_Mace_Adamant ScarabStaff/ITEM_ScarabStaff Scimitar/ITEM_Scimitar_Adamant Shield/ITEM_Shield_Adamant
        Shield/ITEM_Shield_FuzanDragonfireShield Shield/ITEM_Shield_ToktzKetXil Staff/ITEM_Staff_Master
        Staff/ITEM_Staff_PharaohsSceptre Staff/ITEM_Staff_ToktzMejTal Sword/ITEM_Sword_Adamant Sword/ITEM_Sword_ToktzXilAk
    ]],
}

local SOURCES = {
    Head = {
        DowdunReach = [[
            ITEM_Armour_Head_ChickenHat ITEM_Armour_T6_Head_Black ITEM_Armour_T6_Head_BlackRanger ITEM_Armour_T6_Head_BlueDragonhide ITEM_Armour_T6_Head_Mithril
            ITEM_Armour_T6_Head_MithrilMed ITEM_Armour_T6_Head_Mystic ITEM_Armour_T6_Head_Zamorak
        ]],
        Fishing = [[
            ITEM_Armour_Head_AnglersHat
        ]],
        Game = [[
            ITEM_Armour_Head_BagOfNoggin ITEM_Armour_Head_ChefsHat ITEM_Armour_Head_EarlyAdopter ITEM_Armour_Head_SpectralBagOfNoggin
            ITEM_Armour_T2_Head_FarmersHat ITEM_Armour_T2_Head_Leather ITEM_Armour_T2_Head_Linen ITEM_Armour_T2_Head_Reinforced ITEM_Armour_T3_Head_BlackMed
            ITEM_Armour_T3_Head_Bronze ITEM_Armour_T3_Head_BronzeMed ITEM_Armour_T3_Head_HardLeather ITEM_Armour_T3_Head_WhiteMed ITEM_Armour_T3_Head_Wizard
            ITEM_Armour_T4_Head_DarkMage ITEM_Armour_T4_Head_DragonkinMage ITEM_Armour_T4_Head_Iron ITEM_Armour_T4_Head_IronMed ITEM_Armour_T4_Head_Paladin
            ITEM_Armour_T4_Head_StuddedLeather ITEM_Armour_T4_Head_WildArcher ITEM_Armour_T5_Head_GreenDragonHide ITEM_Armour_T5_Head_Necromancer
            ITEM_Armour_T5_Head_Ranger ITEM_Armour_T5_Head_Skeleton ITEM_Armour_T5_Head_SkeletonRanger ITEM_Armour_T5_Head_Splitbark ITEM_Armour_T5_Head_Steel
            ITEM_Armour_T5_Head_SteelMed ITEM_Armour_T5_Head_White
        ]],
        ScornedWilderness = [[
            ITEM_Armour_T1_Head_GildedPaladin ITEM_Armour_T8_Head_Ancestral ITEM_Armour_T8_Head_BlackDragon ITEM_Armour_T8_Head_DragonArmour
            ITEM_Armour_T8_Head_DragonMed ITEM_Armour_T8_Head_Rune ITEM_Armour_T8_Head_RuneMed
        ]],
        UmbralSands = [[
            ITEM_Armour_T7_Head_Adamant ITEM_Armour_T7_Head_AdamantMed ITEM_Armour_T7_Head_Desert ITEM_Armour_T7_Head_Infinity
            ITEM_Armour_T7_Head_KalphiteCarapace ITEM_Armour_T7_Head_LunarGarouMage ITEM_Armour_T7_Head_ObsidianHelmet ITEM_Armour_T7_Head_RedDragon
        ]],
    },
    Body = {
        DowdunReach = [[
            ITEM_Armour_T6_Body_Black ITEM_Armour_T6_Body_BlackRanger ITEM_Armour_T6_Body_BlueDragonHide ITEM_Armour_T6_Body_Mithril ITEM_Armour_T6_Body_Mystic
            ITEM_Armour_T6_Body_Zamorak
        ]],
        Game = [[
            ITEM_Armour_T1_Body_Adventurers ITEM_Armour_T2_Body_Leather ITEM_Armour_T2_Body_Linen ITEM_Armour_T2_Body_Reinforced ITEM_Armour_T3_Body_Bronze
            ITEM_Armour_T3_Body_HardLeather ITEM_Armour_T3_Body_Wizard ITEM_Armour_T4_Body_DarkMage ITEM_Armour_T4_Body_DragonkinMage ITEM_Armour_T4_Body_Iron
            ITEM_Armour_T4_Body_Paladin ITEM_Armour_T4_Body_StuddedLeather ITEM_Armour_T4_Body_WildArcher ITEM_Armour_T5_Body_GreenDragonHide
            ITEM_Armour_T5_Body_Necromancer ITEM_Armour_T5_Body_Ranger ITEM_Armour_T5_Body_Skeleton ITEM_Armour_T5_Body_Splitbark ITEM_Armour_T5_Body_Steel
            ITEM_Armour_T5_Body_White
        ]],
        ScornedWilderness = [[
            ITEM_Armour_T1_Body_GildedPaladin ITEM_Armour_T8_Body_Ancestral ITEM_Armour_T8_Body_BlackDragon ITEM_Armour_T8_Body_DragonArmour
            ITEM_Armour_T8_Body_Rune
        ]],
        UmbralSands = [[
            ITEM_Armour_T7_Body_Adamant ITEM_Armour_T7_Body_Desert ITEM_Armour_T7_Body_Infinity ITEM_Armour_T7_Body_KalphiteCarapace
            ITEM_Armour_T7_Body_LunarGarouMage ITEM_Armour_T7_Body_Obsidian ITEM_Armour_T7_Body_RedDragon
        ]],
    },
    Legs = {
        DowdunReach = [[
            ITEM_Armour_T6_Legs_Black ITEM_Armour_T6_Legs_BlackRanger ITEM_Armour_T6_Legs_BlueDragonhide ITEM_Armour_T6_Legs_Mithril ITEM_Armour_T6_Legs_Mystic
            ITEM_Armour_T6_Legs_Zamorak
        ]],
        Game = [[
            ITEM_Armour_T1_Legs_Adventurers ITEM_Armour_T1_Legs_Lightness ITEM_Armour_T2_Legs_Leather ITEM_Armour_T2_Legs_Linen ITEM_Armour_T2_Legs_Reinforced
            ITEM_Armour_T3_Legs_Bronze ITEM_Armour_T3_Legs_HardLeather ITEM_Armour_T3_Legs_Wizard ITEM_Armour_T4_Legs_DarkMage
            ITEM_Armour_T4_Legs_DragonkinMage ITEM_Armour_T4_Legs_Iron ITEM_Armour_T4_Legs_Paladin ITEM_Armour_T4_Legs_StuddedLeather
            ITEM_Armour_T4_Legs_WildArcher ITEM_Armour_T5_Legs_GreenDragonHide ITEM_Armour_T5_Legs_Necromancer ITEM_Armour_T5_Legs_Ranger
            ITEM_Armour_T5_Legs_Skeleton ITEM_Armour_T5_Legs_Splitbark ITEM_Armour_T5_Legs_Steel ITEM_Armour_T5_Legs_White
        ]],
        ScornedWilderness = [[
            ITEM_Armour_T1_Legs_GildedPaladin ITEM_Armour_T8_Legs_Ancestral ITEM_Armour_T8_Legs_BlackDragon ITEM_Armour_T8_Legs_DragonArmour
            ITEM_Armour_T8_Legs_Rune
        ]],
        UmbralSands = [[
            ITEM_Armour_T7_Legs_Adamant ITEM_Armour_T7_Legs_Desert ITEM_Armour_T7_Legs_Infinity ITEM_Armour_T7_Legs_KalphiteCarapace
            ITEM_Armour_T7_Legs_LunarGarouMage ITEM_Armour_T7_Legs_Obsidian ITEM_Armour_T7_Legs_RedDragon
        ]],
    },
    Cape = {
        Agility = [[
            ITEM_Cape_Skillcape_Agility ITEM_Cape_Trimmed_Skillcape_Agility RegionCapes/Brynmoor/Bramblemead/ITEM_Cape_Bramblemead_Golden
            RegionCapes/Brynmoor/Whispering/ITEM_Cape_Whispering_Golden RegionCapes/DowdunReach/ITEM_Cape_DowdunReach_Golden
            RegionCapes/Fellhollow/ITEM_Cape_Fellhollow_Golden RegionCapes/Ghornfell/Bloodblight/ITEM_Cape_Bloodblight_Golden
            RegionCapes/Ghornfell/Fractured/ITEM_Cape_Fractured_Golden RegionCapes/Ghornfell/Stormtouched/ITEM_Cape_Stormtouched_Golden
            RegionCapes/ScornedWilderness/ITEM_Cape_ScornedWilderness_Golden RegionCapes/UmbralSands/ITEM_Cape_UmbralSands_Golden
        ]],
        DowdunReach = [[
            ITEM_Cape_BlueDyad ITEM_Cape_BlueHex ITEM_Cape_DowdunReach ITEM_Cape_GreenDyad ITEM_Cape_GreenHex ITEM_Cape_PinkDyad ITEM_Cape_PinkHex
            ITEM_Cape_RedDyad ITEM_Cape_RedHex ITEM_Cape_YellowDyad ITEM_Cape_YellowHex ITEM_Cape_Zamorak
        ]],
        Fishing = [[
            ITEM_Cape_Skillcape_Fishing ITEM_Cape_Trimmed_Skillcape_Fishing
        ]],
        Game = [[
            ITEM_Cape_Adventurers_Black ITEM_Cape_Adventurers_Blue ITEM_Cape_Adventurers_Green ITEM_Cape_Adventurers_Orange ITEM_Cape_Adventurers_Pink
            ITEM_Cape_Adventurers_Purple ITEM_Cape_Adventurers_Red ITEM_Cape_Adventurers_White ITEM_Cape_Adventurers_Yellow ITEM_Cape_AlphaTest
            ITEM_Cape_Artisan ITEM_Cape_Attack ITEM_Cape_Avas_Accumulator ITEM_Cape_Avas_Attractor ITEM_Cape_Bloodblight ITEM_Cape_Bramblemead
            ITEM_Cape_Chinchompa ITEM_Cape_Community ITEM_Cape_Construction ITEM_Cape_Cooking ITEM_Cape_EarlyAdopter ITEM_Cape_Fellhollow
            ITEM_Cape_Fractured ITEM_Cape_Garou ITEM_Cape_Goblin ITEM_Cape_Lumber_Backpack ITEM_Cape_Mining ITEM_Cape_Runecrafting
            ITEM_Cape_Saradominist ITEM_Cape_Skeleton ITEM_Cape_Skillcape_Artisan ITEM_Cape_Skillcape_Attack ITEM_Cape_Skillcape_Construction
            ITEM_Cape_Skillcape_Cooking ITEM_Cape_Skillcape_Farming ITEM_Cape_Skillcape_Magic ITEM_Cape_Skillcape_Mining ITEM_Cape_Skillcape_Ranged
            ITEM_Cape_Skillcape_Runecrafting ITEM_Cape_Skillcape_Woodcutting ITEM_Cape_Stormtouched ITEM_Cape_Tattered ITEM_Cape_Trimmed_Skillcape_Artisan
            ITEM_Cape_Trimmed_Skillcape_Attack ITEM_Cape_Trimmed_Skillcape_Construction ITEM_Cape_Trimmed_Skillcape_Cooking ITEM_Cape_Trimmed_Skillcape_Farming
            ITEM_Cape_Trimmed_Skillcape_Magic ITEM_Cape_Trimmed_Skillcape_Mining ITEM_Cape_Trimmed_Skillcape_Ranged ITEM_Cape_Trimmed_Skillcape_Runecrafting
            ITEM_Cape_Trimmed_Skillcape_Woodcutting ITEM_Cape_Whispering ITEM_Cape_Woodcutting
        ]],
        ScornedWilderness = [[
            ITEM_Cape_Dragonslayer ITEM_Cape_GildedPaladin
        ]],
        UmbralSands = [[
            ITEM_Cape_Fire ITEM_Cape_MenaphiteCape_Black ITEM_Cape_MenaphiteCape_Blue ITEM_Cape_MenaphiteCape_Green ITEM_Cape_MenaphiteCape_Orange
            ITEM_Cape_MenaphiteCape_Pink ITEM_Cape_MenaphiteCape_Purple ITEM_Cape_MenaphiteCape_Red ITEM_Cape_MenaphiteCape_White ITEM_Cape_MenaphiteCape_Yellow
            ITEM_Cape_Obsidian ITEM_Cape_UmbralSands
        ]],
    },
}

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function textOf(value)
    local ok, s = pcall(function() return value:ToString() end)
    if ok and type(s) == 'string' then return s end
    return nil
end

local function pretty(id)
    local s = id:gsub('^ITEM_Armour_', ''):gsub('^ITEM_Cape_', 'Cape_'):gsub('^ITEM_', '')
    s = s:gsub('^T%d+_', ''):gsub('^Head_', ''):gsub('^Body_', ''):gsub('^Legs_', '')
    return (s:gsub('_', ' '):gsub('(%l)(%u)', '%1 %2'))
end

function C.excluded(id)
    for _, word in ipairs(EXCLUDE) do
        if id:find(word, 1, true) then return true end
    end
    return false
end

-- Weapon category from a path below Equipment/Held/, e.g. "Sword/ITEM_Sword_Rune".
local function categoryOf(rel)
    local first, second = rel:match('^([%w_]+)/([%w_]+)')
    if not first then return nil end
    local category
    if first == 'UniqueWeapons' then category = UNIQUE_ALIAS[second] or second
    else category = CATEGORY_ALIAS[first] or first end
    return WEAPON_CATEGORIES[category] and category or nil
end

-- Slot key for a loaded HeldEquipmentData, or nil if it is not a weapon we dress.
function C.heldKey(data)
    if not valid(data) then return nil end
    local rel = full(data):match('/Equipment/Held/(.+)$')
    local category = rel and categoryOf(rel)
    return category and C.HELD_PREFIX .. category or nil
end

function C.isHeld(key) return key ~= nil and key:sub(1, #C.HELD_PREFIX) == C.HELD_PREFIX end

local byId = {}
local function addEntry(key, entry)
    C[key] = C[key] or {}
    C[key][#C[key] + 1] = entry
    byId[key .. '|' .. entry.id] = entry
end

for slot, mounts in pairs(SOURCES) do
    C[slot] = {}
    for mount, raw in pairs(mounts) do
        for rel in raw:gmatch('%S+') do
            local id = rel:match('([^/]+)$')
            addEntry(slot, {
                id = id, slot = slot, name = pretty(id),
                path = '/' .. mount .. EQUIPMENT .. slot .. '/' .. rel .. '.' .. id,
                restricted = C.excluded(id),
            })
        end
    end
end

for mount, raw in pairs(HELD_SOURCES) do
    for rel in raw:gmatch('%S+') do
        local id = rel:match('([^/]+)$')
        local category = categoryOf(rel)
        if category then
            local key = C.HELD_PREFIX .. category
            addEntry(key, {
                id = id, slot = key, name = pretty(id), held = true,
                path = '/' .. mount .. EQUIPMENT .. 'Held/' .. rel .. '.' .. id,
                restricted = C.excluded(id),
            })
        end
    end
end

-- Picks up wearables and weapons that later game patches add, as long as the
-- game has loaded them (crafting recipes reference every craftable item).
local discovered = false
local function discover()
    if discovered then return end
    discovered = true
    for _, obj in ipairs(FindAllOf('WearableEquipmentData') or {}) do
        local path = full(obj):match('^%S+%s+(.+)$')
        local slot = path and path:match(EQUIPMENT .. '(%a+)/')
        local id = path and path:match('%.([%w_]+)$')
        if slot and SOURCES[slot] and id and id:match('^ITEM_') and not byId[slot .. '|' .. id] then
            addEntry(slot, { id = id, slot = slot, name = pretty(id), path = path, restricted = C.excluded(id) })
        end
    end
    for _, obj in ipairs(FindAllOf('HeldEquipmentData') or {}) do
        local path = full(obj):match('^%S+%s+(.+)$')
        local key = C.heldKey(obj)
        local id = path and path:match('%.([%w_]+)$')
        if key and id and id:match('^ITEM_') and not byId[key .. '|' .. id] then
            addEntry(key, { id = id, slot = key, name = pretty(id), path = path, held = true, restricted = C.excluded(id) })
        end
    end
end

function C.find(key, id)
    if not key or not id then return nil end
    local entry = byId[key .. '|' .. id]
    if not entry and not discovered then
        -- Another player may wear something this build's list does not know yet.
        discover()
        entry = byId[key .. '|' .. id]
    end
    return entry
end

-- Game objects are never kept between calls. The engine unloads assets and
-- widgets that nothing of its own references, and a Lua table does not count:
-- a cached object can be freed memory by the next use, and touching it
-- crashes the game natively (dumps 2026-09-30 15:57 to 18:50: an icon texture
-- cached here and a weapon template cached in held.lua). Caches hold object
-- paths (strings); the object is looked up again, by path, each time.

-- "Class /Path.To:Object" -> "/Path.To:Object", usable with StaticFindObject.
local function pathOf(o) return (full(o):match('^%S+%s+(.+)$')) or '' end
C.pathOf = pathOf

-- The live object at `path`: found if loaded, else loaded. nil if neither.
function C.resolve(path)
    if type(path) ~= 'string' or path == '' then return nil end
    local ok, obj = pcall(StaticFindObject, path)
    if ok and valid(obj) then return obj end
    local okL, loaded = pcall(LoadAsset, path)
    if okL and valid(loaded) then return loaded end
    ok, obj = pcall(StaticFindObject, path)
    if ok and valid(obj) then return obj end
    return nil
end

-- Returns the loaded WearableEquipmentData / HeldEquipmentData for an entry, or nil.
-- Looked up by path on every call (see above); only the path is kept.
function C.load(entry)
    if not entry or entry.missing then return nil end
    local class = entry.held and '/Script/Dominion.HeldEquipmentData' or '/Script/Dominion.WearableEquipmentData'
    local asset = C.resolve(entry.path)
    if asset and get(function() return asset:IsA(class) end) == true then return asset end
    entry.missing = true
    return nil
end

-- Item icons are soft references; UE4SS exposes their path differently
-- between builds, so try the known layouts and give up quietly.
local function iconPath(soft)
    local layouts = {
        function() return soft.ObjectID.AssetPath end,
        function() return soft.AssetPath end,
        function() return soft:get().AssetPath end,
    }
    for _, read in ipairs(layouts) do
        local ok, assetPath = pcall(read)
        if ok and assetPath then
            local packageName = textOf(assetPath.PackageName)
            local assetName = textOf(assetPath.AssetName)
            if packageName and assetName and assetName ~= 'None' and packageName ~= '' then
                return packageName .. '.' .. assetName
            end
        end
    end
    return nil
end

local function kismet()
    return StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
end

-- Path of an item data asset's icon texture (a string), or nil.
local iconWarned = false
local function findIconPath(asset)
    local okSoft, soft = pcall(function() return asset.Icon end)
    if not okSoft or soft == nil then return nil end
    local path = iconPath(soft)
    if not path then
        local ok, s = pcall(function() return kismet():Conv_SoftObjectReferenceToString(soft):ToString() end)
        if ok and type(s) == 'string' and s ~= '' and s ~= 'None' then path = s end
    end
    if path and C.resolve(path) then return path end
    local ok, tex = pcall(function() return kismet():LoadAsset_Blocking(soft) end)
    if ok and valid(tex) then
        local p = pathOf(tex)
        if p ~= '' then return p end
    end
    if not iconWarned then
        iconWarned = true
        print(string.format('[RSE-Transmog] icons unavailable (soft=%s, path=%s)', tostring(soft), tostring(path)) .. '\n')
    end
    return nil
end

-- Icon texture PATH of any loaded item data asset (cached per asset path), or nil.
local iconCache = {} -- item data path -> icon texture path, or false
function C.iconPathOf(asset)
    if not valid(asset) then return nil end
    local key = pathOf(asset)
    if key == '' then return nil end
    if iconCache[key] == nil then iconCache[key] = findIconPath(asset) or false end
    return iconCache[key] or nil
end

-- Icon texture of an item data asset, looked up fresh (never cached), or nil.
function C.iconOf(asset)
    return C.resolve(C.iconPathOf(asset))
end

-- Loads names, icons and ownership restrictions for one slot, once.
local prepared = {}
function C.prepare(slot)
    discover()
    if prepared[slot] then return C[slot] end
    prepared[slot] = true
    local keep = {}
    for _, entry in ipairs(C[slot] or {}) do
        local asset = C.load(entry)
        if asset then
            local title = textOf(asset.Name)
            if title and title ~= '' then entry.name = title end
            entry.iconPath = C.iconPathOf(asset)
            pcall(function()
                local ent = asset.EntitlementRequiredToEquip
                if valid(ent) and not ent.bAutoUnlock then entry.restricted = true end
            end)
            keep[#keep + 1] = entry
        end
    end
    table.sort(keep, function(a, b) return a.name:lower() < b.name:lower() end)
    C[slot] = keep
    return keep
end

-- Maps each wearable and weapon to the recipe that crafts it. Recipes load
-- over time, so a miss rebuilds the map (at most every 5 seconds).
local recipes, recipesAt = nil, -math.huge
local function recipeFor(asset)
    local key = pathOf(asset)
    if (not recipes or not recipes[key]) and os.clock() - recipesAt >= 5 then
        recipesAt = os.clock()
        recipes = {}
        for _, recipe in ipairs(FindAllOf('RecipeData') or {}) do
            pcall(function()
                recipe.ItemsCreated:ForEach(function(_, element)
                    local item = element:get().ItemData
                    if valid(item) then recipes[pathOf(item)] = pathOf(recipe) end
                end)
            end)
        end
    end
    -- Only the recipe's path is kept; the recipe itself is looked up now.
    local recipePath = recipes and recipes[key]
    if not recipePath or recipePath == '' then return nil end
    local ok, recipe = pcall(StaticFindObject, recipePath)
    return ok and valid(recipe) and recipe or nil
end

-- Whether the character has access to a look: it has worn or held the item,
-- or has learned its recipe. Returns true, false, or nil when it cannot be
-- told yet (no recipe found and the item was never worn).
function C.known(entry, seen, progress)
    if not entry then return nil end
    if seen[entry.id] then return true end
    if entry.restricted or not progress then return false end
    local asset = C.load(entry)
    local recipe = asset and recipeFor(asset)
    if not recipe then return nil end
    local ok, result = pcall(function() return progress:IsRecipeUnlocked(recipe) end)
    if not ok then return nil end
    return result == true
end

-- Updates entry.unlocked (known looks only) for every entry of a slot key.
function C.refreshUnlocked(slot, seen, progress)
    for _, entry in ipairs(C[slot] or {}) do
        entry.unlocked = C.known(entry, seen, progress) == true
    end
end

-- Map load: the caches hold only paths, so this is belt and braces. The next
-- world may have different content loaded, and they are cheap to rebuild.
function C.forget()
    iconCache = {}
    recipes, recipesAt = nil, -math.huge
end

return C
