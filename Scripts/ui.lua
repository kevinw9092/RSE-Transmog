-- Wardrobe panel injected into the inventory screen.
--
-- Two looks, one logic:
--   native  (default) its own window beside the inventory, drawn with the
--           inventory frame's art (copied brushes), with square icon slots and
--           icon tabs in the inventory's style and the game's gold buttons. Slots are plain UMG: game widgets with
--           their own C++ logic (crafting slots/tabs) crashed the game when
--           used without the recipe data they expect.
--   classic plain UMG widgets (Border, Image, TextBlock) in the game's fonts,
--           each cell with an invisible game button on top for input.
-- Every click arrives through the one hookable UFunction,
-- CommonButtonBase:HandleButtonClicked.
local H = require('UEHelpers')
local I = require('i18n')
local C = require('catalog')
local V = require('visual')
local S = require('store')
local Cfg = require('config')
local Dock = require('rse_dock')
-- Id of this mod's icon in RSE-Dock's bar (RSEDock.active holds it while open).
local DOCK_ID = 'transmog'
local t = I.t

local U = { views = {}, actions = {}, slot = 'Body' }
-- Wardrobe tabs. Weapon tabs edit the look of the item category held in that
-- hand (Held:Sword, Held:Shield, ...), so each weapon type keeps its own look.
local TABS = { 'Head', 'Body', 'Legs', 'Cape', 'MainHand', 'OffHand' }
local HIDEABLE = { Head = true, Cape = true } -- plus every weapon type
local BUTTON_CLASS = '/Game/UI/Common/WBP_DomButton_NoIcon.WBP_DomButton_NoIcon_C'
-- Tab icons when nothing is equipped in that slot: a typical item's icon.
local TAB_ICON = {
    Head = { 'Head', 'ITEM_Armour_T3_Head_Bronze' }, Body = { 'Body', 'ITEM_Armour_T3_Body_Bronze' },
    Legs = { 'Legs', 'ITEM_Armour_T3_Legs_Bronze' }, Cape = { 'Cape', 'ITEM_Cape_Adventurers_Red' },
    MainHand = { 'Held:Sword', 'ITEM_Sword_Bronze' }, OffHand = { 'Held:Shield', 'ITEM_Shield_Wood' },
}
local NATIVE_COLUMNS = 4
local CELL_HEIGHT, CELL_ICON, TAB_SIZE = 104, 76, 50
-- Window spacing, shared with RSE-Toolbag's ui.lua (keep both in sync). The
-- content sits at the inventory frame's own inset times FRAME_INSET (RSE-Dock
-- uses the same factor for its shared window), plus CONTENT_PAD.
local FRAME_INSET = 0.9
local CONTENT_PAD = 0 -- window inset to the content
local ROW_GAP = 6     -- between rows: title/Close, search, grid, footer; and tabs to grid
local CELL_PAD = 2    -- grid slot padding: cells are 2 * CELL_PAD apart
local BUTTON_W, BUTTON_H, TITLE_SIZE = 90, 34, 15 -- Close and footer buttons, title text
-- While the native wardrobe is open this file exists. If the game closes with
-- it still there, the next launch uses the classic look instead.
local UI_LOCK = 'ui-native.lock'
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
    -- Square slots: the game's slot art underneath (see copySlotArt); `slot`
    -- only if that cannot be copied. Hover and selection are drawn over it.
    slot         = { R = 0.040, G = 0.036, B = 0.031, A = 0.92 },
    slotHover    = { R = 0.150, G = 0.120, B = 0.075, A = 0.45 },
    slotSelected = { R = 0.190, G = 0.145, B = 0.070, A = 0.95 },
    hoverEdge    = { R = 0.520, G = 0.420, B = 0.240, A = 1 },
    clear        = { R = 0, G = 0, B = 0, A = 0 },
}
-- Inventory grid area relative to the armour panel, measured on CL-240163.
-- Used only if the live layout cannot be read.
local FALLBACK_MENU = { Left = 0, Top = -413, Right = 613, Bottom = 420 }

local function log(s) print('[RSE-Transmog/UI] ' .. tostring(s) .. '\n') end
local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function name(o) return valid(o) and o:GetFullName() or '' end
local function textOf(value)
    local ok, s = pcall(function() return value:ToString() end)
    return ok and type(s) == 'string' and s or ''
end

-- Top-level widgets the mod adds to the game's panels carry this name prefix,
-- so a later instance (after a UE4SS hot reload) can find and remove them.
local TAG = 'RSETransmog_'
-- Tags of earlier builds, still cleaned up after a hot reload.
local STALE_TAGS = { TAG, 'DWWardrobe_' }
local tagCount = 0

local function widget(kind, outer, tag)
    local cls = StaticFindObject('/Script/UMG.' .. kind)
    assert(valid(cls), 'Missing UMG class ' .. kind)
    if tag then
        -- Unique per instance: reusing a live object's name inside the same outer is fatal.
        tagCount = tagCount + 1
        -- Time plus milliseconds: a reloaded instance restarts tagCount, and the
        -- widgets it just removed still exist until garbage collection.
        return StaticConstructObject(cls, outer, FName(string.format('%s%s_%d_%d_%d',
            TAG, tag, os.time(), math.floor(os.clock() * 1000), tagCount)))
    end
    return StaticConstructObject(cls, outer)
end

-- Removes widgets a previous instance of the mod left in `parent`.
local function removeStale(parent)
    local n = valid(parent) and parent:GetChildrenCount() or 0
    for i = n - 1, 0, -1 do
        local child = parent:GetChildAt(i)
        local childName = valid(child) and child:GetFName():ToString() or ''
        local stale = false
        for _, tag in ipairs(STALE_TAGS) do
            if childName:sub(1, #tag) == tag then stale = true end
        end
        if stale then
            pcall(function() child:RemoveFromParent() end)
            log('removed leftover ' .. childName)
        end
    end
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
    -- cache.shownText, not cache.text: cells pass themselves as the cache and
    -- keep their TextBlock in .text.
    if not valid(tb) then return end
    if cache and cache.shownText == s then return end
    local ok, err = pcall(function() tb:SetText(FText(s)) end)
    if ok then
        if cache then cache.shownText = s end
    else
        log('text: ' .. tostring(err))
    end
end

local function setTextColor(tb, color)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

-- Creates one of the game's Widget Blueprints.
local classCache = {}
local function userWidget(classPath)
    local cls = classCache[classPath]
    if not valid(cls) then
        cls = LoadAsset(classPath)
        assert(valid(cls), 'Game widget missing: ' .. classPath)
        classCache[classPath] = cls
    end
    local library = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local world = H.GetWorld()
    -- The owner must be a player controller of this world. While a world is
    -- loading, a cached controller can still be the main menu's, and the
    -- engine then refuses to create the widget, so try the fresh one first.
    for _, owner in ipairs({ H.GetPlayerController(), V.localController() }) do
        local w = get(function() return library:Create(world, cls, owner) end)
        if valid(w) then return w end
    end
    error('Could not create ' .. classPath)
end

local function onClick(view, button, action)
    if not action then return end
    local key = name(button)
    U.actions[key] = action
    view.actionKeys[#view.actionKeys + 1] = key
end

-- The game button left-aligns its label (with a left padding and a spacer
-- taking the rest of the row) and does not grow to fit it. Centre the label
-- and fill the button; re-applied after every label change.
local function centerLabel(b)
    pcall(function() b.bCenterAlignText = true end)
    pcall(function() b.LeftAlignTextPadding = 0 end)
    local label = get(function() return b.LabelText end)
    if not valid(label) then return end
    pcall(function() label:SetJustification(1) end) -- centre
    -- The label's own slot carries the left inset (set when the button is
    -- built, so LeftAlignTextPadding alone does not remove it).
    pcall(function() label.Slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    pcall(function() label.Slot:SetHorizontalAlignment(H_CENTER) end)
    local box = get(function() return label:GetParent() end)
    if valid(box) then
        pcall(function() box.Slot:SetSize(FILL) end)
        pcall(function() box.Slot:SetHorizontalAlignment(H_CENTER) end)
        -- The row holding the label is only as wide as its content and sits
        -- left in the button: make it span the button so centring means centre.
        local row = get(function() return box:GetParent() end)
        if valid(row) then
            pcall(function() row.Slot:SetHorizontalAlignment(H_FILL) end)
        end
    end
end

-- Width that fits a label in the game button's font (no reliable layout
-- measurement exists before the first frame), for the longest of `labels`.
-- Measured in game: "Close" = 52 units of text, about 10.4 per character.
local function fitWidth(labels, minW)
    local longest = 0
    for _, s in ipairs(labels) do
        local n = utf8 and utf8.len(s) or #s
        if n and n > longest then longest = n end
    end
    return math.max(minW or 0, longest * 11 + 32)
end

local function setButtonLabel(b, text)
    pcall(function() b:SetLabelText(FText(text)) end)
    if text ~= '' then centerLabel(b) end
end

local function gameButton(view, parent, title, action, minW, minH, labels)
    local b = userWidget(BUTTON_CLASS)
    local slot = add(parent, b)
    local width = minW or 10
    if title ~= '' then width = fitWidth(labels or { title }, minW) end
    b:SetMinDimensions(width, minH or 10)
    setButtonLabel(b, title)
    onClick(view, b, action)
    if title ~= '' then
        -- Visible buttons: their own setup re-applies the left inset when they
        -- are first drawn, so they are re-centred after showing (U.recenter).
        view.buttons = view.buttons or {}
        view.buttons[#view.buttons + 1] = b
    end
    return b, slot
end

-- Re-centres a view's visible game buttons, now and on the next ticks.
function U.recenter(view, ticks)
    for _, b in ipairs(view.buttons or {}) do
        if valid(b) then centerLabel(b) end
    end
    if ticks then view.recenterTicks = math.max(view.recenterTicks or 0, ticks) end
end

-- ------------------------------------------------------------------ cells

local function paint(c)
    if not c.bg then return end
    if c.square then
        local edge = c.selected and COLOR.gold or (c.hovered and COLOR.hoverEdge or COLOR.clear)
        local fill = c.selected and COLOR.slotSelected or (c.hovered and COLOR.slotHover or COLOR.clear)
        if c.paintedEdge ~= edge then c.paintedEdge = edge; c.edge:SetBrushColor(edge) end
        if c.paintedBg ~= fill then c.paintedBg = fill; c.bg:SetBrushColor(fill) end
        return
    end
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

-- The game's inventory slot art, for the square cells: the idle brush of a
-- live inventory slot (WBP_Inventory_ItemSlot_C, a CommonUI button that draws
-- its background from its button style). Tried in order: the style's
-- NormalBase, the brush the slot draws now (NormalStyle.Normal), its
-- CommonSlotBackground texture or material. Only brush data is copied (a
-- struct holding the texture or material); the slot widget itself, with its
-- hover particles (NS_InventoryHighlight), is never created.
local SLOT_CLASS = 'WBP_Inventory_ItemSlot_C'
local slotSource, slotSearched, slotArtLogged = nil, -math.huge, false

local function paintable(brush)
    return get(function()
        if brush.DrawAs == 0 or not valid(brush.ResourceObject) then return false end -- 0 = no draw
        return brush.TintColor.ColorUseRule ~= 0 or brush.TintColor.SpecifiedColor.A > 0.01
    end) == true
end

-- A live inventory slot, searched again (at most every 2 s) once it is gone.
local function findSlotSource()
    if valid(slotSource) then return slotSource end
    if os.clock() - slotSearched < 2 then return nil end
    slotSearched, slotSource = os.clock(), nil
    for _, s in ipairs(get(function() return FindAllOf(SLOT_CLASS) end) or {}) do
        if valid(s) and not name(s):find('Default__', 1, true) then slotSource = s break end
    end
    return slotSource
end

-- Copies the slot art onto `image`; returns what was copied, or nil.
local function copySlotArt(image)
    local s = findSlotSource()
    if not s then return nil end
    local style = get(function() return s:GetStyle() end)
    for _, source in ipairs({
        { 'style NormalBase', function() return style.NormalBase end },
        { 'NormalStyle.Normal', function() return s.NormalStyle.Normal end },
    }) do
        local brush = get(source[2])
        if brush and paintable(brush) and pcall(function() image:SetBrush(brush) end)
            and valid(get(function() return image.Brush.ResourceObject end)) then
            return source[1]
        end
    end
    local resource = get(function() return s.CommonSlotBackground end)
    if valid(resource) then
        if get(function() return resource:IsA('/Script/Engine.Texture2D') end)
            and pcall(function() image:SetBrushFromTexture(resource, false) end) then
            return 'CommonSlotBackground'
        elseif get(function() return resource:IsA('/Script/Engine.MaterialInterface') end)
            and pcall(function() image:SetBrushFromMaterial(resource) end) then
            return 'CommonSlotBackground'
        end
    end
    return nil
end

-- Gives a square cell the slot art once it can be found (flat `slot` till then).
local function slotArt(c)
    if c.artCopied or not valid(c.art) then return end
    local copied = copySlotArt(c.art)
    if copied then
        pcall(function() c.art:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
        c.artCopied = true
        if not slotArtLogged then
            slotArtLogged = true
            log('slot art copied from ' .. name(slotSource) .. ' (' .. copied .. ')')
        end
    end
end

-- Square icon cell in the inventory's style: the game's slot art, icon
-- centred, gold fill and outline when selected, lighter on hover. Plain UMG
-- plus the same invisible game button as the classic cells (input, gamepad,
-- click sound). Game widgets with their own C++ logic (inventory and crafting
-- slots and tabs) are not used here: they expect item and recipe data behind
-- them.
local function squareCell(view, parent, opts)
    -- opts: width (nil = fill the grid column), height, icon (icon box size), action, note
    local sizeBox = widget('SizeBox', view.tree)
    if opts.width then sizeBox:SetWidthOverride(opts.width) end
    sizeBox:SetHeightOverride(opts.height)
    pcall(function() sizeBox:SetClipping(1) end) -- clip to bounds: nothing spills onto neighbours
    local overlay = widget('Overlay', view.tree)
    sizeBox:SetContent(overlay)

    -- Decoration never takes the mouse; only the invisible button on top does.
    local art = widget('Image', view.tree)
    pcall(function() art:SetColorAndOpacity(COLOR.slot) end)
    art:SetVisibility(HIT_TEST_INVISIBLE)
    align(overlay:AddChildToOverlay(art), H_FILL, V_FILL)
    -- Hover and selection: outline and fill over the art, clear when idle.
    local edge = widget('Border', view.tree)
    edge:SetBrushColor(COLOR.clear)
    edge:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
    local bg = widget('Border', view.tree)
    bg:SetBrushColor(COLOR.clear)
    pcall(function() bg:SetHorizontalAlignment(H_CENTER) end)
    pcall(function() bg:SetVerticalAlignment(V_CENTER) end)
    edge:SetContent(bg)
    edge:SetVisibility(HIT_TEST_INVISIBLE)
    align(overlay:AddChildToOverlay(edge), H_FILL, V_FILL)
    -- Square icon area, centred, whatever the cell's width.
    local iconBox = widget('SizeBox', view.tree)
    iconBox:SetWidthOverride(opts.icon)
    iconBox:SetHeightOverride(opts.icon)
    bg:SetContent(iconBox)

    local c = { square = true, sizeBox = sizeBox, art = art, edge = edge, bg = bg, iconArea = iconBox }
    slotArt(c)
    if opts.note then
        local label = newText(view, 10, COLOR.text, 'medium')
        setText(label, opts.note)
        label:SetVisibility(HIT_TEST_INVISIBLE)
        local labelSlot = overlay:AddChildToOverlay(label)
        align(labelSlot, H_CENTER, 3) -- bottom
        pad(labelSlot, 4, 0, 4, 4)
    end

    local hit, hitSlot = gameButton(view, overlay, '', opts.action, 10, 10)
    align(hitSlot, H_FILL, V_FILL)
    hit:SetRenderOpacity(0)
    c.hit = hit

    c.slot = add(parent, sizeBox)
    view.cells[#view.cells + 1] = c
    return c
end

local function nativeCell(view, parent, action, note)
    local c = squareCell(view, parent, { height = CELL_HEIGHT, icon = CELL_ICON, action = action, note = note })
    c.native = true -- a look: named in the details line on hover
    align(c.slot, H_FILL, V_FILL)
    return c
end

local function nativeTab(view, parent, action)
    local c = squareCell(view, parent, { width = TAB_SIZE, height = TAB_SIZE, icon = TAB_SIZE - 14, action = action })
    c.tab = true
    return c
end

-- A visible game button wrapped as a cell (label changes through setCell).
local function buttonCell(view, parent, title, action, minW, minH, labels)
    local b, slot = gameButton(view, parent, title, action, minW, minH, labels)
    return { button = true, widget = b, sizeBox = b, slot = slot, hit = b, shownText = title }
end

local function setIcon(view, c, texture)
    if not texture then return end
    if c.square then
        if c.iconTexture == texture then return end
        c.iconTexture = texture
        pcall(function()
            local image = c.image
            if not valid(image) then
                image = widget('Image', view.tree)
                c.image = image
                c.iconArea:SetContent(image)
            end
            image:SetBrushFromTexture(texture, false)
            image:SetVisibility(HIT_TEST_INVISIBLE)
        end)
        return
    end
    if not c.iconBox then return end
    local ok = pcall(function()
        local image = widget('Image', view.tree)
        image:SetBrushFromTexture(texture, false)
        c.iconBox:SetContent(image)
    end)
    if ok then c.iconBox:SetVisibility(HIT_TEST_INVISIBLE) end
end

local function setCell(c, label, selected, locked)
    if c.square then
        c.label = label
        if c.selected ~= selected then
            c.selected = selected
            paint(c)
        end
        return
    end
    if c.button then
        if c.shownText ~= label then
            c.shownText = label
            setButtonLabel(c.widget, label)
        end
        return
    end
    setText(c.text, label, c)
    if c.selected ~= selected or c.locked ~= locked then
        c.selected, c.locked = selected, locked
        paint(c)
    end
end

-- ---------------------------------------------------------------- helpers

local function progressComponent()
    local ok, progress = pcall(function() return V.localController():GetProgressComponent() end)
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
    local line, line2
    if view.message then
        line, line2 = view.message.text, ''
    else
        local actual, key = V.actual(U.slot)
        key = key or U.slot
        if not actual or (V.HANDS[U.slot] and not view.key) then
            line, line2 = V.HANDS[U.slot] and t('emptyHand') or t('empty'), ''
        else
            local real = textOf(actual.Name)
            real = real ~= '' and real or t('nothing')
            local look = entryName(key, V.sel[key])
            if view.status2 then
                line, line2 = t('equippedLine', real), t('lookLine', look)
            else
                line = t('equipped', real, look)
            end
        end
    end
    setText(view.status, line, view.statusCache)
    if view.status2 then setText(view.status2, line2 or '', view.status2Cache) end
end

-- Muted gold scrollbar, after the game's art (the engine default is white).
local function styleScrollbar(list)
    local thumb = { R = 0.52, G = 0.41, B = 0.22, A = 0.85 }
    local hot = { R = 0.78, G = 0.62, B = 0.32, A = 1 }
    local track = { R = 0, G = 0, B = 0, A = 0.25 }
    local function tint(brush, color)
        pcall(function() list.WidgetBarStyle[brush].TintColor = { SpecifiedColor = color, ColorUseRule = 0 } end)
    end
    tint('NormalThumbImage', thumb)
    tint('HoveredThumbImage', hot)
    tint('DraggedThumbImage', hot)
    tint('VerticalBackgroundImage', track)
    tint('VerticalTopSlotImage', track)
    tint('VerticalBottomSlotImage', track)
end

-- Title: WINDOW - SLOT, for the hovered tab while hovering one.
local function setTitle(view, slot)
    if not view.title then return end
    setText(view.title, (t('wardrobe') .. '  -  ' .. t(slot)):upper(), view.titleCache)
end

-- Icon for a tab or the "Original" cell: the real item in that slot, or a
-- typical item of that slot when it is empty.
local function slotIcon(slot)
    local actual = V.actual(slot)
    local icon = actual and C.iconOf(actual)
    if icon then return icon end
    local fallback = TAB_ICON[slot]
    return fallback and C.iconOf(C.load(C.find(fallback[1], fallback[2]))) or nil
end

function U.refresh(view)
    local key = view.key
    local data = key and view.slots[key]
    local query = textOf(view.search:GetText()):lower()
    local current = key and V.sel[key]
    local shown, total, position = 0, 0, 0
    local columns = view.columns or COLUMNS

    for _, row in ipairs(data and data.rows or {}) do
        local isCurrent, label, visible = false, nil, true
        if row.kind == 'original' then
            isCurrent, label = current == nil, t('original')
            if row.cell.square then setIcon(view, row.cell, slotIcon(U.slot)) end
        elseif row.kind == 'hidden' then
            isCurrent, label = current == V.HIDDEN, t('hide')
        else
            -- Only looks the character knows (recipe learned, or worn/held before).
            local e = row.entry
            isCurrent, label = current == e.id, e.name
            local matches = query == '' or e.name:lower():find(query, 1, true) ~= nil
            if e.unlocked then total = total + 1 end
            visible = e.unlocked and matches
            if visible then shown = shown + 1 end
        end
        setCell(row.cell, label, isCurrent, false)
        if row.visible ~= visible then
            row.visible = visible
            row.cell.sizeBox:SetVisibility(visible and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
        end
        if visible then
            -- Visible cells are packed left-to-right, top-to-bottom.
            local r, col = position // columns, position % columns
            if row.r ~= r or row.col ~= col then
                row.r, row.col = r, col
                row.cell.slot:SetRow(r)
                row.cell.slot:SetColumn(col)
            end
            position = position + 1
        end
    end

    for _, s in ipairs(TABS) do
        local tab = view.tabs[s]
        if tab.square then setIcon(view, tab, slotIcon(s)) end
        setCell(tab, t(s), s == U.slot, false)
    end
    setTitle(view, U.slot)
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
        status(view, t((err == 'noCharacter' or err == 'notKnown') and err or 'failed'))
    end
    U.refresh(view)
end

local function buildSlot(view, slot, hideable)
    local grid = widget('UniformGridPanel', view.tree)
    pcall(function() grid:SetSlotPadding({ Left = CELL_PAD, Top = CELL_PAD, Right = CELL_PAD, Bottom = CELL_PAD }) end)
    local gridSlot = add(view.list, grid)
    align(gridSlot, H_FILL, nil)
    local data = { grid = grid, rows = {} }

    local function row(kind, entry)
        local r = { kind = kind, entry = entry }
        local action = function() choose(view, slot, kind, entry) end
        if view.native then
            local note = (kind == 'original' and t('originalShort')) or (kind == 'hidden' and t('hide')) or nil
            r.cell = nativeCell(view, grid, action, note)
        else
            r.cell = newCell(view, grid, { height = 40, icon = true, action = action })
        end
        if entry then setIcon(view, r.cell, entry.icon) end
        data.rows[#data.rows + 1] = r
    end

    row('original')
    if hideable then row('hidden') end
    for _, entry in ipairs(C.prepare(slot)) do row('item', entry) end
    view.slots[slot] = data
    return data
end

function U.showSlot(view, slot)
    U.slot = slot
    view.message = nil
    local key = V.keyFor(slot)
    view.key = key
    if key and not view.slots[key] then buildSlot(view, key, HIDEABLE[slot] or C.isHeld(key)) end
    for k, other in pairs(view.slots) do
        other.grid:SetVisibility(k == key and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
    end
    if key then C.refreshUnlocked(key, V.seen, progressComponent()) end
    pcall(function() view.list:ScrollToStart() end)
    view.scrollTries = 2 -- U.tick scrolls the current look into view once rows are laid out
    U.refresh(view)
end

local function setMenu(view, open)
    view.menuOpen = open
    if view.native then
        if open then
            local f = io.open(S.file(UI_LOCK), 'w')
            if f then f:write('open\n') f:close() end
        else
            pcall(os.remove, S.file(UI_LOCK))
        end
    end
    view.menu:SetVisibility(open and VISIBLE or COLLAPSED)
    if view.dock then
        -- One window at a time: RSE-Dock closes the others when this one opens.
        if open then Dock.open(DOCK_ID) else Dock.close(DOCK_ID) end
    elseif valid(view.toggle) then
        setButtonLabel(view.toggle, (open and not view.native) and t('back') or t('wardrobe'))
    end
    if open then
        -- Cells built before any inventory slot existed get the slot art now.
        for _, c in ipairs(view.cells) do
            if c.square then slotArt(c) end
        end
        local ok, err = pcall(U.showSlot, view, U.slot)
        if not ok then log('open: ' .. tostring(err)) end
    end
    U.recenter(view, 2)
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

-- Native window: right of the inventory grid panel, top-aligned with it, as
-- wide as it and as tall as the grid and armour panels together.
local WINDOW_GAP = 12
local function placeWindow(panel, armour, window)
    local root = panel.WidgetTree.RootWidget
    local anchors, alignment, o = menuLayout(panel, armour)
    local a = armour.Slot:GetLayout()
    local ax, ay = get(function() return alignment.X end) or 0, get(function() return alignment.Y end) or 0
    local gw, gh = o.Right, o.Bottom
    -- Top-left corner of the grid panel, relative to its anchor.
    local left, top = o.Left - ax * gw, o.Top - ay * gh
    local height = gh
    local sameAnchors = get(function()
        return math.abs(a.Anchors.Minimum.X - anchors.Minimum.X) < 0.001 and math.abs(a.Anchors.Minimum.Y - anchors.Minimum.Y) < 0.001
    end)
    if sameAnchors then
        local aay = get(function() return a.Alignment.Y end) or 0
        local armourBottom = a.Offsets.Top - aay * a.Offsets.Bottom + a.Offsets.Bottom
        height = math.max(gh, armourBottom - top)
    end
    local width = gw
    local slot = root:AddChildToCanvas(window)
    slot:SetAnchors(anchors)
    slot:SetAlignment(alignment)
    slot:SetZOrder(1000)
    local stretched = get(function()
        return math.abs(anchors.Minimum.X - anchors.Maximum.X) > 0.001 or math.abs(anchors.Minimum.Y - anchors.Maximum.Y) > 0.001
    end)
    if stretched then
        -- Offsets are margins with stretched anchors: use the grid's own place.
        log('inventory layout uses stretched anchors; the transmog window opens over the grid')
        slot:SetOffsets(o)
        return
    end
    slot:SetOffsets({
        Left = left + gw + WINDOW_GAP + ax * width,
        Top = top + ay * height,
        Right = width, Bottom = height,
    })
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
    assert(valid(fallbackCanvas), 'no place for the transmog window')
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

-- Two-step reset: the first click asks for confirmation.
local function resetAllAction(view)
    return function()
        if view.confirmUntil and os.clock() < view.confirmUntil then
            view.confirmUntil = nil
            setCell(view.resetAll, t('resetAll'), false, false)
            local ok, err = V.resetAll()
            status(view, ok and t('resetDone') or t(err == 'noCharacter' and 'noCharacter' or 'failed'))
            U.refresh(view)
        else
            view.confirmUntil = os.clock() + 3
            setCell(view.resetAll, view.native and t('confirmShort') or t('confirm'), true, false)
        end
    end
end

local function buildClassic(view, tree)
    -- Frame: 1px gold outline around the dark panel.
    local frame = widget('Border', tree, 'Menu')
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
    for i, slot in ipairs(TABS) do
        local tab = newCell(view, tabs, {
            height = 34, textSize = 13, center = true, weight = 'medium',
            action = function() U.showSlot(view, slot) end,
        })
        size(tab.slot, FILL)
        pad(tab.slot, i == 1 and 0 or 3, 0, 0, 0)
        view.tabs[slot] = tab
    end

    -- Current slot status
    view.status = newText(view, 12, COLOR.dim)
    pad(add(column, view.status), 2, 8, 2, 4)

    -- Search
    local tools = widget('HorizontalBox', tree)
    pad(add(column, tools), 0, 0, 0, 6)
    local search, searchSlot = buildSearch(view, tools)
    size(searchSlot, FILL)
    align(searchSlot, nil, V_CENTER)
    view.search = search

    -- Appearance grid
    local list = widget('ScrollBox', tree)
    pcall(function() list:SetScrollbarThickness({ X = 6, Y = 6 }) end)
    styleScrollbar(list)
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
        action = function() if view.key then choose(view, view.key, 'original') end end,
    })
    resetSlot.sizeBox:SetWidthOverride(150)
    setCell(resetSlot, t('resetSlot'), false, false)
    local resetAll = newCell(view, footer, {
        height = 32, textSize = 12, center = true, action = resetAllAction(view),
    })
    resetAll.sizeBox:SetWidthOverride(190)
    pad(resetAll.slot, 6, 0, 0, 0)
    setCell(resetAll, t('resetAll'), false, false)
    view.resetAll = resetAll

    return frame
end

-- Native look: the inventory panel frame with crafting-style icon slots and
-- tabs. Nothing is attached to the live UI until everything is built.
local function buildNative(view, tree)
    view.columns = NATIVE_COLUMNS
    -- Tagged so a later instance can remove it after a hot reload. It sits in
    -- the inventory frame's overlay, over the grid (see frameHost); the frame's
    -- own textured background is added underneath by the caller.
    -- Layout: slot tabs down the whole left side; everything else to their right.
    local body = widget('HorizontalBox', tree, 'Menu')

    local tabs = widget('VerticalBox', tree)
    local tabsSlot = add(body, tabs)
    align(tabsSlot, nil, 1) -- top
    pad(tabsSlot, CONTENT_PAD, CONTENT_PAD, 0, CONTENT_PAD)
    for i, slot in ipairs(TABS) do
        local tab = nativeTab(view, tabs, function() U.showSlot(view, slot) end)
        pad(tab.slot, 0, i == 1 and 0 or 2 * CELL_PAD, 0, 0)
        view.tabs[slot] = tab
    end

    local right = widget('VerticalBox', tree)
    local rightSlot = add(body, right)
    size(rightSlot, FILL)
    pad(rightSlot, ROW_GAP, CONTENT_PAD, CONTENT_PAD, CONTENT_PAD)

    -- Header: WARDROBE - SLOT + close
    local header = widget('HorizontalBox', tree)
    add(right, header)
    view.title = newText(view, TITLE_SIZE, COLOR.gold, 'medium')
    view.titleCache = {}
    local titleSlot = add(header, view.title)
    size(titleSlot, FILL)
    align(titleSlot, nil, V_CENTER)
    local close = buttonCell(view, header, t('close'), function() setMenu(view, false) end, BUTTON_W, BUTTON_H)
    align(close.slot, nil, V_CENTER)

    local tools = widget('HorizontalBox', tree)
    pad(add(right, tools), 0, ROW_GAP, 0, ROW_GAP)
    local search, searchSlot = buildSearch(view, tools)
    size(searchSlot, FILL)
    align(searchSlot, nil, V_CENTER)
    view.search = search

    local list = widget('ScrollBox', tree)
    pcall(function() list:SetScrollbarThickness({ X = 6, Y = 6 }) end)
    styleScrollbar(list)
    local listSlot = add(right, list)
    size(listSlot, FILL)
    view.list = list

    -- Name of the hovered (or current) look, and the count
    local info = widget('HorizontalBox', tree)
    pad(add(right, info), 2, ROW_GAP, 2, 0)
    view.details = newText(view, 15, COLOR.gold, 'medium')
    view.detailsCache = {}
    local detailsSlot = add(info, view.details)
    size(detailsSlot, FILL)
    align(detailsSlot, nil, V_CENTER)
    view.count = newText(view, 11, COLOR.dim)
    align(add(info, view.count), nil, V_CENTER)

    -- Footer: what is worn and shown (two short lines), then the resets
    -- What is worn and shown, on its own row across the full width
    local statusRow = widget('HorizontalBox', tree)
    pad(add(right, statusRow), 2, ROW_GAP, 2, 0)
    pcall(function() statusRow:SetClipping(1) end)
    view.status = newText(view, 11, COLOR.dim)
    size(add(statusRow, view.status), FILL)

    -- Buttons, right-aligned
    local footer = widget('HorizontalBox', tree)
    pad(add(right, footer), 0, ROW_GAP, 0, 0)
    size(add(footer, widget('Spacer', tree)), FILL)
    local resetSlot = buttonCell(view, footer, t('resetSlot'), function() if view.key then choose(view, view.key, 'original') end end, BUTTON_W, BUTTON_H)
    align(resetSlot.slot, nil, V_CENTER)
    view.resetAll = buttonCell(view, footer, t('resetAll'), resetAllAction(view), BUTTON_W, BUTTON_H, { t('resetAll'), t('confirmShort') })
    pad(view.resetAll.slot, 6, 0, 0, 0)
    align(view.resetAll.slot, nil, V_CENTER)
    return body
end

local function findWidget(w, wanted, depth)
    if not valid(w) or depth > 8 then return nil end
    if get(function() return w:GetFName():ToString() end) == wanted then return w end
    local n = get(function() return w:GetChildrenCount() end) or 0
    for i = 0, n - 1 do
        local found = findWidget(get(function() return w:GetChildAt(i) end), wanted, depth + 1)
        if found then return found end
    end
    return nil
end

-- The inventory grid's own frame (WBP_Panel_Inventory "BackgroundPanel"):
-- the overlay holding its PanelContent slot, where the grid lives. The native
-- wardrobe is placed in that overlay, above the grid and with the same
-- padding, so it fills exactly the grid's space inside the real frame.
local function frameHost(panel)
    local root = panel.WidgetTree.RootWidget
    local frame
    for i = 0, (get(function() return root:GetChildrenCount() end) or 0) - 1 do
        local child = get(function() return root:GetChildAt(i) end)
        if get(function() return child:GetFName():ToString() end) == 'BackgroundPanel' then frame = child break end
    end
    assert(valid(frame), 'inventory frame not found')
    local content = findWidget(get(function() return frame.WidgetTree.RootWidget end), 'PanelContent', 0)
    assert(valid(content), 'inventory frame content slot not found')
    local overlay = get(function() return content:GetParent() end)
    assert(valid(overlay) and overlay:IsA('/Script/UMG.Overlay'), 'inventory frame overlay not found')
    local padding = get(function()
        local p = content.Slot.Padding
        return { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom }
    end)
    -- The frame's textured background (under the grid) and its gold border art.
    local images = {}
    for i = 0, (get(function() return overlay:GetChildrenCount() end) or 0) - 1 do
        local child = get(function() return overlay:GetChildAt(i) end)
        if get(function() return child:IsA('/Script/UMG.Image') end) then
            images[get(function() return child:GetFName():ToString() end) or ''] = child
        end
    end
    return { overlay = overlay, content = content, padding = padding,
        background = images.BackgroundPanel, border = images.MagicBorder }
end

-- An opaque copy of the frame's background (same texture or material and
-- tiling). Falls back to a solid dark fill if the brush cannot be copied.
local function backdrop(tree, source, tag, fallback)
    local image = widget('Image', tree, tag or 'Backdrop')
    local copied = false
    if valid(source) then
        copied = pcall(function() image:SetBrush(source.Brush) end)
            and valid(get(function() return image.Brush.ResourceObject end))
        if not copied then
            local resource = get(function() return source.Brush.ResourceObject end)
            if valid(resource) then
                if get(function() return resource:IsA('/Script/Engine.Texture2D') end) then
                    copied = pcall(function() image:SetBrushFromTexture(resource, false) end)
                elseif get(function() return resource:IsA('/Script/Engine.MaterialInterface') end) then
                    copied = pcall(function() image:SetBrushFromMaterial(resource) end)
                end
            end
        end
    end
    if copied then
        pcall(function() image:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
    elseif fallback then
        pcall(function() image:SetColorAndOpacity(fallback) end)
        log('frame ' .. (tag or 'background') .. ' could not be copied; using a plain one')
    else
        return nil
    end
    return image
end

function U.mount(panel)
    if not valid(panel) then return end
    local key = name(panel)
    local old = U.views[key]
    if old and (valid(old.toggle) or (old.dock and valid(old.menu))) then return end
    local tree = panel.WidgetTree
    local armour = panel.BackgroundPanelArmour
    assert(valid(armour), 'Armour panel unavailable')
    local overlay = armour.WidgetTree.RootWidget:GetChildAt(0)
    assert(valid(overlay) and overlay:IsA('/Script/UMG.Overlay'), 'Armour overlay unavailable')
    pcall(removeStale, overlay)
    pcall(removeStale, get(function() return tree.RootWidget end))
    local view = {
        panel = panel, armour = armour, tree = tree, slots = {}, tabs = {}, cells = {},
        actionKeys = {}, statusCache = {}, countCache = {},
    }
    U.views[key] = view

    local canvas
    if Dock.present() then
        -- RSE-Dock draws the button: an icon in its bar on the armour panel.
        view.dock = true
        local icon = C.iconOf(C.load(C.find('Body', 'ITEM_Armour_T3_Body_Bronze')))
        local iconPath = icon and (icon:GetFullName():match('^%S+%s+(.+)$')) or nil
        Dock.register(DOCK_ID, { order = 10, label = t('wardrobe'), desc = t('dockDesc'), icon = iconPath, window = 'own' })
    else
        -- Without RSE-Dock: the Transmog button. It is parented to the armour
        -- panel so it follows its open/close animation.
        canvas = widget('CanvasPanel', armour.WidgetTree, 'Toggle')
        overlay:AddChildToOverlay(canvas)
        local toggleBox = widget('VerticalBox', tree)
        local toggleSlot = canvas:AddChildToCanvas(toggleBox)
        toggleSlot:SetOffsets({ Left = 389, Top = 14, Right = 200, Bottom = 42 })
        toggleSlot:SetZOrder(20)
        view.toggleBox = toggleBox
        view.toggle = gameButton(view, toggleBox, t('wardrobe'), function() setMenu(view, not view.menuOpen) end, 200, 42)
    end

    local frame
    if U.native then
        view.native = true
        local ok, result = pcall(function()
            -- Its own window beside the inventory: the frame's background and
            -- border art (copied from the inventory's frame), content inside.
            local host = frameHost(panel)
            pcall(removeStale, host.overlay) -- leftovers of the earlier "cover" build
            if get(function() return host.content:GetVisibility() end) == COLLAPSED then
                pcall(function() host.content:SetVisibility(SELF_HIT_TEST_INVISIBLE) end)
            end
            local window = widget('Overlay', tree, 'Window')
            local back = backdrop(tree, host.background, 'Backdrop', { R = 0.035, G = 0.031, B = 0.027, A = 1 })
            align(window:AddChildToOverlay(back), H_FILL, V_FILL)
            local art = backdrop(tree, host.border, 'Border')
            if art then
                art:SetVisibility(HIT_TEST_INVISIBLE)
                align(window:AddChildToOverlay(art), H_FILL, V_FILL)
            end
            local body = buildNative(view, tree)
            local bodySlot = window:AddChildToOverlay(body)
            align(bodySlot, H_FILL, V_FILL)
            if host.padding then
                -- The inventory's own inset times FRAME_INSET, as RSE-Dock's window.
                local p = host.padding
                pcall(function() bodySlot:SetPadding({ Left = p.Left * FRAME_INSET, Top = p.Top * FRAME_INSET,
                    Right = p.Right * FRAME_INSET, Bottom = p.Bottom * FRAME_INSET }) end)
            end
            placeWindow(panel, armour, window)
            return window
        end)
        if ok then
            frame = result
        else
            log('native look unavailable, using the classic look: ' .. tostring(result))
            view.native, view.columns, view.title, view.host = false, nil, nil, nil
            view.cells, view.tabs = {}, {}
        end
    end
    if not frame then
        frame = buildClassic(view, tree)
        placeMenu(panel, armour, canvas, frame)
    end
    view.menu = frame
    frame:SetVisibility(COLLAPSED)
    view.menuOpen = false
    log('mounted on ' .. key .. (view.dock and ' (RSE-Dock icon)' or ''))
end

-- -------------------------------------------------------------------- tick

local function forget(key)
    local view = U.views[key]
    if view.native and view.menuOpen then pcall(os.remove, S.file(UI_LOCK)) end
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
        if not valid(view.panel) or not ((view.dock and valid(view.menu)) or valid(view.toggleBox)) then
            forget(key)
        else
            local open = inventoryOpen(view)
            if open ~= view.inventoryOpen then
                view.inventoryOpen = open
                if valid(view.toggleBox) then view.toggleBox:SetVisibility(open and VISIBLE or COLLAPSED) end
                if not open and view.menuOpen then setMenu(view, false) end
                if open then
                    V.syncPreview(true)
                    U.recenter(view, 2) -- the toggle is drawn again: re-centre after its setup
                end
            end
            if view.dock then
                -- The dock icon (or another dock window opening) drives this window.
                local want = open and Dock.isOpen(DOCK_ID)
                if want ~= view.menuOpen then setMenu(view, want) end
            end
            if open then
                V.syncPreview()
                if (view.recenterTicks or 0) > 0 then
                    view.recenterTicks = view.recenterTicks - 1
                    U.recenter(view)
                end
                if view.menuOpen and V.HANDS[U.slot] and V.keyFor(U.slot) ~= view.key then
                    -- The player switched weapon type while the wardrobe is open.
                    U.showSlot(view, U.slot)
                end
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
                    if (view.scrollTries or 0) > 0 then
                        -- Rows get their positions a frame after the tab is built:
                        -- scroll the current look into view on the next ticks.
                        view.scrollTries = view.scrollTries - 1
                        local data = view.key and view.slots[view.key]
                        for _, row in ipairs(data and data.rows or {}) do
                            if row.kind == 'item' and row.visible and row.cell.selected then
                                pcall(function() view.list:ScrollWidgetIntoView(row.cell.sizeBox, false, 2, 0) end) -- centre
                                break
                            end
                        end
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
            local hoveredLabel, currentLabel
            for _, c in ipairs(view.cells) do
                local ok, hovered = pcall(function() return c.hit:IsValid() and c.hit:IsHovered() end)
                hovered = ok and hovered == true
                if c.hovered ~= hovered then
                    c.hovered = hovered
                    paint(c)
                end
            end
            -- Details: only the grid on screen (other tabs' grids are collapsed).
            local data = view.native and view.key and view.slots[view.key]
            for _, row in ipairs(data and data.rows or {}) do
                local c = row.cell
                if row.visible ~= false and c.label then
                    if c.hovered then hoveredLabel = c.label end
                    if c.selected then currentLabel = c.label end
                end
            end
            if view.details then
                -- Native slots are icons only: name the hovered look, else the current one.
                setText(view.details, hoveredLabel or currentLabel or '', view.detailsCache)
            end
            if view.title then
                -- Icon tabs: name the hovered tab in the title, else the open one.
                local hoveredTab
                for slot, tab in pairs(view.tabs) do
                    if tab.hovered then hoveredTab = slot end
                end
                setTitle(view, hoveredTab or U.slot)
            end
        end
    end
end

-- Native look unless configured otherwise, or unless the game closed while
-- it was open last time (then classic for this session, and say so).
local function nativeAllowed()
    if Cfg.UIStyle == 'classic' then return false end
    local f = io.open(S.file(UI_LOCK), 'r')
    if f then
        f:close()
        pcall(os.remove, S.file(UI_LOCK))
        log('the game closed while the transmog window was open last time; using the classic look for this session. '
            .. 'Set UIStyle = "classic" in config.lua to keep it.')
        return false
    end
    return true
end

function U.start()
    U.native = nativeAllowed()
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
    -- Panels that already exist (UE4SS hot reload): the main chunk does not
    -- run on the game thread, and widgets must only be created there.
    ExecuteInGameThread(function()
        for _, panel in ipairs(FindAllOf('InventoryMainPanel') or {}) do
            local ok, err = pcall(U.mount, panel)
            if not ok then log('mount: ' .. tostring(err)) end
        end
    end)
end

return U
