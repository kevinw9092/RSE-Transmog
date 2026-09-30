-- Weapon (held equipment) appearance.
--
-- Held items are replicated actors (PlayerEquipmentComponent's
-- HeldEquipmentActorRight/Left) whose meshes come from each weapon's
-- Blueprint (BP_Sword_Rune, ...). The real meshes are never swapped: they
-- only stop rendering, so their collision, sockets, animation and hit
-- detection keep working exactly as before. Local-only "ghost" mesh
-- components, copied from the chosen weapon's Blueprint templates, are
-- attached to the same actor in their place. Ghosts follow the real mesh's
-- visibility, so the game can still hide the weapon (emotes, climbing...).
--
-- Component discovery avoids TArray return values where it can (their Lua
-- shape differs between UE4SS builds): the real actor is walked through
-- GetNumChildrenComponents/GetChildComponent, and Blueprint templates are
-- looked up by their object path (<Class>:<Name>_GEN_VARIABLE).
local C = require('catalog')
local Cfg = require('config')
local S = require('store')

local Hd = { HANDS = { MainHand = 'Right', OffHand = 'Left' }, blocked = {} }

local MESH = '/Script/Engine.MeshComponent'
local STATIC = '/Script/Engine.StaticMeshComponent'
local SKELETAL = '/Script/Engine.SkeletalMeshComponent'
-- Meshes gameplay shows and hides on its own (loaded arrows, bolts, effects).
local SKIP = { 'projectile', 'arrow', 'bolt', 'ammo', 'fx', 'niagara', 'particle', 'trail' }
-- Names tried on the chosen weapon's Blueprint besides the real weapon's own.
local COMMON_NAMES = { 'Mesh', 'StaticMesh', 'SkeletalMesh', 'WeaponMesh', 'ItemMesh', 'EquipmentMesh',
    'StaticMeshComponent', 'SkeletalMeshComponent', 'Weapon', 'Blade', 'Head', 'Handle' }
local KEEP_RELATIVE, NO_COLLISION, ALWAYS_TICK_POSE = 0, 0, 0

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function path(o) return full(o):match('^%S+%s+(.+)$') or '' end
local function log(s) print('[RSE-Transmog] ' .. tostring(s) .. '\n') end
local function debug(s) if Cfg.Debug then log(s) end end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function nameOf(o)
    local s = get(function() return o:GetFName():ToString() end)
    return type(s) == 'string' and s or ''
end
local function str(v)
    if type(v) == 'string' then return v ~= '' and v ~= 'None' and v or nil end
    local s = get(function() return v:ToString() end)
    return (type(s) == 'string' and s ~= '' and s ~= 'None') and s or nil
end

-- ------------------------------------------------------------ crash guard
-- Building a look calls into the engine. A lock file names the look while
-- that happens; if the game dies mid-apply, the next launch finds the lock,
-- blocks that look for the session and says so, instead of crashing again.
local LOCK = 'weapon-apply.lock'

local function readLock()
    local f = io.open(S.file(LOCK), 'r')
    if not f then return nil end
    local id = f:read('l')
    f:close()
    pcall(os.remove, S.file(LOCK))
    return id
end

do
    local id = readLock()
    if id and id:match('^[%w_]+$') then
        Hd.blocked[id] = true
        log('the game closed while applying weapon look ' .. id .. '; that look is disabled for this session. '
            .. 'Please send UE4SS.log with your bug report (with Debug on, the "weapon:" lines above the crash name the step).')
    end
end

local function lock(id)
    local f = io.open(S.file(LOCK), 'w')
    if f then f:write(id, '\n') f:close() end
end
local function unlock() pcall(os.remove, S.file(LOCK)) end

-- Breadcrumbs (Debug): the last "weapon:" line before a crash names the step.
local function trace(s) debug('weapon: ' .. s) end

-- Looked up by path each time, never cached: a kept object can have been
-- unloaded by the next use (see catalog.lua, "Game objects are never kept").
local function class(p)
    local c = get(function() return StaticFindObject(p) end)
    return valid(c) and c or nil
end

local function alive(actor)
    if not valid(actor) then return false end
    return get(function() return actor:IsActorBeingDestroyed() end) ~= true
end

-- Elements of a TArray however this UE4SS build hands it to Lua
-- (Lua table, indexable userdata, or ForEach with element wrappers).
local function list(value)
    local out = {}
    if value == nil then return out end
    if type(value) == 'table' then
        for _, v in ipairs(value) do out[#out + 1] = v end
        return out
    end
    local n = get(function() return #value end)
    if type(n) == 'number' and n > 0 then
        for i = 1, n do
            local e = get(function() return value[i] end)
            if e ~= nil and get(function() return e:IsValid() end) == nil then
                e = get(function() return e:get() end)
            end
            if e ~= nil then out[#out + 1] = e end
        end
        if #out > 0 then return out end
    end
    pcall(function()
        value:ForEach(function(_, element)
            local e = get(function() return element:get() end)
            if e ~= nil then out[#out + 1] = e end
        end)
    end)
    return out
end
Hd.list = list

local function skipped(name)
    local lower = name:lower()
    for _, word in ipairs(SKIP) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

local function isMesh(comp) return get(function() return comp:IsA(MESH) end) == true end
local function isSkeletal(comp) return get(function() return comp:IsA(SKELETAL) end) == true end

local function meshAsset(comp)
    if isSkeletal(comp) then
        local m = get(function() return comp.SkeletalMeshAsset end)
        if not valid(m) then m = get(function() return comp:GetSkeletalMeshAsset() end) end
        if not valid(m) then m = get(function() return comp.SkeletalMesh end) end
        return valid(m) and m or nil
    end
    local m = get(function() return comp.StaticMesh end)
    return valid(m) and m or nil
end

-- ------------------------------------------------------------ real actor

-- Every scene component of an actor, root first, walked through the
-- attachment tree with scalar calls only.
local function actorComponents(actor)
    local out, seen = {}, {}
    local function walk(comp, depth)
        if not valid(comp) or depth > 8 then return end
        local key = full(comp)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = comp
        local n = get(function() return comp:GetNumChildrenComponents() end)
        if type(n) == 'number' and n > 0 then
            for i = 0, n - 1 do walk(get(function() return comp:GetChildComponent(i) end), depth + 1) end
        else
            for _, child in ipairs(list(get(function() return comp.AttachChildren end))) do walk(child, depth + 1) end
        end
    end
    walk(get(function() return actor:K2_GetRootComponent() end), 0)
    if #out <= 1 then
        -- Fallback: the engine's own component query.
        local cls = class(MESH)
        for _, comp in ipairs(list(get(function() return actor:K2_GetComponentsByClass(cls) end))) do
            if valid(comp) and not seen[full(comp)] then
                seen[full(comp)] = true
                out[#out + 1] = comp
            end
        end
    end
    return out
end

local function heldActor(equipment, side)
    local actor = get(function() return equipment['HeldEquipmentActor' .. side] end)
    if not valid(actor) then actor = get(function() return equipment['GetHeldEquipmentActor' .. side](equipment) end) end
    return valid(actor) and actor or nil
end

local function heldData(equipment, actor, side)
    local data = get(function() return actor.HeldEquipmentData end)
    if not valid(data) then data = get(function() return actor:GetHeldEquipmentData() end) end
    if not valid(data) then data = get(function() return equipment['GetHeldEquipmentData' .. side](equipment) end) end
    return valid(data) and data or nil
end
Hd.heldActor, Hd.heldData = heldActor, heldData

-- Real mesh components that currently make up the weapon's look.
local function realVisuals(actor)
    local out = {}
    for _, comp in ipairs(actorComponents(actor)) do
        if isMesh(comp) and not skipped(nameOf(comp)) and meshAsset(comp)
            and get(function() return comp:IsVisible() end) == true then
            out[#out + 1] = comp
        end
    end
    return out
end

-- --------------------------------------------------------------- templates

-- Weapon data -> Blueprint actor class.
--
-- NEVER read HeldEquipmentActorClass from Lua: it is a soft class reference,
-- and pushing it to Lua crashes UE4SS on this engine version (null memcpy in
-- push_softobjectproperty). The class is found instead from, in order:
--   1. classes learned from real weapon actors (persisted in saves\),
--   2. the naming rule Held/<folder>/ITEM_X -> Held/<folder>/BP_X.BP_X_C,
--      with the exceptions below (verified against the pak file listing).
local BP_EXCEPTIONS = {
    ITEM_Crossbow_Black = 'BP_Crossbow_BlackKnight',
    ITEM_Sword_Black = 'BP_Sword_BlackKnight',
    ITEM_Shortbow_Hunter = 'BP_Shortbow_Hunters',
    ITEM_Longbow_Hunter = 'BP_Longbow_Hunters',
    ITEM_Dagger_DragonboneBone = 'BP_Dagger_Dragonbone',
    ITEM_Masterworks_GreatSword_TitansWrath = 'BP_ITEM_Masterworks_GreatSword_TitansWrath',
    ITEM_Masterwork_Staff_Zamorak = 'BP_Staff_Zamorak',
    ITEM_Masterworks_Shield_Dragonfire_Imaru = 'BP_Shield_Imaru_Dragonfire',
    ITEM_Masterworks_Shield_Anti_Dragon = 'BP_Shield_Anti_Dragon',
    ITEM_Masterworks_Shield_Dragonfire = 'BP_Shield_Poison_Dragonfire',
    ITEM_Club_AbyssalWhip_Masterwork = 'BP_Club_AbyssalWhip',
    ITEM_ScarabStaff = 'BP_ScarabStaff_HeldItem',
}
local LEARNED = 'weapon-classes.txt'
local learned -- ITEM id -> class path

local function loadLearned()
    if learned then return learned end
    learned = {}
    local f = io.open(S.file(LEARNED), 'r')
    if f then
        for line in f:lines() do
            local id, p = line:match('^(ITEM_[%w_]+)=(/[%w_/%.]+)$')
            if id then learned[id] = p end
        end
        f:close()
    end
    return learned
end

-- Records the class of a real weapon actor, so its look always resolves exactly.
local function learn(data, actor)
    local id = full(data):match('%.([%w_]+)$')
    local p = path(get(function() return actor:GetClass() end))
    if not id or p == '' or not p:match('^/[%w_/%.]+$') then return end
    local known = loadLearned()
    if known[id] == p then return end
    known[id] = p
    local f = io.open(S.file(LEARNED), 'a')
    if f then f:write(id, '=', p, '\n') f:close() end
end

local function isClass(o) return valid(o) and get(function() return o:IsA('/Script/CoreUObject.Class') end) == true end

local function loadClass(p)
    local cls = get(function() return StaticFindObject(p) end)
    if isClass(cls) then return cls end
    local ok, loaded = pcall(LoadAsset, p)
    return ok and isClass(loaded) and loaded or nil
end

local function actorClassOf(data)
    local dataPath = path(data)
    local id = dataPath:match('%.([%w_]+)$')
    if not id then return nil end
    local p = loadLearned()[id]
    local cls = p and loadClass(p)
    if cls then return cls end
    local dir = dataPath:match('^(.*)/[^/]+$')
    local bp = BP_EXCEPTIONS[id] or ('BP_' .. id:gsub('^ITEM_', ''))
    return dir and loadClass(dir .. '/' .. bp .. '.' .. bp .. '_C') or nil
end
Hd.actorClassOf = actorClassOf

local function superOf(cls)
    local s = get(function() return cls:GetSuperStruct() end)
    return valid(s) and s or nil
end

-- Finds the template called `name` on a Blueprint class or its parents:
-- Blueprint components and inherited overrides live at <Class>:<Name>_GEN_VARIABLE,
-- native components at <Package>.Default__<Class>:<Name>.
-- StaticFindObject is slow when the object does not exist (UE4SS falls back
-- to a search), so every miss is remembered and never asked again.
local missCache = {}
local function lookup(p)
    if missCache[p] then return nil end
    local obj = get(function() return StaticFindObject(p) end)
    if valid(obj) then return obj end
    missCache[p] = true
    return nil
end

local function findTemplate(cls, name)
    local c = cls
    while c do
        local p = path(c)
        if not p:match('^/Game/') and not p:match('^/%w+/Gameplay/') then break end -- native class: stop
        local package, className = p:match('^(.+)%.([^%.]+)$')
        for _, candidate in ipairs({
            p .. ':' .. name .. '_GEN_VARIABLE',
            package and (package .. '.Default__' .. className .. ':' .. name) or nil,
        }) do
            local tpl = lookup(candidate)
            if tpl and isMesh(tpl) then return tpl end
        end
        c = superOf(c)
    end
    return nil
end

-- Construction-script templates, parents first: { name, tpl, parent, socket }.
local function scsTemplates(cls)
    local out = {}
    local chain, c = {}, cls
    while c do table.insert(chain, 1, c) c = superOf(c) end
    local function walk(node, parent)
        if not valid(node) then return end
        local tpl = get(function() return node.ComponentTemplate end)
        local name = str(get(function() return node.InternalVariableName end))
            or (valid(tpl) and (nameOf(tpl):gsub('_GEN_VARIABLE$', ''))) or ''
        if valid(tpl) then
            out[#out + 1] = {
                name = name, tpl = tpl,
                parent = str(get(function() return node.ParentComponentOrVariableName end)) or parent,
                socket = str(get(function() return node.AttachToName end)),
            }
        end
        for _, child in ipairs(list(get(function() return node.ChildNodes end))) do walk(child, name) end
    end
    for _, k in ipairs(chain) do
        local scs = get(function() return k.SimpleConstructionScript end)
        if valid(scs) then
            for _, node in ipairs(list(get(function() return scs.RootNodes end))) do walk(node, nil) end
        end
    end
    return out
end

local function usable(tpl, name)
    return isMesh(tpl) and not skipped(name) and meshAsset(tpl) ~= nil
        and get(function() return tpl.bVisible end) ~= false
        and get(function() return tpl.bHiddenInGame end) ~= true
end

-- Visible mesh templates of a weapon Blueprint: { name, tpl, parent, socket, via }.
-- hints: component names worth trying (the real weapon's mesh names).
--
-- The cache keeps PLAIN DATA only: per class path, each template's name,
-- parent, socket, route and the template's own object path. The templates are
-- looked up again from those paths on every call. Keeping the template
-- objects crashed the game (dump 2026-09-30 18:50): the weapon Blueprint was
-- unloaded and loaded again under the same name, and the cache handed back
-- the old, freed templates.
local templateCache = {} -- class path -> { { name, tplPath, parent, socket, via } }

-- Live templates for cached plain entries, or nil if any of them is gone.
local function resolveTemplates(entries)
    local out = {}
    for _, e in ipairs(entries) do
        local tpl = get(function() return StaticFindObject(e.tplPath) end)
        if not (valid(tpl) and isMesh(tpl)) then return nil end
        out[#out + 1] = { name = e.name, tpl = tpl, parent = e.parent, socket = e.socket, via = e.via }
    end
    return out
end

local function plainTemplates(visual)
    local out = {}
    for _, t in ipairs(visual) do
        local tplPath = path(t.tpl)
        if tplPath == '' then return nil end
        out[#out + 1] = { name = t.name, tplPath = tplPath, parent = t.parent, socket = t.socket, via = t.via }
    end
    return out
end
Hd.plainTemplates, Hd.resolveTemplates = plainTemplates, resolveTemplates

local function visualTemplates(cls, hints)
    local key = path(cls)
    local cached = templateCache[key]
    if cached then
        local live = resolveTemplates(cached)
        if live then return live end
        templateCache[key] = nil
    end
    local byName, order = {}, {}
    local function put(t)
        if t.name == '' then return end
        if not byName[t.name] then order[#order + 1] = t.name end
        byName[t.name] = t
    end
    for _, t in ipairs(scsTemplates(cls)) do
        -- Most-derived override of this template, if a child Blueprint edited it.
        t.tpl = findTemplate(cls, t.name) or t.tpl
        t.via = 'scs'
        put(t)
    end
    local function collect()
        local visual = {}
        for _, n in ipairs(order) do
            local t = byName[n]
            if usable(t.tpl, n) then visual[#visual + 1] = t end
        end
        return visual
    end
    -- The real weapon's mesh names first: weapons of one type share a base
    -- Blueprint, so this usually hits at once. Common names only as a fallback.
    for _, n in ipairs(hints or {}) do
        if not byName[n] then
            local tpl = findTemplate(cls, n)
            if tpl then put({ name = n, tpl = tpl, via = 'path' }) end
        end
    end
    local visual = collect()
    if #visual == 0 then
        for _, n in ipairs(COMMON_NAMES) do
            if not byName[n] then
                local tpl = findTemplate(cls, n)
                if tpl and usable(tpl, n) then
                    put({ name = n, tpl = tpl, via = 'path' })
                    break
                end
            end
        end
        visual = collect()
    end
    -- Only cache real results: an empty one may just mean the hints were wrong.
    if #visual > 0 and key ~= '' then templateCache[key] = plainTemplates(visual) end
    return visual
end

-- --------------------------------------------------------------- hiding

local function hideReal(state, comp)
    local saved = {
        comp = comp,
        main = get(function() return comp.bRenderInMainPass end),
        depth = get(function() return comp.bRenderInDepthPass end),
        shadow = get(function() return comp.CastShadow end),
        tracing = get(function() return comp.bVisibleInRayTracing end),
    }
    if isSkeletal(comp) then
        saved.tick = get(function() return comp.VisibilityBasedAnimTickOption end)
        -- Keep animating while not drawn so ghosts following its pose move.
        pcall(function() comp.VisibilityBasedAnimTickOption = ALWAYS_TICK_POSE end)
    end
    local ok = pcall(function()
        comp:SetRenderInMainPass(false)
        comp:SetRenderInDepthPass(false)
    end)
    if not ok then
        saved.hiddenInGame = get(function() return comp.bHiddenInGame end)
        pcall(function() comp:SetHiddenInGame(true, false) end)
    end
    pcall(function() comp:SetCastShadow(false) end)
    pcall(function() comp:SetVisibleInRayTracing(false) end)
    state.hidden[#state.hidden + 1] = saved
end

local function showReal(saved)
    local comp = saved.comp
    pcall(function() comp:SetRenderInMainPass(saved.main ~= false) end)
    pcall(function() comp:SetRenderInDepthPass(saved.depth ~= false) end)
    pcall(function() comp:SetCastShadow(saved.shadow ~= false) end)
    pcall(function() comp:SetVisibleInRayTracing(saved.tracing ~= false) end)
    if saved.hiddenInGame ~= nil then pcall(function() comp:SetHiddenInGame(saved.hiddenInGame, false) end) end
    if saved.tick ~= nil then pcall(function() comp.VisibilityBasedAnimTickOption = saved.tick end) end
end

-- ------------------------------------------------------------------ ghosts

local warned = {}
local function warnOnce(key, s)
    if warned[key] then return end
    warned[key] = true
    log(s)
end

local function copyMaterials(tpl, ghost)
    for index, material in ipairs(list(get(function() return tpl.OverrideMaterials end))) do
        if valid(material) then pcall(function() ghost:SetMaterial(index - 1, material) end) end
    end
end

local function sameSkeleton(a, b)
    local sa = get(function() return a.Skeleton end)
    local sb = get(function() return b.Skeleton end)
    return valid(sa) and full(sa) == full(sb)
end

local function number(v, default)
    return type(v) == 'number' and v or default
end

-- Template's relative transform as an FTransform table (FRotator -> FQuat
-- exactly as FRotator::Quaternion does), so placement needs no call with
-- struct out-parameters.
local function relativeTransform(tpl)
    local l = get(function() return tpl.RelativeLocation end)
    local r = get(function() return tpl.RelativeRotation end)
    local s = get(function() return tpl.RelativeScale3D end)
    local pitch = number(get(function() return r.Pitch end), 0)
    local yaw = number(get(function() return r.Yaw end), 0)
    local roll = number(get(function() return r.Roll end), 0)
    local half = math.pi / 360
    local sp, cp = math.sin(pitch * half), math.cos(pitch * half)
    local sy, cy = math.sin(yaw * half), math.cos(yaw * half)
    local sr, cr = math.sin(roll * half), math.cos(roll * half)
    return {
        Rotation = {
            X = cr * sp * sy - sr * cp * cy,
            Y = -cr * sp * cy - sr * cp * sy,
            Z = cr * cp * sy - sr * sp * cy,
            W = cr * cp * cy + sr * sp * sy,
        },
        Translation = {
            X = number(get(function() return l.X end), 0),
            Y = number(get(function() return l.Y end), 0),
            Z = number(get(function() return l.Z end), 0),
        },
        Scale3D = {
            X = number(get(function() return s.X end), 1),
            Y = number(get(function() return s.Y end), 1),
            Z = number(get(function() return s.Z end), 1),
        },
    }
end
Hd.relativeTransform = relativeTransform

local function addGhost(actor, t, parent, socket, leader)
    local tpl = t.tpl
    local skeletal = isSkeletal(tpl)
    local transform = relativeTransform(tpl)
    trace('create ' .. (skeletal and 'skeletal' or 'static') .. ' ghost for ' .. t.name)
    local ghost = get(function() return actor:AddComponentByClass(class(skeletal and SKELETAL or STATIC), true, transform, false) end)
    if not valid(ghost) then
        warnOnce('add', 'weapon looks unavailable: AddComponentByClass failed')
        return nil
    end
    trace('configure ghost')
    pcall(function() ghost:SetCollisionEnabled(NO_COLLISION) end)
    pcall(function() ghost:SetGenerateOverlapEvents(false) end)
    trace('attach ghost to ' .. nameOf(parent) .. ' socket ' .. tostring(socket))
    pcall(function() ghost:K2_AttachToComponent(parent, FName(socket or 'None'), KEEP_RELATIVE, KEEP_RELATIVE, KEEP_RELATIVE, false) end)
    local mesh = meshAsset(tpl)
    trace('set mesh ' .. full(mesh))
    if skeletal then
        if not pcall(function() ghost:SetSkeletalMeshAsset(mesh) end) then
            pcall(function() ghost:SetSkeletalMesh(mesh, true) end)
        end
        local leaderMesh = leader and meshAsset(leader)
        if leaderMesh and sameSkeleton(mesh, leaderMesh) then
            -- Same rig (bow strings, crossbow arms): copy the real weapon's pose.
            if not pcall(function() ghost:SetLeaderPoseComponent(leader, true, false) end) then
                pcall(function() ghost:SetMasterPoseComponent(leader, true) end)
            end
        else
            local anim = get(function() return tpl.AnimClass end)
            if valid(anim) then pcall(function() ghost:SetAnimInstanceClass(anim) end) end
        end
    else
        pcall(function() ghost:SetStaticMesh(mesh) end)
    end
    trace('copy materials')
    copyMaterials(tpl, ghost)
    return ghost
end

local function ownerAlive(comp)
    return valid(comp) and alive(get(function() return comp:GetOwner() end))
end

local function restore(state)
    -- Components of an actor being torn down go with it; touching them can crash.
    for _, ghost in ipairs(state.ghosts) do
        if ownerAlive(ghost) then pcall(function() ghost:K2_DestroyComponent(ghost) end) end
    end
    for _, saved in ipairs(state.hidden) do
        if ownerAlive(saved.comp) then showReal(saved) end
    end
    state.ghosts, state.hidden, state.anchor, state.shownVisible = {}, {}, nil, nil
end

-- Renders appearance `want` (ITEM id or HIDDEN) on `actor`. Returns ok, reason.
local function dress(state, actor, key, want, hiddenValue)
    trace('apply ' .. want .. ' on ' .. full(actor:GetClass()))
    local reals = realVisuals(actor)
    if #reals == 0 then return false, 'no visible meshes on ' .. full(actor:GetClass()) end
    trace(#reals .. ' real mesh(es) found')
    local templates
    if want ~= hiddenValue then
        local data = C.load(C.find(key, want))
        if not data then return false, 'unknown look ' .. tostring(want) end
        trace('resolve actor class of ' .. full(data))
        local cls = actorClassOf(data)
        if not valid(cls) then return false, 'no actor class for ' .. want end
        local hints = {}
        for _, comp in ipairs(reals) do hints[#hints + 1] = nameOf(comp) end
        trace('read templates of ' .. full(cls))
        templates = visualTemplates(cls, hints)
        if #templates == 0 then return false, 'no meshes found in ' .. full(cls) end
        trace(#templates .. ' template(s) found')
    end

    local leader
    local realByName = {}
    for _, comp in ipairs(actorComponents(actor)) do realByName[nameOf(comp)] = comp end
    trace('hide real meshes')
    for _, comp in ipairs(reals) do
        if not leader and isSkeletal(comp) then leader = comp end
        hideReal(state, comp)
    end
    state.anchor = reals[1]

    if templates then
        local root = get(function() return actor:K2_GetRootComponent() end)
        local ghostByName = {}
        for _, t in ipairs(templates) do
            local parent, socket = nil, t.socket
            if t.parent then parent = ghostByName[t.parent] or realByName[t.parent] end
            local twin = realByName[t.name]
            if not parent and valid(twin) then
                -- Same slot on the real weapon: attach where it is attached.
                parent = get(function() return twin:GetAttachParent() end)
                socket = socket or str(get(function() return twin:GetAttachSocketName() end))
            end
            if not valid(parent) then parent = root end
            local ghost = valid(parent) and addGhost(actor, t, parent, socket, leader)
            if ghost then
                ghostByName[t.name] = ghost
                state.ghosts[#state.ghosts + 1] = ghost
            end
        end
        if #state.ghosts == 0 then
            restore(state)
            return false, 'ghost meshes could not be created'
        end
    end
    trace('done')
    return true
end

-- Ghosts mirror the real weapon's visibility; re-hides if the game re-enabled drawing.
local function sync(state)
    local anchor = state.anchor
    if not ownerAlive(anchor) then return end
    local visible = get(function() return anchor:IsVisible() end) == true
    if visible ~= state.shownVisible then
        state.shownVisible = visible
        for _, ghost in ipairs(state.ghosts) do
            if valid(ghost) then pcall(function() ghost:SetVisibility(visible, true) end) end
        end
    end
    for _, saved in ipairs(state.hidden) do
        if saved.hiddenInGame == nil and valid(saved.comp)
            and get(function() return saved.comp.bRenderInMainPass end) == true then
            pcall(function() saved.comp:SetRenderInMainPass(false) end)
            pcall(function() saved.comp:SetRenderInDepthPass(false) end)
        end
    end
end

-- After a UE4SS hot reload the previous instance's ghosts are still attached
-- and the real meshes still hidden, with nothing tracking them. Ghosts are
-- recognisable: AddComponentByClass names them <Class>_<n> (Blueprint
-- components use their variable names) and they have no collision.
local function cleanupStale(actor)
    local removed = 0
    for _, comp in ipairs(actorComponents(actor)) do
        local n = nameOf(comp)
        if isMesh(comp) and (n:match('^StaticMeshComponent_%d+$') or n:match('^SkeletalMeshComponent_%d+$'))
            and get(function() return comp:GetCollisionEnabled() end) == NO_COLLISION then
            pcall(function() comp:K2_DestroyComponent(comp) end)
            removed = removed + 1
        elseif isMesh(comp) and get(function() return comp.bRenderInMainPass end) == false then
            showReal({ comp = comp })
        end
    end
    if removed > 0 then debug('removed ' .. removed .. ' leftover weapon look mesh(es) from a previous load') end
end

-- ----------------------------------------------------------------- public

function Hd.newState() return { ghosts = {}, hidden = {} } end

-- Keeps one hand of one character in line with `sel`.
-- sel: slot key -> ITEM id | hiddenValue. onSeen(id) is called for the real item.
function Hd.update(state, equipment, side, sel, hiddenValue, onSeen)
    local actor = heldActor(equipment, side)
    local actorName = full(actor)
    local now = os.clock()
    if actorName ~= state.actor then
        restore(state)
        state.actor, state.applied, state.key = actorName, nil, nil
        state.readyAt = now + 0.2 -- let a freshly spawned actor finish construction
    end
    if not alive(actor) then return end

    local data = heldData(equipment, actor, side)
    local key = C.heldKey(data)
    if state.learnedFor ~= actorName then
        state.learnedFor = actorName
        pcall(cleanupStale, actor)
        if key then learn(data, actor) end
    end
    if onSeen and data then
        local id = full(data):match('%.([%w_]+)$')
        if id then onSeen(id) end
    end
    local want = key and sel[key] or nil
    if want ~= state.applied or key ~= state.key then
        if now < (state.readyAt or 0) then return end
        restore(state)
        state.applied, state.key = want, key
        if want and Hd.blocked[want] then
            log('weapon look ' .. want .. ' is disabled for this session (it crashed the game last time)')
        elseif want then
            lock(want)
            local ok, dressed, reason = pcall(dress, state, actor, key, want, hiddenValue)
            unlock()
            if not ok or not dressed then
                restore(state)
                log('weapon look ' .. tostring(want) .. ': ' .. tostring(ok and reason or dressed))
            end
        end
    end
    if state.applied then sync(state) end
end

-- Real weapon key for a hand of the given equipment component, or nil.
function Hd.currentKey(equipment, side)
    local actor = heldActor(equipment, side)
    if not alive(actor) then return nil, nil end
    local data = heldData(equipment, actor, side)
    return C.heldKey(data), data
end

function Hd.forget(state)
    if state then restore(state) end
end

-- Map load: drop the template cache (plain data, so belt and braces).
function Hd.forgetCaches()
    templateCache = {}
end
Hd.visualTemplates = visualTemplates

-- Console diagnostics: what the mod sees on a held weapon and on its chosen look.
function Hd.describe(equipment, side, sel, out)
    local actor = heldActor(equipment, side)
    if not valid(actor) then out(side .. ': nothing held') return end
    local data = heldData(equipment, actor, side)
    local key = C.heldKey(data)
    out(string.format('%s: actor=%s data=%s key=%s', side, full(actor:GetClass()), full(data), tostring(key)))
    local walked = actorComponents(actor)
    local n = get(function() return get(function() return actor:K2_GetRootComponent() end):GetNumChildrenComponents() end)
    out(string.format('   components walked: %d (root children: %s)', #walked, tostring(n)))
    local hints = {}
    for _, comp in ipairs(walked) do
        local cls = full(comp:GetClass()):match('%.([%w_]+)$') or '?'
        out(string.format('   component %s (%s) mesh=%s visible=%s parent=%s socket=%s', nameOf(comp), cls,
            full(meshAsset(comp)), tostring(get(function() return comp:IsVisible() end)),
            nameOf(get(function() return comp:GetAttachParent() end)),
            tostring(str(get(function() return comp:GetAttachSocketName() end)))))
        if isMesh(comp) then hints[#hints + 1] = nameOf(comp) end
    end
    local want = key and sel[key]
    local entry = want and C.find(key, want)
    local look = entry and C.load(entry)
    if look then
        local cls = actorClassOf(look)
        out(string.format('   look %s -> class %s', want, full(cls)))
        if valid(cls) then
            local scs = get(function() return cls.SimpleConstructionScript end)
            out(string.format('   look SCS=%s rootNodes=%d', full(scs), #list(get(function() return scs.RootNodes end))))
            templateCache[path(cls)] = nil
            for _, t in ipairs(visualTemplates(cls, hints)) do
                out(string.format('   look template %s via %s parent=%s socket=%s mesh=%s', t.name, t.via,
                    tostring(t.parent), tostring(t.socket), full(meshAsset(t.tpl))))
            end
        end
    elseif want then
        out('   look ' .. want .. ' could not be loaded')
    end
end

return Hd
