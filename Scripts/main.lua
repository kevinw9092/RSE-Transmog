-- Dragonwilds Wardrobe: visual-only transmog for RuneScape: Dragonwilds.
local VERSION = '1.0.0'
local V = require('visual')
local U = require('ui')
local function log(s) print('[DragonwildsWardrobe] ' .. tostring(s) .. '\n') end

local ok, err = pcall(U.start)
if not ok then log('UI startup: ' .. tostring(err)) end
ok, err = pcall(V.hook)
if not ok then log('hooks: ' .. tostring(err)) end

-- One game-thread loop drives everything: the equipment watchdog (four
-- pointer reads), the wardrobe panel and hover highlight while it is open.
-- A single long-lived callback is used on purpose: creating a new
-- ExecuteInGameThread callback every few milliseconds corrupts the callback
-- registry of some UE4SS builds and eventually crashes the game.
local frame = 0
local function step()
    frame = frame + 1
    if frame % 2 == 0 then
        local okVisual, visualError = pcall(V.tick)
        if not okVisual then log('visual: ' .. tostring(visualError)) end
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
