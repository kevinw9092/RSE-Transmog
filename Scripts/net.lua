-- Multiplayer sync: lets players who run the mod see each other's looks.
--
-- Transport uses two stock engine RPCs that every PlayerController has and
-- the game itself never uses in shipping builds:
--   client -> server   APlayerController::ServerExec(FString)       (max 128 chars)
--   server -> client   APlayerController::ClientMessage(FString, ...)
-- The server (listen host or dedicated server with UE4SS) keeps each
-- player's selection and relays it to every client that said hello. Only
-- selection ids travel; stats, inventory and replicated game state are
-- never touched. Without the mod on the server nothing is sent after the
-- first unanswered hellos, and players without the mod see nothing new.
--
-- Protocol (space separated, prefix PROTO):
--   C->S  hi                     client has the mod; server answers ack + state
--   C->S  set <key> <value>      key: Head|Body|Legs|Cape|Held:<Category>
--                                value: ITEM_... | HIDDEN | -   (- = original)
--   S->C  ack
--   S->C  set <playerId> <key> <value>
--   S->C  clr <playerId>         player left
local Cfg = require('config')

local N = {
    PROTO = 'rset1',
    remote = {},      -- playerId -> { key -> value }   (what other players chose)
    acked = false,    -- the server runs the mod
}
local MAX_LEN = 120   -- ServerExec rejects (and disconnects) above 128
local MAX_KEYS = 24
local HELLO_EVERY, HELLO_TRIES = 5, 6
local SEND_PER_TICK = 6

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function log(s) print('[RSE-Transmog/Net] ' .. tostring(s) .. '\n') end
local function debug(s) if Cfg.Debug then log(s) end end
local function enabled() return Cfg.Multiplayer ~= false end

local function alive(actor)
    if not valid(actor) then return false end
    return get(function() return actor:IsActorBeingDestroyed() end) ~= true
end

local ARMOUR = { Head = true, Body = true, Legs = true, Cape = true }
function N.validKey(key)
    return type(key) == 'string' and (ARMOUR[key] or key:match('^Held:%a+$') ~= nil) and #key <= 24
end
function N.validValue(value)
    return type(value) == 'string' and #value <= 80
        and (value == '-' or value == 'HIDDEN' or value:match('^ITEM_[%w_]+$') ~= nil)
end

local function words(s)
    local out = {}
    for w in s:gmatch('%S+') do out[#out + 1] = w end
    return out
end

local function playerId(pc)
    local id = get(function() return pc.PlayerState.PlayerId end)
    return type(id) == 'number' and math.floor(id) or nil
end
N.playerId = playerId

-- ------------------------------------------------------------------ client

local client = { pc = nil, pcName = nil, tries = 0, nextHello = 0, outbox = {} }

local function sendNow(pc, message)
    if #message > MAX_LEN then return false end
    local ok, err = pcall(function() pc:ServerExec(message) end)
    if not ok then debug('send failed: ' .. tostring(err)) end
    return ok
end

local function queue(message) client.outbox[#client.outbox + 1] = message end

local function queueState(sel)
    for key, value in pairs(sel or {}) do
        if N.validKey(key) and N.validValue(value) then
            queue(N.PROTO .. ' set ' .. key .. ' ' .. value)
        end
    end
end

-- Called every tick with the local controller and the local selection table.
function N.clientTick(pc, sel)
    if not enabled() then return end
    local name = full(pc)
    if name ~= client.pcName then
        -- New world or reconnect: start the handshake again.
        client.pc, client.pcName, client.tries, client.nextHello = pc, name, 0, os.clock() + 2
        client.outbox, N.acked, N.remote = {}, false, {}
        N.changed = true
    end
    if not valid(pc) then return end
    local now = os.clock()
    if not N.acked and client.tries < HELLO_TRIES and now >= client.nextHello then
        client.tries = client.tries + 1
        client.nextHello = now + HELLO_EVERY
        sendNow(pc, N.PROTO .. ' hi')
        if client.tries == HELLO_TRIES then debug('server did not answer; looks stay local') end
    end
    if N.acked and client.pendingState then
        client.pendingState = nil
        queueState(sel)
    end
    local sent = 0
    while N.acked and sent < SEND_PER_TICK and #client.outbox > 0 do
        sendNow(pc, table.remove(client.outbox, 1))
        sent = sent + 1
    end
end

-- Local selection changed.
function N.publish(key, value)
    if not enabled() or not N.acked then return end
    if value == nil then value = '-' end
    if N.validKey(key) and N.validValue(value) then queue(N.PROTO .. ' set ' .. key .. ' ' .. value) end
end

local function onClientMessage(pc, text)
    if text:sub(1, #N.PROTO + 1) ~= N.PROTO .. ' ' then return end
    if not get(function() return pc:IsLocalController() end) then return end
    N.stats.clientHandled = N.stats.clientHandled + 1
    local w = words(text)
    if w[2] == 'ack' then
        if not N.acked then log('server runs RSE-Transmog: looks are shared') end
        N.acked = true
        client.pendingState = true
    elseif w[2] == 'set' and #w == 5 then
        local id, key, value = tonumber(w[3]), w[4], w[5]
        if id and N.validKey(key) and N.validValue(value) then
            N.remote[id] = N.remote[id] or {}
            N.remote[id][key] = value ~= '-' and value or nil
            N.changed = true
        end
    elseif w[2] == 'clr' and #w == 3 then
        local id = tonumber(w[3])
        -- Keep an empty table so a still-present character is restored.
        if id and N.remote[id] then N.remote[id] = {} N.changed = true end
    end
end

-- ------------------------------------------------------------------ server

local server = { players = {} } -- pcName -> { pc, id, sel, subscribed, tokens, stamp }

local function tell(pc, message)
    pcall(function() pc:ClientMessage(message, FName('None'), 0.0) end)
end

local function broadcast(message)
    for _, p in pairs(server.players) do
        if p.subscribed and alive(p.pc) then tell(p.pc, message) end
    end
end

local function onServerExec(pc, text)
    if text:sub(1, #N.PROTO + 1) ~= N.PROTO .. ' ' then return end
    -- Only the machine with authority relays (a listen host, or a dedicated server).
    local authority = get(function() return pc:HasAuthority() end)
    if authority == nil then authority = get(function() return pc.Role end) == 3 end -- ROLE_Authority
    if authority ~= true then
        -- UE4SS also reports our own outgoing call on a client: not a problem.
        N.stats.sent = N.stats.sent + 1
        return
    end
    N.stats.serverHandled = N.stats.serverHandled + 1
    local key = full(pc)
    local id = playerId(pc)
    if not id then return end
    local p = server.players[key]
    if not p or p.id ~= id then
        p = { pc = pc, id = id, sel = {}, count = 0, tokens = 40, stamp = os.clock() }
        server.players[key] = p
    end
    -- Rate limit: 10 messages per second, bursts of 40.
    local now = os.clock()
    p.tokens = math.min(40, p.tokens + (now - p.stamp) * 10)
    p.stamp = now
    if p.tokens < 1 then return end
    p.tokens = p.tokens - 1

    local w = words(text)
    if w[2] == 'hi' then
        p.subscribed = true
        tell(pc, N.PROTO .. ' ack')
        for _, other in pairs(server.players) do
            if other ~= p then
                for k, v in pairs(other.sel) do tell(pc, string.format('%s set %d %s %s', N.PROTO, other.id, k, v)) end
            end
        end
        debug('player ' .. id .. ' joined the transmog sync')
    elseif w[2] == 'set' and #w == 4 and N.validKey(w[3]) and N.validValue(w[4]) then
        local k, v = w[3], w[4]
        local stored = v ~= '-' and v or nil
        if p.sel[k] == stored then return end
        if stored and not p.sel[k] then
            if p.count >= MAX_KEYS then return end
            p.count = p.count + 1
        elseif not stored and p.sel[k] then
            p.count = p.count - 1
        end
        p.sel[k] = stored
        broadcast(string.format('%s set %d %s %s', N.PROTO, id, k, v))
    end
end

local nextSweep = 0
-- Runs on every machine; only does work where players registered (the server).
function N.serverTick()
    local now = os.clock()
    if now < nextSweep then return end
    nextSweep = now + 2
    for key, p in pairs(server.players) do
        if not alive(p.pc) or playerId(p.pc) ~= p.id then
            server.players[key] = nil
            broadcast(string.format('%s clr %d', N.PROTO, p.id))
            debug('player ' .. p.id .. ' left the transmog sync')
        end
    end
end

-- ------------------------------------------------------------------- setup

-- FString parameters arrive as a Lua string or as an FString object,
-- depending on the UE4SS build.
local function textOf(param)
    local v = get(function() return param:get() end)
    if type(v) == 'string' then return v end
    local s = get(function() return v:ToString() end)
    if type(s) == 'string' then return s end
    s = get(function() return param:ToString() end)
    return type(s) == 'string' and s or nil
end

-- Hook counters for transmog_status: tells "hook never fired" apart from
-- "server has no mod".
N.stats = { serverHook = 0, sent = 0, serverHandled = 0, clientHook = 0, clientHandled = 0, lastError = nil }

function N.hook()
    local ok, err = pcall(RegisterHook, '/Script/Engine.PlayerController:ServerExec', function(ctx, message)
        if not enabled() then return end
        N.stats.serverHook = N.stats.serverHook + 1
        local text = textOf(message)
        if not text then N.stats.lastError = 'ServerExec text unreadable' return end
        local okHandle, handleErr = pcall(onServerExec, ctx:get(), text)
        if not okHandle then
            N.stats.lastError = tostring(handleErr)
            log('server: ' .. tostring(handleErr))
        end
    end)
    if not ok then log('ServerExec hook unavailable: ' .. tostring(err)) end
    ok, err = pcall(RegisterHook, '/Script/Engine.PlayerController:ClientMessage', function(ctx, message)
        if not enabled() then return end
        N.stats.clientHook = N.stats.clientHook + 1
        local text = textOf(message)
        if not text then N.stats.lastError = 'ClientMessage text unreadable' return end
        local okHandle, handleErr = pcall(onClientMessage, ctx:get(), text)
        if not okHandle then
            N.stats.lastError = tostring(handleErr)
            log('client: ' .. tostring(handleErr))
        end
    end)
    if not ok then log('ClientMessage hook unavailable: ' .. tostring(err)) end
end

function N.describe(out)
    local mode = '?'
    pcall(function()
        local lib = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        if lib:IsStandalone(client.pc) then mode = 'solo'
        elseif lib:IsDedicatedServer(client.pc) then mode = 'dedicated server'
        elseif lib:IsServer(client.pc) then mode = 'host'
        else mode = 'client' end
    end)
    out(string.format('sync %s (%s), server answered: %s, hellos sent: %d, queued: %d',
        enabled() and 'on' or 'off', mode, tostring(N.acked), client.tries, #client.outbox))
    local s = N.stats
    out(string.format('   messages: %d sent, %d relayed as server, %d received (%d for us), last error: %s',
        s.sent, s.serverHandled, s.clientHook, s.clientHandled, tostring(s.lastError)))
    for id, sel in pairs(N.remote) do
        local parts = {}
        for k, v in pairs(sel) do parts[#parts + 1] = k .. '=' .. v end
        table.sort(parts)
        out(string.format('   player %d: %s', id, #parts > 0 and table.concat(parts, ' ') or '(original)'))
    end
    local count = 0
    for _ in pairs(server.players) do count = count + 1 end
    if count > 0 then out(string.format('relaying for %d player(s)', count)) end
end

return N
