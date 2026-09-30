-- RSE-Transmog (RuneScape Enhanced): visual-only transmog for RuneScape: Dragonwilds.
-- Based on Dragonwilds Wardrobe by ColonelCousland (MIT).
-- The same folder runs on clients, listen hosts and dedicated servers; on a
-- server without a local player only the multiplayer relay (net.lua) works.
local VERSION = '1.2.2'
local V = require('visual')
local U = require('ui')
local N = require('net')
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
local SETTLE = 3
local idleUntil = 0
local function forgetWorld(pause)
    for _, f in ipairs({ V.forget, U.forget, N.forget }) do pcall(f) end
    idleUntil = os.clock() + pause
    U.idle = true
end
pcall(RegisterLoadMapPreHook, function()
    pcall(U.newWorld)
    forgetWorld(60)
end)
pcall(RegisterLoadMapPostHook, function() forgetWorld(SETTLE) end)

local frame = 0
local function step()
    if idleUntil > 0 then
        if os.clock() < idleUntil then return end
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
