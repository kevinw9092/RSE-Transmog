-- RSE-Transmog (RuneScape Enhanced): visual-only transmog for RuneScape: Dragonwilds.
-- Based on Dragonwilds Wardrobe by ColonelCousland (MIT).
-- The same folder runs on clients, listen hosts and dedicated servers; on a
-- server without a local player only the multiplayer relay (net.lua) works.
local VERSION = '1.3.0'
local V = require('visual')
local U = require('ui')
local N = require('net')
local C = require('catalog')
local Hd = require('held')
local function log(s) print('[RSE-Transmog] ' .. tostring(s) .. '\n') end

local ok, err = pcall(U.start)
if not ok then log('UI startup: ' .. tostring(err)) end
ok, err = pcall(V.hook)
if not ok then log('hooks: ' .. tostring(err)) end
ok, err = pcall(N.hook)
if not ok then log('net hooks: ' .. tostring(err)) end

-- "transmog_status" in the game console prints what the mod sees (for bug reports).
if type(RegisterConsoleCommandHandler) == 'function' then
    pcall(RegisterConsoleCommandHandler, 'transmog_status', function(_, _, ar)
        local function out(line)
            log(line)
            pcall(function() ar:Log('[RSE-Transmog] ' .. line) end)
        end
        local okDescribe, describeErr = pcall(function()
            V.describe(out)
            N.describe(out)
        end)
        if not okDescribe then out('status failed: ' .. tostring(describeErr)) end
        return true
    end)
    -- Developer tool: logs the candidate brushes of a live empty and filled
    -- inventory slot (open the inventory first), for the slot art.
    pcall(RegisterConsoleCommandHandler, 'transmog_slotart', function(_, _, ar)
        local function out(line)
            log(line)
            pcall(function() ar:Log('[RSE-Transmog] ' .. line) end)
        end
        local okArt, artErr = pcall(U.describeSlotArt, out)
        if not okArt then out('slotart failed: ' .. tostring(artErr)) end
        return true
    end)
    -- Developer tool: dumps the game's UI building blocks to ui-dump.txt.
    pcall(RegisterConsoleCommandHandler, 'transmog_dumpui', function(_, _, ar)
        local okDump, result = pcall(function() return require('uidump').run() end)
        local line = okDump and tostring(result) or ('dump failed: ' .. tostring(result))
        log(line)
        pcall(function() ar:Log('[RSE-Transmog] ' .. line) end)
        return true
    end)
end

-- One game-thread loop drives everything: the equipment watchdog (four
-- pointer reads), the wardrobe panel and hover highlight while it is open.
-- A single long-lived callback is used on purpose: creating a new
-- ExecuteInGameThread callback every few milliseconds corrupts the callback
-- registry of some UE4SS builds and eventually crashes the game.
-- Map loads: forget every game object held and stay idle until the new world
-- has settled. Calling into the old world's characters or widgets while they
-- are torn down crashes the game natively (a pcall cannot catch it); two
-- crashes on leave-and-rejoin (2026-09-30) happened ~2 s into a world load.
-- The settle also counts loop ticks: right after a load the game can spend
-- seconds in a single frame (3.2 s on 2026-09-30 18:30), and a clock-only
-- settle would then end in the very first frame after it. The loop runs at
-- most once a frame, so SETTLE_TICKS ticks means that many real frames.
local SETTLE = 3
local SETTLE_TICKS = 10
local idleUntil, idleTicks = 0, 0
local function forgetWorld(pause)
    for _, f in ipairs({ V.forget, U.forget, N.forget, C.forget, Hd.forgetCaches }) do pcall(f) end
    idleUntil = os.clock() + pause
    idleTicks = SETTLE_TICKS
    U.idle = true
end
pcall(RegisterLoadMapPreHook, function()
    pcall(U.newWorld)
    forgetWorld(60)
end)
pcall(RegisterLoadMapPostHook, function() forgetWorld(SETTLE) end)

-- RSE-ModMenu (Esc > MODS) publishes changed settings as shared variables.
-- The config table is shared by every module, so live settings apply at once;
-- UIStyle, Multiplayer and ShowOthers apply after a restart (see modmenu.json).
local Cfg = require('config')
local MODMENU_ID = 'RSE-Transmog'
local mmRev = nil
local function modMenuSync()
    local ok, rev = pcall(function() return ModRef:GetSharedVariable('ModMenu.' .. MODMENU_ID .. '.rev') end)
    if not ok or type(rev) ~= 'number' or rev == mmRev then return end
    mmRev = rev
    local okV, v = pcall(function() return ModRef:GetSharedVariable('ModMenu.' .. MODMENU_ID .. '.Debug') end)
    if okV and type(v) == 'boolean' then Cfg.Debug = v end
end

local frame = 0
local function step()
    modMenuSync()
    if idleUntil > 0 then
        if idleTicks > 0 then idleTicks = idleTicks - 1 end
        if os.clock() < idleUntil or idleTicks > 0 then return end
        idleUntil = 0
        U.idle = false
        local okFlush, flushError = pcall(U.flush)
        if not okFlush then log('UI: ' .. tostring(flushError)) end
    end
    frame = frame + 1
    if frame % 2 == 0 then
        local okVisual, visualError = pcall(V.tick)
        if not okVisual then log('visual: ' .. tostring(visualError)) end
        local okNet, netError = pcall(N.serverTick)
        if not okNet then log('net: ' .. tostring(netError)) end
        local okUi, uiError = pcall(U.tick)
        if not okUi then log('UI: ' .. tostring(uiError)) end
    end
    local okHover, hoverError = pcall(U.hover)
    if not okHover then log('hover: ' .. tostring(hoverError)) end
end

if type(LoopInGameThreadWithDelay) == 'function' then
    LoopInGameThreadWithDelay(120, step)
else
    -- Older UE4SS builds: one slower async loop hopping to the game thread.
    LoopAsync(250, function()
        ExecuteInGameThread(function()
            frame = frame + 1 -- keep watchdog on every call
            step()
        end)
        return false
    end)
end

log('v' .. VERSION .. ' loaded')
