-- Appearance override for the local character and, with multiplayer sync,
-- for other players who run the mod.
--
-- Armour: on clients, Current<Slot>Wearable is swapped to the chosen
-- appearance, the game's own OnRep visual refresh runs, and the real pointer
-- is written back in the same call. With authority (solo, listen host) the
-- look's mesh is put on the outfit mesh directly instead (see swapShow).
-- Equipment, stats, inventory and save data never change.
-- Weapons: see held.lua (real meshes stop drawing, local ghost meshes show
-- the chosen look). Everything here is local rendering on this machine; the
-- only thing shared with other players is the list of chosen ids (net.lua).
local C = require('catalog')
local S = require('store')
local Cfg = require('config')
local Hd = require('held')
local N = require('net')

local V = {
    SLOTS = { 'Head', 'Body', 'Legs', 'Cape' },
    HANDS = Hd.HANDS, -- tab slot -> 'Right' | 'Left'
    HIDDEN = S.HIDDEN,
    sel = {},         -- slot key -> nil | ITEM id | HIDDEN (persisted)
    seen = {},        -- ITEM id -> true (persisted)
    guard = false,    -- true while we call OnRep ourselves
}
local EMPTY = {}
local chars = {}       -- pawn full name -> character render state
local byEquipment = {} -- equipment component full name -> character render state

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function log(s) print('[RSE-Transmog] ' .. tostring(s) .. '\n') end
local function debug(s) if Cfg.Debug then log(s) end end
local function idOf(o) return full(o):match('%.([%w_]+)$') end

-- IsValid() still passes for actors being torn down (player leaving, world
-- change); calling into those can crash the game, so check both.
local function alive(actor)
    if not valid(actor) then return false end
    return get(function() return actor:IsActorBeingDestroyed() end) ~= true
end

-- --------------------------------------------------------------- context

-- The local controller is cached: FindAllOf walks every object, and on a
-- listen server the first PlayerController found may belong to a guest.
-- A scan that found nothing (dedicated server, loading screen) is repeated
-- at most every 3 s instead of every second.
local cachedPC, lastScan, scanGap = nil, -math.huge, 1
function V.localController()
    local now = os.clock()
    if alive(cachedPC) then
        -- A controller without a pawn may be the main menu's, still alive
        -- while the next world loads: look again, at most once a second.
        if now - lastScan < 1 or alive(get(function() return cachedPC:K2_GetPawn() end)) then return cachedPC end
    end
    cachedPC = nil
    if now - lastScan < scanGap then return nil end
    lastScan = now
    for _, pc in ipairs(FindAllOf('PlayerController') or {}) do
        if alive(pc) and get(function() return pc:IsLocalController() end) == true then
            cachedPC = pc
            break
        end
    end
    scanGap = cachedPC and 1 or 3
    return cachedPC
end

local function context()
    local pc = V.localController()
    if not pc then return nil end
    local pawn = get(function() return pc:K2_GetPawn() end)
    if not alive(pawn) then return nil end
    local equipment = get(function() return pawn:GetPlayerEquipmentComponent() end)
    if not valid(equipment) then return nil end
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

-- -------------------------------------------------------------- characters

local function newChar(pawn, equipment, isLocal)
    local eqName = full(equipment)
    local ch = {
        pawn = pawn, pawnName = full(pawn), equipment = equipment, eqName = eqName, isLocal = isLocal,
        -- This machine owns the character (solo, listen host, or a guest's pawn
        -- on the host). nil/false when unknown: the OnRep route, as before.
        authority = get(function() return pawn:HasAuthority() end) == true,
        sel = EMPTY,
        shown = {},       -- slot -> PATH of the appearance currently rendered by us (never the object)
        hidden = {},      -- slot -> true while we hide the slot
        sig = {},         -- slot -> mesh signature recorded after our last apply
        lastActual = {},  -- slot -> full name of the real equipped item
        retryAt = {},     -- slot -> earliest os.clock() for a watchdog re-apply
        applied = {},     -- slot -> selection value last rendered
        hands = { Right = Hd.newState(eqName), Left = Hd.newState(eqName) },
    }
    chars[ch.pawnName] = ch
    byEquipment[ch.eqName] = ch
    return ch
end

local function dropChar(ch)
    if alive(ch.pawn) then
        for _, state in pairs(ch.hands) do pcall(Hd.forget, state) end
    end
    chars[ch.pawnName] = nil
    if byEquipment[ch.eqName] == ch then byEquipment[ch.eqName] = nil end
end

-- ------------------------------------------------------------------ armour

local function meshName(component)
    if not valid(component) then return 'none' end
    local ok, mesh = pcall(function() return component:GetSkeletalMeshAsset() end)
    if not ok then ok, mesh = pcall(function() return component.SkeletalMesh end) end -- legacy field
    local visible = false
    pcall(function() visible = component:IsVisible() end)
    return (ok and full(mesh) or '?') .. '|' .. tostring(visible)
end

local function signature(equipment, slot)
    return meshName(equipment['Outfit' .. slot .. 'Mesh'])
end

-- Direct route: puts the look's mesh, materials and animation class on the
-- slot's outfit mesh component, the way syncPreview dresses the inventory
-- preview. No replicated field is written and no OnRep runs.
-- Unlike the OnRep route it does not redo the game's other per-item visuals
-- (MaterialSectionsToHide on the body, hair under helmets): those stay as the
-- real item set them.
local function directShow(ch, slot, appearance)
    local component = ch.equipment['Outfit' .. slot .. 'Mesh']
    if not valid(component) then return false, 'no outfit mesh' end
    local okBody, bodyType = pcall(function() return ch.pawn:GetPlayerCustomizationComponent():GetBodyType() end)
    if not okBody or bodyType == nil then return false, 'no body type' end
    return pcall(function()
        local mesh = appearance:GetSkeletalMesh(bodyType)
        if not valid(mesh) then error('no mesh for this body type') end
        if full(component:GetSkeletalMeshAsset()) ~= full(mesh) then component:SetSkeletalMeshAsset(mesh) end
        appearance:ApplyMaterialsToSkeletalMeshComponent(bodyType, component)
        local anim = get(function() return appearance:GetAnimBlueprintClass(bodyType) end)
        if valid(anim) and full(get(function() return component.AnimClass end)) ~= full(anim) then
            component:SetAnimInstanceClass(anim)
        end
    end)
end

-- Renders `appearance` in `slot` while keeping `actual` as the real item.
--
-- Two routes:
--  * Machine WITHOUT authority over the character (a client looking at its
--    own or anyone's pawn): Current<Slot>Wearable is swapped to the look, the
--    game's own OnRep_Current<Slot>Wearable visual refresh runs, and the real
--    pointer is written back in the same call. On a client OnRep is purely
--    the visual refresh of a replicated value, so this is the faithful route
--    (it also hides body sections and hair the way the game does).
--  * Machine WITH authority (solo, listen host): the same replicated field is
--    the server's real state, and its OnRep may do more than visuals there
--    (e.g. apply the fake item's effects). The direct route is used instead;
--    if it fails, the OnRep route below runs as before.
local function swapShow(ch, slot, appearance, actual)
    local equipment = ch.equipment
    if ch.authority then
        local ok, err = directShow(ch, slot, appearance)
        if ok then
            ch.shown[slot] = C.pathOf(appearance)
            return true
        end
        debug('direct ' .. slot .. ' failed, using the OnRep route: ' .. tostring(err))
    end
    local prop = 'Current' .. slot .. 'Wearable'
    -- The previous look is kept as a path and looked up now: a kept data asset
    -- can have been unloaded since (see catalog.lua).
    local previous = (ch.shown[slot] and C.resolve(ch.shown[slot])) or actual
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
    ch.shown[slot] = C.pathOf(appearance)
    return true
end

-- Head hiding reuses the game's own "hide helmet" visual path locally. The
-- replicated flag is restored immediately, so nothing is sent or saved.
-- This runs on every machine, authority included: bHideHeadWearable is the
-- player's own cosmetic "hide helmet" option (Server_UpdateHeadWearableHiddenState),
-- not an item, so its OnRep carries no item effects; it also shows the hair
-- the way the game does, which hiding the mesh alone would not.
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

local function hideSlot(ch, slot)
    if slot == 'Head' then renderHeadHidden(ch.equipment, true) end
    setMeshVisible(ch.equipment, slot, false)
    ch.hidden[slot] = true
end

local function unhideSlot(ch, slot)
    if not ch.hidden[slot] then return end
    ch.hidden[slot] = nil
    if slot == 'Head' then renderHeadHidden(ch.equipment, ch.equipment.bHideHeadWearable) end
    setMeshVisible(ch.equipment, slot, true)
end

-- Makes the rendered armour slot match ch.sel[slot]. force: re-run even if unchanged.
local function applyWearable(ch, slot, force)
    local equipment = ch.equipment
    local actual = equipment['Current' .. slot .. 'Wearable']
    local want = ch.sel[slot]
    ch.lastActual[slot] = full(actual)
    ch.applied[slot] = want

    if want ~= V.HIDDEN then unhideSlot(ch, slot) end
    if not valid(actual) then
        ch.shown[slot], ch.sig[slot] = nil, nil
        return true, 'empty'
    end

    if want == V.HIDDEN then
        if ch.shown[slot] and ch.shown[slot] ~= C.pathOf(actual) then
            swapShow(ch, slot, actual, actual)
        end
        hideSlot(ch, slot)
    else
        local appearance = actual
        if want then
            appearance = C.load(C.find(slot, want))
            if not appearance then return false, 'failed' end
        end
        local current = ch.shown[slot] or C.pathOf(actual)
        if force or ch.hidden[slot] or current ~= C.pathOf(appearance) then
            local ok, err = swapShow(ch, slot, appearance, actual)
            if not ok then
                log('apply ' .. slot .. ': ' .. tostring(err))
                return false, 'failed'
            end
        end
        if not want then ch.shown[slot] = nil end
    end
    ch.sig[slot] = want and signature(equipment, slot) or nil
    if Cfg.Debug then
        debug('apply ' .. slot .. '=' .. tostring(want) .. ' actual=' .. ch.lastActual[slot] .. (ch.isLocal and '' or ' (other player)'))
    end
    return true
end

-- One pass over a character: armour watchdog plus both hands.
local function tickChar(ch, now, onSeen)
    local equipment = ch.equipment
    for _, slot in ipairs(V.SLOTS) do
        local actual = equipment['Current' .. slot .. 'Wearable']
        local actualName = full(actual)
        if onSeen then
            local id = idOf(actual)
            if id then onSeen(id) end
        end
        local want = ch.sel[slot]
        if actualName ~= ch.lastActual[slot] then
            ch.shown[slot], ch.hidden[slot] = nil, nil
            if want then applyWearable(ch, slot, true)
            else ch.lastActual[slot], ch.applied[slot] = actualName, nil end
        elseif want ~= ch.applied[slot] then
            applyWearable(ch, slot, false)
        elseif want and ch.sig[slot] and now >= (ch.retryAt[slot] or 0)
            and signature(equipment, slot) ~= ch.sig[slot] then
            -- The game refreshed the slot on its own (load, respawn, co-op sync).
            ch.retryAt[slot] = now + 2
            debug('watchdog re-apply ' .. slot)
            applyWearable(ch, slot, true)
        end
    end
    for _, side in pairs(V.HANDS) do
        Hd.update(ch.hands[side], equipment, side, ch.sel, V.HIDDEN, onSeen)
    end
end

-- ------------------------------------------------------------ local player

local function localChar()
    local _, pawn = context()
    return pawn and chars[full(pawn)] or nil
end

local function save()
    if not V.guid then return false, 'noCharacter' end
    local ok, err = S.save(V.guid, { sel = V.sel, seen = V.seen })
    if not ok then log('save failed: ' .. tostring(err)) end
    return ok, err
end

-- Public: choose an appearance (nil = original, HIDDEN, or ITEM id) for a
-- slot key (Head/Body/Legs/Cape or Held:<Category>) and persist it.
function V.progress()
    local pc = V.localController()
    local progress = pc and get(function() return pc:GetProgressComponent() end)
    return valid(progress) and progress or nil
end

function V.set(key, value)
    if not V.guid then return false, 'noCharacter' end
    local ch = localChar()
    if not ch then return false, 'noCharacter' end
    -- Only looks the character has access to (recipe learned, or worn/held before).
    if value and value ~= V.HIDDEN and C.known(C.find(key, value), V.seen, V.progress()) ~= true then
        return false, 'notKnown'
    end
    local previous = V.sel[key]
    V.sel[key] = value
    local ok, err = true, nil
    if C.isHeld(key) then
        -- Weapon looks are built on the next game-thread tick (V.tick), not
        -- inside the UI click event.
        if Hd.blocked[value or ''] then
            V.sel[key] = previous
            return false, 'failed'
        end
    else
        ok, err = applyWearable(ch, key, false)
        if not ok then
            V.sel[key] = previous
            applyWearable(ch, key, true)
            return false, err
        end
    end
    save()
    N.publish(key, value)
    return true, err
end

function V.resetAll()
    if not V.guid then return false, 'noCharacter' end
    local keys = {}
    for key in pairs(V.sel) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        V.sel[key] = nil
        N.publish(key, nil)
    end
    local ch = localChar()
    if ch then
        for _, slot in ipairs(V.SLOTS) do applyWearable(ch, slot, false) end
    end
    save()
    return true
end

-- Real item in a wardrobe tab (armour slot or MainHand/OffHand), or nil.
-- For hands, also returns the slot key (Held:<Category>) of that item.
function V.actual(slot)
    local _, _, equipment = context()
    if not equipment then return nil end
    local side = V.HANDS[slot]
    if side then
        local key, data = Hd.currentKey(equipment, side)
        return data, key
    end
    local actual = equipment['Current' .. slot .. 'Wearable']
    return valid(actual) and actual or nil
end

-- Slot key a wardrobe tab edits right now (nil for an empty hand).
function V.keyFor(slot)
    if not V.HANDS[slot] then return slot end
    local _, key = V.actual(slot)
    return key
end

local function loadCharacter(pc)
    local guid = characterGuid(pc)
    if not guid then return false end
    if guid ~= V.guid then
        local data = S.load(guid)
        V.guid, V.sel, V.seen = guid, data.sel, data.seen
        debug('character ' .. guid:sub(1, 8) .. ' loaded')
        -- A weapon look that crashed the game last time is dropped from the choices.
        local dropped = false
        for key, value in pairs(V.sel) do
            if Hd.blocked[value] then V.sel[key], dropped = nil, true end
        end
        if dropped then S.save(guid, { sel = V.sel, seen = V.seen }) end
        V.pruned = false
    end
    return true
end

-- ----------------------------------------------------------- other players

local function remoteTick(pc, localPawnName, now)
    local world = get(function() return pc:GetWorld() end)
    local gameState = valid(world) and get(function() return world.GameState end) or nil
    local players = valid(gameState) and get(function() return gameState.PlayerArray end) or nil
    local present = {}
    local count = 0
    if players then pcall(function() count = #players end) end
    for i = 1, count do
        local ps = get(function() return players[i] end)
        if alive(ps) then
            local id = get(function() return ps.PlayerId end)
            local sel = type(id) == 'number' and N.remote[math.floor(id)] or nil
            local pawn = get(function() return ps.PawnPrivate end)
            if not valid(pawn) then pawn = get(function() return ps:GetPawn() end) end
            local pawnName = alive(pawn) and full(pawn) or nil
            if pawnName and pawnName ~= localPawnName then
                local ch = chars[pawnName]
                if not ch and sel and next(sel) ~= nil then
                    local equipment = get(function() return pawn:GetPlayerEquipmentComponent() end)
                    if valid(equipment) then ch = newChar(pawn, equipment, false) end
                end
                if ch then
                    present[pawnName] = true
                    ch.sel = sel or EMPTY
                    tickChar(ch, now)
                end
            end
        end
    end
    for name, ch in pairs(chars) do
        if not ch.isLocal and not present[name] then dropChar(ch) end
    end
end

-- Other players' looks are known, or other players are still dressed.
local function hasOthers()
    if next(N.remote) ~= nil then return true end
    for _, ch in pairs(chars) do
        if not ch.isLocal then return true end
    end
    return false
end

-- Runs every tick: a handful of property reads per dressed character, no
-- asset loading unless a slot actually needs to be re-rendered.
function V.tick()
    local pc, pawn, equipment = context()
    if not equipment then return end
    local pawnName = full(pawn)
    if pawnName ~= V.pawnName then
        for _, ch in pairs(chars) do
            if ch.isLocal then dropChar(ch) end
        end
        V.pawnName = pawnName
        V.guid = nil
    end
    if not V.guid and not loadCharacter(pc) then return end

    -- Once per character: drop saved looks the character provably has no
    -- access to (saved by an older version). "Can't tell yet" keeps the look.
    if not V.pruned then
        local progress = V.progress()
        if progress then
            V.pruned = true
            local dropped = {}
            for key, value in pairs(V.sel) do
                if value ~= V.HIDDEN and C.known(C.find(key, value), V.seen, progress) == false then
                    dropped[#dropped + 1] = key
                end
            end
            for _, key in ipairs(dropped) do
                debug('dropped ' .. key .. '=' .. V.sel[key] .. ': this character does not know that look')
                V.sel[key] = nil
            end
            if #dropped > 0 then save() end
        end
    end

    local ch = chars[pawnName]
    if not ch or ch.eqName ~= full(equipment) then
        if ch then dropChar(ch) end
        ch = newChar(pawn, equipment, true)
    end
    ch.sel = V.sel

    local now = os.clock()
    local newSeen = false
    tickChar(ch, now, function(id)
        if not V.seen[id] then V.seen[id], newSeen = true, true end
    end)
    if newSeen then save() end

    N.clientTick(pc, V.sel)
    -- Solo play, or nobody else shared a look: nothing to dress or drop.
    if Cfg.ShowOthers ~= false and hasOthers() then
        remoteTick(pc, pawnName, now)
    end
end

-- Instant re-apply when the game replicates an equipment refresh.
function V.hook()
    for _, slot in ipairs(V.SLOTS) do
        local fn = '/Script/Dominion.PlayerEquipmentComponent:OnRep_Current' .. slot .. 'Wearable'
        local ok, err = pcall(RegisterHook, fn, function() end, function(ctx)
            if V.guard then return end
            local ch = byEquipment[full(ctx:get())]
            if not ch or not ch.sel[slot] then return end
            ch.shown[slot], ch.hidden[slot] = nil, nil
            applyWearable(ch, slot, true)
        end)
        if not ok then debug('hook ' .. slot .. ' unavailable: ' .. tostring(err)) end
    end
    -- Held items: change events let held.lua skip its per-tick check.
    local okHeld, heldErr = pcall(Hd.hook)
    if not okHeld then debug('held hooks unavailable: ' .. tostring(heldErr)) end
    -- Recipes learned: refresh the wardrobe's unlock flags (the refresh on
    -- each tab switch stays as the safety net).
    for _, fn in ipairs({ 'BP_OnRecipesUnlocked', 'Client_OnRecipesUnlocked' }) do
        local ok, err = pcall(RegisterHook, '/Script/Dominion.ProgressComponent:' .. fn, function() end, function()
            C.recipesUnlocked()
        end)
        if not ok then debug('hook ' .. fn .. ' unavailable: ' .. tostring(err)) end
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
    -- The previews are remembered by path and looked up each time (never kept
    -- as objects, see catalog.lua); FindAllOf again only once one is gone.
    if not previews then
        previews = {}
        for _, found in ipairs(FindAllOf('PlayerCharacterPreview') or {}) do
            local p = C.pathOf(found)
            if p ~= '' then previews[#previews + 1] = p end
        end
    end
    for _, previewPath in ipairs(previews) do
        local preview = get(function() return StaticFindObject(previewPath) end)
        if not valid(preview) then previews = nil return end
        local key = full(preview)
        previewSig[key] = previewSig[key] or {}
        for _, slot in ipairs(V.SLOTS) do
            local component = preview[slot .. 'OutfitMeshComponent']
            local actual = equipment['Current' .. slot .. 'Wearable']
            local want = V.sel[slot]
            local touched = previewSig[key][slot] ~= nil
            -- Signature (strings only): choice, real item, body type, and what the
            -- preview draws after our last apply. Unchanged means nothing to do.
            local base = valid(actual) and (tostring(want) .. '|' .. full(actual) .. '|' .. tostring(bodyType)) or nil
            if valid(component) and base and (want or touched)
                and previewSig[key][slot] ~= base .. '|' .. meshName(component) then
                local ok, err = pcall(function()
                    if want == V.HIDDEN then
                        if component:IsVisible() then component:SetVisibility(false, true) end
                    else
                        local asset = want and C.load(C.find(slot, want)) or actual
                        local mesh = asset:GetSkeletalMesh(bodyType)
                        if full(component:GetSkeletalMeshAsset()) ~= full(mesh) then
                            component:SetSkeletalMeshAsset(mesh)
                        end
                        -- The signature changed: the materials may differ even on the same mesh.
                        asset:ApplyMaterialsToSkeletalMeshComponent(bodyType, component)
                        local visible = valid(mesh)
                        if component:IsVisible() ~= visible then component:SetVisibility(visible, true) end
                    end
                end)
                if ok then
                    previewSig[key][slot] = want and (base .. '|' .. meshName(component)) or nil
                else
                    debug('preview ' .. slot .. ': ' .. tostring(err))
                end
            end
        end
    end
end

-- Console diagnostics (transmog_status).
function V.describe(out)
    local pc, pawn, equipment = context()
    if not equipment then out('no local character') return end
    out('character ' .. tostring(V.guid) .. ', player id ' .. tostring(N.playerId(pc)))
    local keys = {}
    for key, value in pairs(V.sel) do keys[#keys + 1] = key .. '=' .. value end
    table.sort(keys)
    out('selection: ' .. (#keys > 0 and table.concat(keys, ' ') or '(original)'))
    for _, side in pairs(V.HANDS) do Hd.describe(equipment, side, V.sel, out) end
    local others = 0
    for _, ch in pairs(chars) do if not ch.isLocal then others = others + 1 end end
    out('other players dressed: ' .. others)
end

-- Map loads: drops every character and preview this module holds, without
-- touching them (they belong to the world being torn down; calling into them
-- crashes the game natively). Characters are found again after the load.
function V.forget()
    chars, byEquipment = {}, {}
    cachedPC, lastScan, scanGap = nil, -math.huge, 1
    previewSig, previews = {}, nil
end

return V
