-- Wearable appearance catalogue.
-- Static list: every WearableEquipmentData found in game build CL-240163
-- (base game plus the DowdunReach, UmbralSands, ScornedWilderness, Agility and
-- Fishing content plugins). Items added by later patches are picked up at
-- runtime from loaded objects (see discover()).
local C = {}
local EQUIPMENT = '/Gameplay/Character/Player/Equipment/'

-- Paid, promotional or developer-only cosmetics are never offered unless the
-- character already owns them (has worn them). Keeps the mod within Nexus rules.
local EXCLUDE = { 'AlphaTest', 'EarlyAdopter', 'Community', 'GildedPaladin', '_DE_' }

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

local function valid(o) return o ~= nil and o:IsValid() end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function textOf(value)
    local ok, s = pcall(function() return value:ToString() end)
    if ok and type(s) == 'string' then return s end
    return nil
end

local function pretty(id)
    local s = id:gsub('^ITEM_Armour_', ''):gsub('^ITEM_Cape_', 'Cape_')
    s = s:gsub('^T%d+_', ''):gsub('^Head_', ''):gsub('^Body_', ''):gsub('^Legs_', '')
    return (s:gsub('_', ' '):gsub('(%l)(%u)', '%1 %2'))
end

function C.excluded(id)
    for _, word in ipairs(EXCLUDE) do
        if id:find(word, 1, true) then return true end
    end
    return false
end

local byId = {}
for slot, mounts in pairs(SOURCES) do
    C[slot] = {}
    for mount, raw in pairs(mounts) do
        for rel in raw:gmatch('%S+') do
            local id = rel:match('([^/]+)$')
            local entry = {
                id = id, slot = slot, name = pretty(id),
                path = '/' .. mount .. EQUIPMENT .. slot .. '/' .. rel .. '.' .. id,
                restricted = C.excluded(id),
            }
            C[slot][#C[slot] + 1] = entry
            byId[slot .. ':' .. id] = entry
        end
    end
end

function C.find(slot, id)
    return id and byId[slot .. ':' .. id] or nil
end

-- Picks up wearables that later game patches add, as long as the game has
-- loaded them (crafting recipes reference every craftable wearable).
local discovered = false
local function discover()
    if discovered then return end
    discovered = true
    for _, obj in ipairs(FindAllOf('WearableEquipmentData') or {}) do
        local path = full(obj):match('^%S+%s+(.+)$')
        local slot = path and path:match(EQUIPMENT .. '(%a+)/')
        local id = path and path:match('%.([%w_]+)$')
        if slot and C[slot] and id and id:match('^ITEM_') and not byId[slot .. ':' .. id] then
            local entry = { id = id, slot = slot, name = pretty(id), path = path, obj = obj, restricted = C.excluded(id) }
            C[slot][#C[slot] + 1] = entry
            byId[slot .. ':' .. id] = entry
        end
    end
end

-- Returns the loaded WearableEquipmentData for an entry, or nil.
function C.load(entry)
    if not entry then return nil end
    if valid(entry.obj) then return entry.obj end
    if entry.missing then return nil end
    local ok, asset = pcall(LoadAsset, entry.path)
    if ok and valid(asset) and asset:IsA('/Script/Dominion.WearableEquipmentData') then
        entry.obj = asset
        return asset
    end
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

local iconWarned = false
local function loadIcon(asset)
    local okSoft, soft = pcall(function() return asset.Icon end)
    if not okSoft or soft == nil then return nil end
    local path = iconPath(soft)
    if not path then
        local ok, s = pcall(function() return kismet():Conv_SoftObjectReferenceToString(soft):ToString() end)
        if ok and type(s) == 'string' and s ~= '' and s ~= 'None' then path = s end
    end
    if path then
        local ok, tex = pcall(LoadAsset, path)
        if ok and valid(tex) then return tex end
    end
    local ok, tex = pcall(function() return kismet():LoadAsset_Blocking(soft) end)
    if ok and valid(tex) then return tex end
    if not iconWarned then
        iconWarned = true
        print(string.format('[DragonwildsWardrobe] icons unavailable (soft=%s, path=%s)', tostring(soft), tostring(path)) .. '\n')
    end
    return nil
end

-- Loads names, icons and ownership restrictions for one slot, once.
local prepared = {}
function C.prepare(slot)
    discover()
    if prepared[slot] then return C[slot] end
    prepared[slot] = true
    local keep = {}
    for _, entry in ipairs(C[slot]) do
        local asset = C.load(entry)
        if asset then
            local title = textOf(asset.Name)
            if title and title ~= '' then entry.name = title end
            entry.icon = loadIcon(asset)
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

-- Maps each wearable to the recipe that crafts it.
local recipes
local function recipeFor(asset)
    if not recipes then
        recipes = {}
        for _, recipe in ipairs(FindAllOf('RecipeData') or {}) do
            pcall(function()
                recipe.ItemsCreated:ForEach(function(_, element)
                    local item = element:get().ItemData
                    if valid(item) then recipes[full(item)] = recipe end
                end)
            end)
        end
    end
    return recipes[full(asset)]
end

-- seen: set of ids the character has worn. Updates entry.unlocked for a slot.
function C.refreshUnlocked(slot, seen, progress)
    for _, entry in ipairs(C[slot]) do
        local unlocked = seen[entry.id] == true
        if not unlocked and progress and not entry.restricted then
            local recipe = recipeFor(entry.obj)
            if recipe then
                local ok, result = pcall(function() return progress:IsRecipeUnlocked(recipe) end)
                unlocked = ok and result == true
            end
        end
        entry.unlocked = unlocked
    end
end

return C
