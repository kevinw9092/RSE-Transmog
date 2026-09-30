-- Client-side appearance override for the local character.
--
-- Technique: Current<Slot>Wearable is swapped to the chosen appearance, the
-- game's own OnRep visual refresh runs, and the real pointer is written back
-- in the same call. Equipment, stats, inventory and save data never change,
-- nothing is sent to the server, and other players see the real gear.
local H = require('UEHelpers')
local C = require('catalog')
local S = require('store')
local Cfg = require('config')

local V = {
    SLOTS = { 'Head', 'Body', 'Legs', 'Cape' },
    HIDDEN = S.HIDDEN,
    sel = {},         -- slot -> nil | ITEM id | HIDDEN (persisted)
    seen = {},        -- ITEM id -> true (persisted)
    shown = {},       -- slot -> appearance object currently rendered by us
    hidden = {},      -- slot -> true while we hide the slot
    sig = {},         -- slot -> mesh signature recorded after our last apply
    lastActual = {},  -- slot -> full name of the real equipped item
    retryAt = {},     -- slot -> earliest os.clock() for a watchdog re-apply
    guard = false,    -- true while we call OnRep ourselves
}

local function valid(o) return o ~= nil and o:IsValid() end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function log(s) print('[DragonwildsWardrobe] ' .. tostring(s) .. '\n') end
local function debug(s) if Cfg.Debug then log(s) end end
local function idOf(o) return full(o):match('%.([%w_]+)$') end

local function context()
    local pc = H.GetPlayerController()
    if not valid(pc) then return nil end
    local pawn = pc:K2_GetPawn()
    if not valid(pawn) or not pawn:IsLocallyControlled() then return nil end
    local ok, equipment = pcall(function() return pawn:GetPlayerEquipmentComponent() end)
    if not ok or not valid(equipment) then return nil end
    return pc, pawn, equipment
end
V.context = context

local function characterGuid(pc)
    local ok, raw = pcall(function()
        local g = pc:GetCharacterGuid().InnerGuid
        return string.format('%08x%08x%08x%08x',
            g.A % 4294967296, g.B % 4294967296, g.C % 4294967296, g.D % 4294967296)
    end)
    if not ok or raw == string.rep('0', 32) then return nil end
    return raw
end

local function meshName(component)
    if not valid(component) then return 'none' end
    local ok, mesh = pcall(function() return component:GetSkeletalMeshAsset() end)
    if not ok then ok, mesh = pcall(function() return component.SkeletalMeshAsset end) end
    local visible = false
    pcall(function() visible = component:IsVisible() end)
    return (ok and full(mesh) or '?') .. '|' .. tostring(visible)
end

local function signature(equipment, slot)
    return meshName(equipment['Outfit' .. slot .. 'Mesh'])
end

-- Renders `appearance` in `slot` while keeping `actual` as the real item.
local function swapShow(equipment, slot, appearance, actual)
    local prop = 'Current' .. slot .. 'Wearable'
    local previous = V.shown[slot] or actual
    V.guard = true
    equipment[prop] = appearance
    local ok, err = pcall(function() equipment['OnRep_' .. prop](equipment, previous) end)
    equipment[prop] = actual
    V.guard = false
    if full(equipment[prop]) ~= full(actual) then
        -- Should never happen; refuse to continue rather than risk real data.
        return false, 'equipment pointer could not be restored'
    end
    if not ok then return false, tostring(err) end
    V.shown[slot] = appearance
    return true
end

-- Head hiding reuses the game's own "hide helmet" visual path locally. The
-- replicated flag is restored immediately, so nothing is sent or saved.
local function renderHeadHidden(equipment, hide)
    local real = equipment.bHideHeadWearable
    V.guard = true
    local ok, err = pcall(function()
        equipment.bHideHeadWearable = hide
        equipment:OnRep_HideHeadWearable(not hide)
    end)
    equipment.bHideHeadWearable = real
    V.guard = false
    return ok, err
end

local function setMeshVisible(equipment, slot, visible)
    local component = equipment['Outfit' .. slot .. 'Mesh']
    if valid(component) then
        pcall(function() component:SetVisibility(visible, true) end)
    end
end

local function hideSlot(equipment, slot)
    if slot == 'Head' then renderHeadHidden(equipment, true) end
    setMeshVisible(equipment, slot, false)
    V.hidden[slot] = true
end

local function unhideSlot(equipment, slot)
    if not V.hidden[slot] then return end
    V.hidden[slot] = nil
    if slot == 'Head' then renderHeadHidden(equipment, equipment.bHideHeadWearable) end
    setMeshVisible(equipment, slot, true)
end

-- Makes the rendered slot match V.sel[slot]. force: re-run even if unchanged.
function V.apply(slot, force)
    local _, _, equipment = context()
    if not equipment then return false, 'noCharacter' end
    local actual = equipment['Current' .. slot .. 'Wearable']
    local want = V.sel[slot]
    V.lastActual[slot] = full(actual)

    if want ~= V.HIDDEN then unhideSlot(equipment, slot) end
    if not valid(actual) then
        V.shown[slot], V.sig[slot] = nil, nil
        return true, 'empty'
    end

    if want == V.HIDDEN then
        if V.shown[slot] and V.shown[slot] ~= actual then
            swapShow(equipment, slot, actual, actual)
        end
        hideSlot(equipment, slot)
    else
        local appearance = actual
        if want then
            appearance = C.load(C.find(slot, want))
            if not appearance then return false, 'failed' end
        end
        local current = V.shown[slot] or actual
        if force or V.hidden[slot] or current ~= appearance then
            local ok, err = swapShow(equipment, slot, appearance, actual)
            if not ok then
                log('apply ' .. slot .. ': ' .. tostring(err))
                return false, 'failed'
            end
        end
        if not want then V.shown[slot] = nil end
    end
    V.sig[slot] = want and signature(equipment, slot) or nil
    debug('apply ' .. slot .. '=' .. tostring(want) .. ' actual=' .. V.lastActual[slot])
    return true
end

local function save()
    if not V.guid then return false, 'noCharacter' end
    local ok, err = S.save(V.guid, { sel = V.sel, seen = V.seen })
    if not ok then log('save failed: ' .. tostring(err)) end
    return ok, err
end

-- Public: choose an appearance (nil = original, HIDDEN, or ITEM id) and persist.
function V.set(slot, value)
    if not V.guid then return false, 'noCharacter' end
    local previous = V.sel[slot]
    V.sel[slot] = value
    local ok, err = V.apply(slot, false)
    if not ok then
        V.sel[slot] = previous
        V.apply(slot, true)
        return false, err
    end
    save()
    return true, err
end

function V.resetAll()
    if not V.guid then return false, 'noCharacter' end
    for _, slot in ipairs(V.SLOTS) do
        V.sel[slot] = nil
        V.apply(slot, false)
    end
    save()
    return true
end

function V.actual(slot)
    local _, _, equipment = context()
    if not equipment then return nil end
    local actual = equipment['Current' .. slot .. 'Wearable']
    return valid(actual) and actual or nil
end

local function loadCharacter(pc)
    local guid = characterGuid(pc)
    if not guid then return false end
    if guid ~= V.guid then
        local data = S.load(guid)
        V.guid, V.sel, V.seen = guid, data.sel, data.seen
        log('character ' .. guid:sub(1, 8) .. ' loaded')
    end
    return true
end

-- Runs every tick: a handful of property reads, no asset loading unless a
-- slot actually needs to be re-rendered.
function V.tick()
    local pc, pawn, equipment = context()
    if not equipment then return end
    local pawnName = full(pawn)
    if pawnName ~= V.pawnName then
        V.pawnName = pawnName
        V.shown, V.hidden, V.sig, V.lastActual = {}, {}, {}, {}
        V.guid = nil
    end
    if not V.guid and not loadCharacter(pc) then return end

    local now = os.clock()
    local newSeen = false
    for _, slot in ipairs(V.SLOTS) do
        local actual = equipment['Current' .. slot .. 'Wearable']
        local actualName = full(actual)
        local id = idOf(actual)
        if id and not V.seen[id] then V.seen[id], newSeen = true, true end

        if actualName ~= V.lastActual[slot] then
            V.shown[slot], V.hidden[slot] = nil, nil
            if V.sel[slot] then V.apply(slot, true) else V.lastActual[slot] = actualName end
        elseif V.sel[slot] and V.sig[slot] and now >= (V.retryAt[slot] or 0)
            and signature(equipment, slot) ~= V.sig[slot] then
            -- The game refreshed the slot on its own (load, respawn, co-op sync).
            V.retryAt[slot] = now + 2
            debug('watchdog re-apply ' .. slot)
            V.apply(slot, true)
        end
    end
    if newSeen then save() end
end

-- Instant re-apply when the game replicates an equipment refresh.
function V.hook()
    for _, slot in ipairs(V.SLOTS) do
        local fn = '/Script/Dominion.PlayerEquipmentComponent:OnRep_Current' .. slot .. 'Wearable'
        local ok, err = pcall(RegisterHook, fn, function() end, function(ctx)
            if V.guard or not V.sel[slot] then return end
            local _, _, equipment = context()
            if not equipment or full(ctx:get()) ~= full(equipment) then return end
            V.shown[slot], V.hidden[slot] = nil, nil
            V.apply(slot, true)
        end)
        if not ok then debug('hook ' .. slot .. ' unavailable: ' .. tostring(err)) end
    end
end

-- Inventory character preview: it renders from the real inventory, so the
-- chosen appearance is copied onto its outfit meshes while the menu is open.
local previewSig, previews = {}, nil
function V.syncPreview(forget)
    if forget then previewSig, previews = {}, nil return end
    local _, pawn, equipment = context()
    if not equipment then return end
    local okBody, bodyType = pcall(function() return pawn:GetPlayerCustomizationComponent():GetBodyType() end)
    if not okBody then return end
    previews = previews or FindAllOf('PlayerCharacterPreview') or {}
    for _, preview in ipairs(previews) do
        if not valid(preview) then previews = nil return end
        local key = full(preview)
        previewSig[key] = previewSig[key] or {}
        for _, slot in ipairs(V.SLOTS) do
            local component = preview[slot .. 'OutfitMeshComponent']
            local actual = equipment['Current' .. slot .. 'Wearable']
            local want = V.sel[slot]
            local touched = previewSig[key][slot] ~= nil
            if valid(component) and valid(actual) and (want or touched) then
                local ok, err = pcall(function()
                    if want == V.HIDDEN then
                        component:SetVisibility(false, true)
                    else
                        local asset = want and C.load(C.find(slot, want)) or actual
                        local mesh = asset:GetSkeletalMesh(bodyType)
                        local current = component:GetSkeletalMeshAsset()
                        if full(current) ~= full(mesh) or previewSig[key][slot] ~= full(asset) then
                            if not pcall(function() component:SetSkeletalMeshAsset(mesh) end) then
                                component:SetSkeletalMesh(mesh, true)
                            end
                            asset:ApplyMaterialsToSkeletalMeshComponent(bodyType, component)
                        end
                        component:SetVisibility(valid(mesh), true)
                    end
                end)
                if ok then
                    previewSig[key][slot] = want and (want == V.HIDDEN and 'hidden' or full(C.load(C.find(slot, want)))) or nil
                else
                    debug('preview ' .. slot .. ': ' .. tostring(err))
                end
            end
        end
    end
end

return V
