-- Appearance override for the local character and, with multiplayer sync,
-- for other players who run the mod.
--
-- Armour: Current<Slot>Wearable is swapped to the chosen appearance, the
-- game's own OnRep visual refresh runs, and the real pointer is written back
-- in the same call. Equipment, stats, inventory and save data never change.
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
local cachedPC, lastScan = nil, -math.huge
function V.localController()
    local now = os.clock()
    if alive(cachedPC) then
        -- A controller without a pawn may be the main menu's, still alive
        -- while the next world loads: look again, at most once a second.
        if now - lastScan < 1 or alive(get(function() return cachedPC:K2_GetPawn() end)) then return cachedPC end
    end
    cachedPC = nil
    if now - lastScan < 1 then return nil end
    lastScan = now
    for _, pc in ipairs(FindAllOf('PlayerController') or {}) do
        if alive(pc) and get(function() return pc:IsLocalController() end) == true then
            cachedPC = pc
            break
        end
    end
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
    local ch = {
        pawn = pawn, pawnName = full(pawn), equipment = equipment, eqName = full(equipment), isLocal = isLocal,
        sel = EMPTY,
        shown = {},       -- slot -> appearance object currently rendered by us
        hidden = {},      -- slot -> true while we hide the slot
        sig = {},         -- slot -> mesh signature recorded after our last apply
        lastActual = {},  -- slot -> full name of the real equipped item
        retryAt = {},     -- slot -> earliest os.clock() for a watchdog re-apply
        applied = {},     -- slot -> selection value last rendered
        hands = { Right = Hd.newState(), Left = Hd.newState() },
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
    if not ok then ok, mesh = pcall(function() return component.SkeletalMeshAsset end) end
    local visible = false
    pcall(function() visible = component:IsVisible() end)
    return (ok and full(mesh) or '?') .. '|' .. tostring(visible)
end

local function signature(equipment, slot)
    return meshName(equipment['Outfit' .. slot .. 'Mesh'])
end

-- Renders `appearance` in `slot` while keeping `actual` as the real item.
local function swapShow(ch, slot, appearance, actual)
    local equipment = ch.equipment
    local prop = 'Current' .. slot .. 'Wearable'
    local previous = ch.shown[slot] or actual
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
    ch.shown[slot] = appearance
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
        if ch.shown[slot] and ch.shown[slot] ~= actual then
            swapShow(ch, slot, actual, actual)
        end
        hideSlot(ch, slot)
    else
        local appearance = actual
        if want then
            appearance = C.load(C.find(slot, want))
            if not appearance then return false, 'failed' end
        end
        local current = ch.shown[slot] or actual
        if force or ch.hidden[slot] or current ~= appearance then
            local ok, err = swapShow(ch, slot, appearance, actual)
            if not ok then
                log('apply ' .. slot .. ': ' .. tostring(err))
                return false, 'failed'
            end
        end
        if not want then ch.shown[slot] = nil end
    end
    ch.sig[slot] = want and signature(equipment, slot) or nil
    debug('apply ' .. slot .. '=' .. tostring(want) .. ' actual=' .. ch.lastActual[slot] .. (ch.isLocal and '' or ' (other player)'))
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
        log('character ' .. guid:sub(1, 8) .. ' loaded')
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
                log('dropped ' .. key .. '=' .. V.sel[key] .. ': this character does not know that look')
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
    if Cfg.ShowOthers ~= false then
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

return V
