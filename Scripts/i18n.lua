local Cfg = require('config')
local I = {}

local strings = {
    en = {
        wardrobe = 'Transmog', back = '« Inventory', close = 'Close',
        Head = 'Head', Body = 'Body', Legs = 'Legs', Cape = 'Cape', MainHand = 'Weapon', OffHand = 'Off-hand',
        search = 'Search appearances...',
        count = '%d / %d appearances',
        original = 'Original look', originalShort = 'Original', hide = 'Hide',
        resetSlot = 'Reset slot', resetAll = 'Reset all', confirm = 'Click again to confirm', confirmShort = 'Confirm?',
        equipped = 'Equipped: %s   |   Look: %s',
        equippedLine = 'Equipped: %s', lookLine = 'Look: %s',
        nothing = 'nothing', hidden = 'hidden',
        empty = 'Nothing equipped here. Your choice applies when you equip an item.',
        emptyHand = 'Hold a weapon or shield in this hand to pick a look for its type.',
        applied = '%s applied',
        resetDone = 'All slots show your real equipment again',
        failed = 'Could not apply this appearance',
        noCharacter = 'Your character is not ready yet',
        notKnown = 'You have not unlocked this look yet',
    },
    tr = {
        wardrobe = 'Transmog', back = '« Envanter', close = 'Kapat',
        Head = 'Baş', Body = 'Gövde', Legs = 'Bacak', Cape = 'Pelerin', MainHand = 'Silah', OffHand = 'Yan el',
        search = 'Görünüm ara...',
        count = '%d / %d görünüm',
        original = 'Orijinal görünüm', originalShort = 'Orijinal', hide = 'Gizle',
        resetSlot = 'Yuvayı sıfırla', resetAll = 'Tümünü sıfırla', confirm = 'Onay için tekrar tıkla', confirmShort = 'Onayla?',
        equipped = 'Giyili: %s   |   Görünüm: %s',
        equippedLine = 'Giyili: %s', lookLine = 'Görünüm: %s',
        nothing = 'yok', hidden = 'gizli',
        empty = 'Bu yuvada eşya yok. Seçimin bir eşya giydiğinde uygulanır.',
        emptyHand = 'Türüne görünüm seçmek için bu elde bir silah veya kalkan tut.',
        applied = '%s uygulandı',
        resetDone = 'Tüm yuvalar yeniden gerçek ekipmanını gösteriyor',
        failed = 'Bu görünüm uygulanamadı',
        noCharacter = 'Karakterin henüz hazır değil',
        notKnown = 'Bu görünümün kilidini henüz açmadın',
    },
}

local active

local function detect()
    if Cfg.Language and strings[Cfg.Language] then return Cfg.Language end
    local ok, code = pcall(function()
        local lib = StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary')
        return lib:GetCurrentLanguage():ToString()
    end)
    if ok and type(code) == 'string' then
        local short = code:sub(1, 2):lower()
        if strings[short] then return short end
    end
    return 'en'
end

function I.t(key, ...)
    active = active or detect()
    local s = strings[active][key] or strings.en[key] or key
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
end

return I
