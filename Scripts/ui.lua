-- Wardrobe panel injected into the inventory screen.
--
-- Everything the player sees is drawn with plain UMG widgets (Border, Image,
-- TextBlock) using the game's own fonts. Each clickable cell carries an
-- invisible game button on top: it supplies mouse/gamepad input and the click
-- sound, and its click is the one UFunction we can hook. The game button's own
-- visuals are not used because its label layer does not follow scrolling.
local H = require('UEHelpers')
local Cfg = require('config')
local I = require('i18n')
local C = require('catalog')
local V = require('visual')
local t = I.t

local U = { views = {}, actions = {}, slot = 'Body', showLocked = Cfg.ShowLockedByDefault ~= false }
local SLOTS = V.SLOTS
local HIDEABLE = { Head = true, Cape = true }
local BUTTON_CLASS = '/Game/UI/Common/WBP_DomButton_NoIcon.WBP_DomButton_NoIcon_C'
local FONTS = {
    regular = '/Game/UI/Fonts/Poppins-Regular_Font.Poppins-Regular_Font',
    medium = '/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font',
}
local VISIBLE, COLLAPSED, HIT_TEST_INVISIBLE, SELF_HIT_TEST_INVISIBLE = 0, 1, 3, 4
local H_FILL, H_LEFT, H_CENTER = 0, 1, 2
local V_FILL, V_CENTER = 0, 2
local FILL = { SizeRule = 1, Value = 1 }
local COLUMNS = 2

local COLOR = {
    frame    = { R = 0.36, G = 0.28, B = 0.15, A = 1 },
    panel    = { R = 0.030, G = 0.026, B = 0.022, A = 0.97 },
    cell     = { R = 0.075, G = 0.066, B = 0.056, A = 1 },
    hover    = { R = 0.150, G = 0.122, B = 0.080, A = 1 },
    selected = { R = 0.330, G = 0.240, B = 0.090, A = 1 },
    selHover = { R = 0.400, G = 0.295, B = 0.115, A = 1 },
    input    = { R = 0.100, G = 0.088, B = 0.074, A = 1 },
    gold     = { R = 0.96, G = 0.82, B = 0.50, A = 1 },
    text     = { R = 0.88, G = 0.85, B = 0.78, A = 1 },
    dim      = { R = 0.58, G = 0.55, B = 0.50, A = 1 },
    locked   = { R = 0.48, G = 0.45, B = 0.41, A = 1 },
}
-- Inventory grid area relative to the armour panel, measured on CL-240163.
-- Used only if the live layout cannot be read.
local FALLBACK_MENU = { Left = 0, Top = -413, Right = 613, Bottom = 420 }

local function log(s) print('[DragonwildsWardrobe/UI] ' .. tostring(s) .. '\n') end
local function valid(o) return o ~= nil and o:IsValid() end
local function name(o) return valid(o) and o:GetFullName() or '' end
local function textOf(value)
    local ok, s = pcall(function() return value:ToString() end)
    return ok and type(s) == 'string' and s or ''
end

local function widget(kind, outer)
    local cls = StaticFindObject('/Script/UMG.' .. kind)
    assert(valid(cls), 'Missing UMG class ' .. kind)
    return StaticConstructObject(cls, outer)
end

local function add(parent, child)
    if parent:IsA('/Script/UMG.VerticalBox') then return parent:AddChildToVerticalBox(child) end
    if parent:IsA('/Script/UMG.HorizontalBox') then return parent:AddChildToHorizontalBox(child) end
    if parent:IsA('/Script/UMG.Overlay') then return parent:AddChildToOverlay(child) end
    if parent:IsA('/Script/UMG.UniformGridPanel') then return parent:AddChildToUniformGrid(child, 0, 0) end
    return parent:AddChild(child)
end

local function pad(slot, l, tp, r, b)
    pcall(function() slot:SetPadding({ Left = l, Top = tp, Right = r, Bottom = b }) end)
end
local function size(slot, rule) pcall(function() slot:SetSize(rule) end) end
local function align(slot, h, v)
    if h then pcall(function() slot:SetHorizontalAlignment(h) end) end
    if v then pcall(function() slot:SetVerticalAlignment(v) end) end
end

local fontCache = {}
local function font(kind)
    if fontCache[kind] == nil then
        local ok, f = pcall(LoadAsset, FONTS[kind])
        fontCache[kind] = ok and valid(f) and f or false
    end
    return fontCache[kind] or nil
end

-- Styles must be set before the widget is added to a live parent.
local function newText(view, sizePx, color, weight)
    local tb = widget('TextBlock', view.tree)
    pcall(function()
        local f = font(weight or 'regular')
        if f then tb.Font.FontObject = f end
    end)
    pcall(function() tb.Font.Size = sizePx end)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    pcall(function() tb:SetTextOverflowPolicy(1) end) -- ellipsis
    return tb
end

local function setText(tb, s, cache)
    if cache and cache.text == s then return end
    local ok, err = pcall(function() tb:SetText(FText(s)) end)
    if ok then
        if cache then cache.text = s end
    else
        log('text: ' .. tostring(err))
    end
end

local function setTextColor(tb, color)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

local function gameButton(view, parent, title, action, minW, minH)
    local cls = LoadAsset(BUTTON_CLASS)
    assert(valid(cls), 'Native button asset missing')
    local library = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local b = library:Create(H.GetWorld(), cls, H.GetPlayerController())
    local slot = add(parent, b)
    b:SetMinDimensions(minW or 10, minH or 10)
    b:SetLabelText(FText(title))
    if action then
        local key = name(b)
        U.actions[key] = action
        view.actionKeys[#view.actionKeys + 1] = key
    end
    return b, slot
end

-- ------------------------------------------------------------------ cells

local function paint(c)
    local bg
    if c.selected then bg = c.hovered and COLOR.selHover or COLOR.selected
    else bg = c.hovered and COLOR.hover or COLOR.cell end
    if c.paintedBg ~= bg then
        c.paintedBg = bg
        c.bg:SetBrushColor(bg)
    end
    local fg = c.selected and COLOR.gold or (c.locked and COLOR.locked or COLOR.text)
    if c.paintedFg ~= fg then
        c.paintedFg = fg
        setTextColor(c.text, fg)
    end
end

-- A clickable cell: [icon] label, with an invisible game button on top.
-- opts: height, textSize, weight, center (bool), icon (bool), action (function)
local function newCell(view, parent, opts)
    local overlay = widget('Overlay', view.tree)
    local sizeBox = widget('SizeBox', view.tree)
    sizeBox:SetHeightOverride(opts.height or 36)
    sizeBox:SetContent(overlay)

    local bg = widget('Border', view.tree)
    bg:SetBrushColor(COLOR.cell)
    bg:SetPadding({ Left = 8, Top = 2, Right = 8, Bottom = 2 })
    pcall(function() bg:SetVerticalAlignment(V_CENTER) end)
    local bgSlot = overlay:AddChildToOverlay(bg)
    align(bgSlot, H_FILL, V_FILL)
    local row = widget('HorizontalBox', view.tree)
    bg:SetContent(row)

    local c = { sizeBox = sizeBox, bg = bg }
    if opts.icon then
        local iconBox = widget('SizeBox', view.tree)
        iconBox:SetWidthOverride(30)
        iconBox:SetHeightOverride(30)
        local iconSlot = add(row, iconBox)
        align(iconSlot, nil, V_CENTER)
        pad(iconSlot, 0, 0, 8, 0)
        iconBox:SetVisibility(COLLAPSED)
        c.iconBox = iconBox
    end
    c.text = newText(view, opts.textSize or 13, COLOR.text, opts.weight)
    local textSlot = add(row, c.text)
    size(textSlot, FILL)
    align(textSlot, opts.center and H_CENTER or H_LEFT, V_CENTER)
    pcall(function() c.text:SetJustification(opts.center and 1 or 0) end)

    local hit, hitSlot = gameButton(view, overlay, '', opts.action, 10, 10)
    align(hitSlot, H_FILL, V_FILL)
    hit:SetRenderOpacity(0)
    c.hit = hit

    c.slot = add(parent, sizeBox)
    paint(c)
    view.cells[#view.cells + 1] = c
    return c
end

local function setIcon(view, c, texture)
    if not c.iconBox or not texture then return end
    local ok = pcall(function()
        local image = widget('Image', view.tree)
        image:SetBrushFromTexture(texture, false)
        c.iconBox:SetContent(image)
    end)
    if ok then c.iconBox:SetVisibility(HIT_TEST_INVISIBLE) end
end

local function setCell(c, label, selected, locked)
    setText(c.text, label, c)
    if c.selected ~= selected or c.locked ~= locked then
        c.selected, c.locked = selected, locked
        paint(c)
    end
end

-- ---------------------------------------------------------------- helpers

local function progressComponent()
    local ok, progress = pcall(function() return H.GetPlayerController():GetProgressComponent() end)
    return ok and valid(progress) and progress or nil
end

local function entryName(slot, value)
    if value == nil then return t('original') end
    if value == V.HIDDEN then return t('hidden') end
    local entry = C.find(slot, value)
    return entry and entry.name or value
end

local function status(view, message)
    view.message = message and { slot = U.slot, text = message, expires = os.clock() + 4 } or nil
end

-- --------------------------------------------------------------- rendering

function U.refreshStatus(view)
    if view.message and (view.message.slot ~= U.slot or os.clock() >= view.message.expires) then
        view.message = nil
    end
    local line
    if view.message then
        line = view.message.text
    else
        local actual = V.actual(U.slot)
        if not actual then
            line = t('empty')
        else
            local real = textOf(actual.Name)
            line = t('equipped', real ~= '' and real or t('nothing'), entryName(U.slot, V.sel[U.slot]))
        end
    end
    setText(view.status, line, view.statusCache)
end

function U.refresh(view)
    local slot = U.slot
    local data = view.slots[slot]
    if not data then return end
    local query = textOf(view.search:GetText()):lower()
    local current = V.sel[slot]
    local shown, total, position = 0, 0, 0

    for _, row in ipairs(data.rows) do
        local isCurrent, label, visible, locked = false, nil, true, false
        if row.kind == 'original' then
            isCurrent, label = current == nil, t('original')
        elseif row.kind == 'hidden' then
            isCurrent, label = current == V.HIDDEN, t('hide')
        else
            local e = row.entry
            locked = not e.unlocked
            isCurrent, label = current == e.id, e.name
            local allowed = not e.restricted or e.unlocked
            local matches = query == '' or e.name:lower():find(query, 1, true) ~= nil
            if allowed then total = total + 1 end
            visible = allowed and matches and (U.showLocked or not locked)
            if visible then shown = shown + 1 end
        end
        setCell(row.cell, label, isCurrent, locked)
        if row.visible ~= visible then
            row.visible = visible
            row.cell.sizeBox:SetVisibility(visible and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
        end
        if visible then
            -- Visible cells are packed left-to-right, top-to-bottom.
            local r, col = position // COLUMNS, position % COLUMNS
            if row.r ~= r or row.col ~= col then
                row.r, row.col = r, col
                row.cell.slot:SetRow(r)
                row.cell.slot:SetColumn(col)
            end
            position = position + 1
        end
    end

    for _, s in ipairs(SLOTS) do
        setCell(view.tabs[s], t(s), s == slot, false)
    end
    setCell(view.lockedCell, U.showLocked and t('lockedShown') or t('lockedHidden'), not U.showLocked, false)
    setText(view.count, t('count', shown, total), view.countCache)
    U.refreshStatus(view)
end

local function choose(view, slot, kind, entry)
    local value
    if kind == 'hidden' then value = V.HIDDEN
    elseif kind == 'item' then value = entry.id end
    local ok, err = V.set(slot, value)
    if ok then
        status(view, err == 'empty' and t('empty') or t('applied', entryName(slot, value)))
    else
        status(view, t(err == 'noCharacter' and 'noCharacter' or 'failed'))
    end
    U.refresh(view)
end

local function buildSlot(view, slot)
    local grid = widget('UniformGridPanel', view.tree)
    pcall(function() grid:SetSlotPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 }) end)
    local gridSlot = add(view.list, grid)
    align(gridSlot, H_FILL, nil)
    local data = { grid = grid, rows = {} }

    local function row(kind, entry)
        local r = { kind = kind, entry = entry }
        r.cell = newCell(view, grid, {
            height = 40, icon = true,
            action = function() choose(view, slot, kind, entry) end,
        })
        if entry then setIcon(view, r.cell, entry.icon) end
        data.rows[#data.rows + 1] = r
    end

    row('original')
    if HIDEABLE[slot] then row('hidden') end
    for _, entry in ipairs(C.prepare(slot)) do row('item', entry) end
    view.slots[slot] = data
    return data
end

function U.showSlot(view, slot)
    U.slot = slot
    view.message = nil
    local data = view.slots[slot] or buildSlot(view, slot)
    for s, other in pairs(view.slots) do
        other.grid:SetVisibility(s == slot and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
    end
    C.refreshUnlocked(slot, V.seen, progressComponent())
    pcall(function() view.list:ScrollToStart() end)
    U.refresh(view)
end

local function setMenu(view, open)
    view.menuOpen = open
    view.menu:SetVisibility(open and VISIBLE or COLLAPSED)
    view.toggle:SetLabelText(FText(open and t('back') or t('wardrobe')))
    if open then
        local ok, err = pcall(U.showSlot, view, U.slot)
        if not ok then log('open: ' .. tostring(err)) end
    end
end

-- ------------------------------------------------------------------ layout

-- Finds the inventory grid panel (same column as the armour panel, above it)
-- and returns its layout in the inventory root canvas, so the wardrobe covers
-- it exactly at any resolution or UI scale.
local function menuLayout(panel, armour)
    local a = armour.Slot:GetLayout()
    local ok, layout = pcall(function()
        local root = panel.WidgetTree.RootWidget
        for i = 0, root:GetChildrenCount() - 1 do
            local child = root:GetChildAt(i)
            if valid(child) and name(child) ~= name(armour) then
                local okLayout, l = pcall(function() return child.Slot:GetLayout() end)
                local o = okLayout and l.Offsets
                if o and math.abs(o.Left - a.Offsets.Left) < 2 and o.Top < a.Offsets.Top
                    and math.abs(o.Right - a.Offsets.Right) < 2 and o.Bottom > 200 then
                    return l
                end
            end
        end
    end)
    if ok and layout then return layout.Anchors, layout.Alignment, layout.Offsets end
    local o = a.Offsets
    return a.Anchors, a.Alignment, {
        Left = o.Left + FALLBACK_MENU.Left, Top = o.Top + FALLBACK_MENU.Top,
        Right = FALLBACK_MENU.Right, Bottom = FALLBACK_MENU.Bottom,
    }
end

-- The menu must live in the inventory root canvas: anything parented to the
-- armour panel is drawn below the inventory grid and never receives input.
local function placeMenu(panel, armour, fallbackCanvas, menu)
    local ok, err = pcall(function()
        local root = panel.WidgetTree.RootWidget
        assert(root:IsA('/Script/UMG.CanvasPanel'), 'inventory root is not a canvas')
        local anchors, alignment, offsets = menuLayout(panel, armour)
        local slot = root:AddChildToCanvas(menu)
        slot:SetAnchors(anchors)
        slot:SetAlignment(alignment)
        slot:SetOffsets(offsets)
        slot:SetZOrder(1000)
    end)
    if ok then return end
    log('menu placement fallback: ' .. tostring(err))
    local slot = fallbackCanvas:AddChildToCanvas(menu)
    slot:SetOffsets(FALLBACK_MENU)
    slot:SetZOrder(21)
end

local function buildSearch(view, parent)
    local search = widget('EditableTextBox', view.tree)
    pcall(function() search.WidgetStyle.TextStyle.Font.Size = 13 end)
    pcall(function()
        local f = font('regular')
        if f then search.WidgetStyle.TextStyle.Font.FontObject = f end
    end)
    pcall(function() search.WidgetStyle.BackgroundColor = { SpecifiedColor = COLOR.input, ColorUseRule = 0 } end)
    pcall(function() search.WidgetStyle.ForegroundColor = { SpecifiedColor = COLOR.text, ColorUseRule = 0 } end)
    pcall(function() search.WidgetStyle.Padding = { Left = 10, Top = 7, Right = 10, Bottom = 7 } end)
    search:SetHintText(FText(t('search')))
    local slot = add(parent, search)
    pcall(function() search:SetForegroundColor(COLOR.text) end)
    return search, slot
end

function U.mount(panel)
    if not valid(panel) then return end
    local key = name(panel)
    if U.views[key] and valid(U.views[key].toggle) then return end
    local tree = panel.WidgetTree
    local armour = panel.BackgroundPanelArmour
    assert(valid(armour), 'Armour panel unavailable')
    local overlay = armour.WidgetTree.RootWidget:GetChildAt(0)
    assert(valid(overlay) and overlay:IsA('/Script/UMG.Overlay'), 'Armour overlay unavailable')
    local view = {
        panel = panel, armour = armour, tree = tree, slots = {}, tabs = {}, cells = {},
        actionKeys = {}, statusCache = {}, countCache = {},
    }
    U.views[key] = view

    -- The toggle is parented to the armour panel so it follows its open/close animation.
    local canvas = widget('CanvasPanel', armour.WidgetTree)
    overlay:AddChildToOverlay(canvas)
    local toggleBox = widget('VerticalBox', tree)
    local toggleSlot = canvas:AddChildToCanvas(toggleBox)
    toggleSlot:SetOffsets({ Left = 389, Top = 14, Right = 200, Bottom = 42 })
    toggleSlot:SetZOrder(20)
    view.toggleBox = toggleBox
    view.toggle = gameButton(view, toggleBox, t('wardrobe'), function() setMenu(view, not view.menuOpen) end, 200, 42)

    -- Frame: 1px gold outline around the dark panel.
    local frame = widget('Border', tree)
    frame:SetBrushColor(COLOR.frame)
    frame:SetPadding({ Left = 1, Top = 1, Right = 1, Bottom = 1 })
    local body = widget('Border', tree)
    body:SetBrushColor(COLOR.panel)
    body:SetPadding({ Left = 12, Top = 10, Right = 12, Bottom = 10 })
    frame:SetContent(body)
    view.menu = frame
    local column = widget('VerticalBox', tree)
    body:SetContent(column)

    -- Header: title + close
    local header = widget('HorizontalBox', tree)
    add(column, header)
    local title = newText(view, 20, COLOR.gold, 'medium')
    local titleSlot = add(header, title)
    size(titleSlot, FILL)
    align(titleSlot, nil, V_CENTER)
    setText(title, t('wardrobe'))
    local close = newCell(view, header, { height = 30, textSize = 12, center = true, action = function() setMenu(view, false) end })
    close.sizeBox:SetWidthOverride(96)
    align(close.slot, nil, V_CENTER)
    setCell(close, t('close'), false, false)

    -- Slot tabs
    local tabs = widget('HorizontalBox', tree)
    pad(add(column, tabs), 0, 8, 0, 0)
    for i, slot in ipairs(SLOTS) do
        local tab = newCell(view, tabs, {
            height = 34, textSize = 14, center = true, weight = 'medium',
            action = function() U.showSlot(view, slot) end,
        })
        size(tab.slot, FILL)
        pad(tab.slot, i == 1 and 0 or 3, 0, 0, 0)
        view.tabs[slot] = tab
    end

    -- Current slot status
    view.status = newText(view, 12, COLOR.dim)
    pad(add(column, view.status), 2, 8, 2, 4)

    -- Search + locked filter
    local tools = widget('HorizontalBox', tree)
    pad(add(column, tools), 0, 0, 0, 6)
    local search, searchSlot = buildSearch(view, tools)
    size(searchSlot, FILL)
    align(searchSlot, nil, V_CENTER)
    view.search = search
    view.lockedCell = newCell(view, tools, {
        height = 34, textSize = 12, center = true,
        action = function()
            U.showLocked = not U.showLocked
            U.refresh(view)
        end,
    })
    view.lockedCell.sizeBox:SetWidthOverride(180)
    pad(view.lockedCell.slot, 6, 0, 0, 0)
    align(view.lockedCell.slot, nil, V_CENTER)

    -- Appearance grid
    local list = widget('ScrollBox', tree)
    pcall(function() list:SetScrollbarThickness({ X = 6, Y = 6 }) end)
    local listSlot = add(column, list)
    size(listSlot, FILL)
    view.list = list

    -- Footer: count + resets
    local footer = widget('HorizontalBox', tree)
    pad(add(column, footer), 0, 8, 0, 0)
    view.count = newText(view, 11, COLOR.dim)
    local countSlot = add(footer, view.count)
    size(countSlot, FILL)
    align(countSlot, nil, V_CENTER)
    local resetSlot = newCell(view, footer, {
        height = 32, textSize = 12, center = true,
        action = function() choose(view, U.slot, 'original') end,
    })
    resetSlot.sizeBox:SetWidthOverride(150)
    setCell(resetSlot, t('resetSlot'), false, false)
    local resetAll
    resetAll = newCell(view, footer, {
        height = 32, textSize = 12, center = true,
        action = function()
            if view.confirmUntil and os.clock() < view.confirmUntil then
                view.confirmUntil = nil
                setCell(resetAll, t('resetAll'), false, false)
                local ok, err = V.resetAll()
                status(view, ok and t('resetDone') or t(err == 'noCharacter' and 'noCharacter' or 'failed'))
                U.refresh(view)
            else
                view.confirmUntil = os.clock() + 3
                setCell(resetAll, t('confirm'), true, false)
            end
        end,
    })
    resetAll.sizeBox:SetWidthOverride(190)
    pad(resetAll.slot, 6, 0, 0, 0)
    setCell(resetAll, t('resetAll'), false, false)
    view.resetAll = resetAll

    placeMenu(panel, armour, canvas, frame)
    frame:SetVisibility(COLLAPSED)
    view.menuOpen = false
    log('mounted on ' .. key)
end

-- -------------------------------------------------------------------- tick

local function forget(key)
    local view = U.views[key]
    for _, actionKey in ipairs(view.actionKeys) do U.actions[actionKey] = nil end
    U.views[key] = nil
end

local function inventoryOpen(view)
    -- The game keeps InventoryMainPanel alive after closing; the armour
    -- background image is what the native UI collapses.
    local ok, open = pcall(function()
        local image = view.armour.BackgroundPanel
        return image:GetVisibility() == VISIBLE and image:GetRenderOpacity() > 0.1
    end)
    return ok and open
end

function U.tick()
    for key, view in pairs(U.views) do
        if not valid(view.panel) or not valid(view.toggleBox) then
            forget(key)
        else
            local open = inventoryOpen(view)
            if open ~= view.inventoryOpen then
                view.inventoryOpen = open
                view.toggleBox:SetVisibility(open and VISIBLE or COLLAPSED)
                if not open and view.menuOpen then setMenu(view, false) end
                if open then V.syncPreview(true) end
            end
            if open then
                V.syncPreview()
                if view.menuOpen then
                    local query = textOf(view.search:GetText())
                    if query ~= view.lastQuery then
                        view.lastQuery = query
                        U.refresh(view)
                    else
                        U.refreshStatus(view)
                    end
                    if view.confirmUntil and os.clock() >= view.confirmUntil then
                        view.confirmUntil = nil
                        setCell(view.resetAll, t('resetAll'), false, false)
                    end
                end
            end
        end
    end
end

-- Hover highlight, polled quickly while the wardrobe is open.
function U.hover()
    for _, view in pairs(U.views) do
        if view.menuOpen then
            for _, c in ipairs(view.cells) do
                local ok, hovered = pcall(function() return c.hit:IsValid() and c.hit:IsHovered() end)
                hovered = ok and hovered == true
                if c.hovered ~= hovered then
                    c.hovered = hovered
                    paint(c)
                end
            end
        end
    end
end

function U.start()
    RegisterHook('/Script/Dominion.InventoryMainPanel:HandleToggle', function(ctx)
        local view = U.views[name(ctx:get())]
        if view and view.menuOpen then setMenu(view, false) end
    end)
    RegisterHook('/Script/CommonUI.CommonButtonBase:HandleButtonClicked', function(ctx)
        local action = U.actions[name(ctx:get())]
        if action then
            local ok, err = pcall(action)
            if not ok then log('button: ' .. tostring(err)) end
        end
    end)
    NotifyOnNewObject('/Script/Dominion.InventoryMainPanel', function(panel)
        ExecuteWithDelay(500, function()
            ExecuteInGameThread(function()
                local ok, err = pcall(U.mount, panel)
                if not ok then log('mount: ' .. tostring(err)) end
            end)
        end)
    end)
    for _, panel in ipairs(FindAllOf('InventoryMainPanel') or {}) do
        local ok, err = pcall(U.mount, panel)
        if not ok then log('mount: ' .. tostring(err)) end
    end
end

return U
