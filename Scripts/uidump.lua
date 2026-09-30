-- Developer tool: "transmog_dumpui" in the game console writes the game's
-- UI building blocks to <mod>\ui-dump.txt, used to rebuild the wardrobe from
-- the game's own widgets (item slots, tabs, headers, tooltips):
--   * the live inventory screen's widget tree
--   * the designed widget tree of the crafting screen and its parts
--   * reflected properties and functions (with parameters) of each candidate
local D = {}

local CANDIDATES = {
    '/Game/UI/Inventory/WBP_Inventory_MainPanel',
    '/Game/UI/Inventory/WBP_Inventory_InventoryBody',
    '/Game/UI/Inventory/WBP_Inventory_ItemSlot',
    '/Game/UI/Inventory/WBP_InventoryTabButton',
    '/Game/UI/Inventory/WBP_Inventory_VerticalNavigation',
    '/Game/UI/Inventory/Tooltip/WBP_Inventory_Tooltip',
    '/Game/UI/Crafting/WBP_Crafting_MainPanel',
    '/Game/UI/Crafting/WBP_Crafting_NavigableTabButton',
    '/Game/UI/Crafting/WBP_Crafting_Tooltip',
    '/Game/UI/Crafting/Craft/WBP_Crafting_CategoryColleciton',
    '/Game/UI/Crafting/Craft/WBP_Crafting_CategoryContent',
    '/Game/UI/Crafting/Craft/WBP_Crafting_ItemCategory',
    '/Game/UI/Crafting/Craft/WBP_Crafting_ItemSlot',
    '/Game/UI/Crafting/Craft/WBP_Crafting_CraftPanel',
    '/Game/UI/Crafting/Craft/WBP_Crafting_RecipeInfo',
    '/Game/UI/Common/WBP_AccordionHeader',
    '/Game/UI/Common/WBP_DomButton',
    '/Game/UI/Common/WBP_DomButton_NoIcon',
    '/Game/UI/Common/WBP_DomTextBlock',
    '/Game/UI/Common/WBP_IconImage',
    '/Game/UI/Common/WBP_TitleOnlyTooltip',
}
-- Walk the designed trees of these (the rest only get their reflection dumped).
local TREES = {
    WBP_Crafting_MainPanel = true, WBP_Crafting_CraftPanel = true, WBP_Crafting_ItemSlot = true,
    WBP_Crafting_ItemCategory = true, WBP_Crafting_CategoryContent = true, WBP_Crafting_RecipeInfo = true,
    WBP_Crafting_NavigableTabButton = true, WBP_Inventory_ItemSlot = true, WBP_InventoryTabButton = true,
    WBP_AccordionHeader = true, WBP_Crafting_Tooltip = true,
}

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function fname(o)
    local s = get(function() return o:GetFName():ToString() end)
    return type(s) == 'string' and s or '?'
end
local function className(o)
    return get(function() return o:GetClass():GetFName():ToString() end) or '?'
end

local scripts = debug.getinfo(1, 'S').source:match('^@?(.*[/\\])') or ''
local modDir = scripts:gsub('[Ss]cripts[/\\]$', '')

-- Desired size of a widget: what it asks its parent for ("?" if unknown).
-- The drawn size is not read: passing FGeometry to SlateBlueprintLibrary
-- has crashed this game natively.
local function sizeOf(w)
    local desired = get(function() return w:GetDesiredSize() end)
    local dx, dy = get(function() return desired.X end), get(function() return desired.Y end)
    if type(dx) == 'number' and type(dy) == 'number' then
        return string.format('desired=%.0fx%.0f', dx, dy)
    end
    return '?'
end

local function walkWidget(w, depth, out, seen)
    if not valid(w) or depth > 30 then return end
    local key = get(function() return w:GetFullName() end) or tostring(w)
    if seen[key] then return end
    seen[key] = true
    local extra = ''
    local vis = get(function() return w:GetVisibility() end)
    if vis then extra = ' vis=' .. tostring(vis) end
    extra = extra .. ' size=' .. sizeOf(w)
    out(string.rep('  ', depth) .. fname(w) .. ' : ' .. className(w) .. extra)
    local n = get(function() return w:GetChildrenCount() end)
    if type(n) == 'number' then
        for i = 0, n - 1 do walkWidget(get(function() return w:GetChildAt(i) end), depth + 1, out, seen) end
    end
    -- A nested user widget has its own tree.
    local tree = get(function() return w.WidgetTree end)
    local root = valid(tree) and get(function() return tree.RootWidget end)
    if valid(root) then
        out(string.rep('  ', depth + 1) .. '[inner tree]')
        walkWidget(root, depth + 2, out, seen)
    end
end

local function dumpReflection(cls, out)
    local c, level = cls, 0
    while valid(c) and level < 12 do
        local cname = fname(c)
        out('  -- class ' .. cname)
        if cname == 'UserWidget' or cname == 'Widget' or cname == 'Object' then break end
        pcall(function()
            c:ForEachProperty(function(prop)
                out('    prop ' .. fname(prop) .. ' : ' .. (get(function() return prop:GetClass():GetFName():ToString() end) or '?'))
            end)
        end)
        pcall(function()
            c:ForEachFunction(function(fn)
                local params = {}
                pcall(function()
                    fn:ForEachProperty(function(p)
                        params[#params + 1] = fname(p) .. ':' .. (get(function() return p:GetClass():GetFName():ToString() end) or '?')
                    end)
                end)
                out('    func ' .. fname(fn) .. '(' .. table.concat(params, ', ') .. ')')
            end)
        end)
        c = get(function() return c:GetSuperStruct() end)
        level = level + 1
    end
end

function D.run()
    local file = modDir .. 'ui-dump.txt'
    local f = io.open(file, 'w')
    if not f then return 'could not write ' .. file end
    local function out(s) f:write(s, '\n') end

    out('== live inventory panels')
    for _, panel in ipairs(FindAllOf('InventoryMainPanel') or {}) do
        out('# ' .. (get(function() return panel:GetFullName() end) or '?'))
        walkWidget(get(function() return panel.WidgetTree.RootWidget end), 1, out, {})
    end

    for _, p in ipairs(CANDIDATES) do
        local short = p:match('([^/]+)$')
        local ok, cls = pcall(LoadAsset, p .. '.' .. short .. '_C')
        out('')
        out('== ' .. short .. (ok and valid(cls) and '' or '  (not loaded)'))
        if ok and valid(cls) then
            if TREES[short] then
                local tree = get(function() return cls.WidgetTree end)
                local root = valid(tree) and get(function() return tree.RootWidget end)
                if valid(root) then
                    out('  [designed tree]')
                    walkWidget(root, 2, out, {})
                else
                    out('  [designed tree unavailable]')
                end
            end
            dumpReflection(cls, out)
        end
    end
    f:close()
    return 'written to ' .. file
end

return D
