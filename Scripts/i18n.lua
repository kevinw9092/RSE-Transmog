local Cfg = require('config')
local I = {}

local strings = {
    en = {
        wardrobe = 'Wardrobe', back = '« Inventory', close = 'Close',
        Head = 'Head', Body = 'Body', Legs = 'Legs', Cape = 'Cape',
        search = 'Search appearances...',
        lockedShown = 'Locked: shown', lockedHidden = 'Locked: hidden',
        count = '%d / %d appearances',
        original = 'Original look', hide = 'Hide',
        resetSlot = 'Reset slot', resetAll = 'Reset all', confirm = 'Click again to confirm',
        equipped = 'Equipped: %s   |   Look: %s',
        nothing = 'nothing', hidden = 'hidden',
        empty = 'Nothing equipped here. Your choice applies when you equip an item.',
        applied = '%s applied',
        resetDone = 'All slots show your real equipment again',
        failed = 'Could not apply this appearance',
        noCharacter = 'Your character is not ready yet',
    },
    tr = {
        wardrobe = 'Gardırop', back = '« Envanter', close = 'Kapat',
        Head = 'Baş', Body = 'Gövde', Legs = 'Bacak', Cape = 'Pelerin',
        search = 'Görünüm ara...',
        lockedShown = 'Kilitli: gösteriliyor', lockedHidden = 'Kilitli: gizli',
        count = '%d / %d görünüm',
        original = 'Orijinal görünüm', hide = 'Gizle',
        resetSlot = 'Yuvayı sıfırla', resetAll = 'Tümünü sıfırla', confirm = 'Onay için tekrar tıkla',
        equipped = 'Giyili: %s   |   Görünüm: %s',
        nothing = 'yok', hidden = 'gizli',
        empty = 'Bu yuvada eşya yok. Seçimin bir eşya giydiğinde uygulanır.',
        applied = '%s uygulandı',
        resetDone = 'Tüm yuvalar yeniden gerçek ekipmanını gösteriyor',
        failed = 'Bu görünüm uygulanamadı',
        noCharacter = 'Karakterin henüz hazır değil',
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
