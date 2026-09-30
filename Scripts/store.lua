-- Per-character wardrobe selections. Stored next to the mod, never in game saves.
-- File format (one entry per line):
--   Head=ITEM_...      chosen appearance
--   Cape=HIDDEN        slot hidden
--   Held:Sword=ITEM_...  weapon look, one per weapon category
--   seen=ITEM_...      appearance the character has worn (counts as unlocked)
local S = { HIDDEN = 'HIDDEN' }
local SLOTS = { Head = true, Body = true, Legs = true, Cape = true }
local function isKey(key) return SLOTS[key] or key:match('^Held:%a+$') ~= nil end

local scripts = debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or ''
local modDir = scripts:gsub('[Ss]cripts[/\\]$', '')

local function exists(path)
    local f = io.open(path, 'r')
    if f then f:close() return true end
    return false
end

-- saves\ ships with the mod; fall back to the mod folder if it was removed.
local function saveDir()
    if S.dir then return S.dir end
    local probe = modDir .. 'saves\\.write-test'
    local f = io.open(probe, 'w')
    if f then
        f:close()
        pcall(os.remove, probe)
        S.dir = modDir .. 'saves\\'
    else
        S.dir = modDir
    end
    return S.dir
end

-- Full path of a helper file kept next to the character files.
function S.file(name) return saveDir() .. name end

local function parse(path)
    local data = { sel = {}, seen = {} }
    local f = io.open(path, 'r')
    if not f then return nil end
    for line in f:lines() do
        local key, value = line:match('^%s*([%w:]+)%s*=%s*([%w_]+)%s*$')
        if key == 'seen' and value:match('^ITEM_') then
            data.seen[value] = true
        elseif key and isKey(key) and (value == S.HIDDEN or value:match('^ITEM_')) then
            data.sel[key] = value
        end
    end
    f:close()
    return data
end

-- guid: 32 lowercase hex characters identifying the character.
function S.load(guid)
    local path = saveDir() .. 'wardrobe-' .. guid .. '.txt'
    local data = parse(path)
    if not data then
        -- 0.x builds kept the file inside Scripts\.
        local legacy = scripts .. 'wardrobe-' .. guid .. '.txt'
        data = parse(legacy)
        if data then
            S.save(guid, data)
            pcall(os.remove, legacy)
        end
    end
    return data or { sel = {}, seen = {} }
end

function S.save(guid, data)
    local path = saveDir() .. 'wardrobe-' .. guid .. '.txt'
    local tmp = path .. '.tmp'
    local f, err = io.open(tmp, 'w')
    if not f then return false, err end
    f:write('# RSE-Transmog selections\n')
    for _, slot in ipairs({ 'Head', 'Body', 'Legs', 'Cape' }) do
        if data.sel[slot] then f:write(slot, '=', data.sel[slot], '\n') end
    end
    local held = {}
    for key in pairs(data.sel) do
        if not SLOTS[key] and isKey(key) then held[#held + 1] = key end
    end
    table.sort(held)
    for _, key in ipairs(held) do f:write(key, '=', data.sel[key], '\n') end
    local seen = {}
    for id in pairs(data.seen) do seen[#seen + 1] = id end
    table.sort(seen)
    for _, id in ipairs(seen) do f:write('seen=', id, '\n') end
    f:close()
    -- Windows rename does not overwrite, so remove the old file first.
    if exists(path) then os.remove(path) end
    local ok, renameErr = os.rename(tmp, path)
    if not ok then return false, renameErr end
    return true
end

return S
