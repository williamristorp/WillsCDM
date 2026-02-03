local addonName, addon = ...
addon = addon or {}

addon.DB = addon.DB or {}
local DB = addon.DB

DB.DEFAULT_COOLDOWN_SWIPE_COLOR = {0, 0, 0, 0.7}
DB.DEFAULT_AURA_SWIPE_COLOR = {1, 0.95, 0.57, 0.7}

local dbDefaults = {
    defaultAlwaysShowCooldownEdge = false,
    defaultCooldownSwipeColor = {unpack(DB.DEFAULT_COOLDOWN_SWIPE_COLOR)},
    defaultAuraSwipeColor = {unpack(DB.DEFAULT_AURA_SWIPE_COLOR)},
    defaultShowAuras = true,
    spellSettings = {}
}

local function ApplyDefaultsToTable(tbl, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(tbl[k]) ~= "table" then
                tbl[k] = {}
            end
            ApplyDefaultsToTable(tbl[k], v)
        elseif tbl[k] == nil then
            tbl[k] = v
        end
    end
end

function DB.GetDB()
    return WillsDB
end

function DB.GetSpellSettings(spellID)
    local db = DB.GetDB()
    return db.spellSettings[spellID]
end

function DB.EnsureSpellSettings(spellID)
    local db = DB.GetDB()
    if db.spellSettings[spellID] == nil then
        db.spellSettings[spellID] = {}
    end
    return db.spellSettings[spellID]
end

function DB.CleanupSpellSettings(spellID)
    local db = DB.GetDB()
    local settings = db.spellSettings[spellID]
    if settings == nil then
        return
    end

    if settings.showAura ~= nil then
        -- Legacy support for old setting name
        settings.showAuras = settings.showAura
        settings.showAura = nil
    end

    if settings.showAuras == nil and settings.cooldownSwipeColor == nil and settings.auraSwipeColor == nil and
        settings.alwaysShowCooldownEdge == nil then
        db.spellSettings[spellID] = nil
    end
end

function DB.CleanupAllSpellSettings()
    local db = DB.GetDB()
    if not db or type(db.spellSettings) ~= "table" then
        return
    end

    local keys = {}
    for spellID in pairs(db.spellSettings) do
        table.insert(keys, spellID)
    end

    for _, spellID in ipairs(keys) do
        DB.CleanupSpellSettings(spellID)
    end
end

local function ColorsEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    local eps = 0.0001
    for i = 1, 4 do
        local av = a[i]
        local bv = b[i]
        if av == nil and bv == nil then
            -- ok
        else
            if av == nil then
                av = (i == 4) and 1 or 0
            end
            if bv == nil then
                bv = (i == 4) and 1 or 0
            end
            if math.abs(av - bv) > eps then
                return false
            end
        end
    end
    return true
end

function DB.GetAlwaysShowCooldownEdge(spellID)
    local db = DB.GetDB()
    local settings = DB.GetSpellSettings(spellID)
    if settings and settings.alwaysShowCooldownEdge ~= nil then
        return settings.alwaysShowCooldownEdge
    end
    return db.defaultAlwaysShowCooldownEdge
end

function DB.GetCooldownSwipeColor(spellID)
    local db = DB.GetDB()
    local settings = DB.GetSpellSettings(spellID)
    return (settings and settings.cooldownSwipeColor) or db.defaultCooldownSwipeColor
end

function DB.GetAuraSwipeColor(spellID)
    local db = DB.GetDB()
    local settings = DB.GetSpellSettings(spellID)
    return (settings and settings.auraSwipeColor) or db.defaultAuraSwipeColor
end

function DB.GetShowAuras(spellID)
    local db = DB.GetDB()
    local settings = DB.GetSpellSettings(spellID)
    if settings and settings.showAuras ~= nil then
        return settings.showAuras
    end
    return db.defaultShowAuras
end

function DB.SetAlwaysShowCooldownEdge(spellID, value)
    local db = DB.GetDB()
    if value == db.defaultAlwaysShowCooldownEdge then
        local settings = DB.GetSpellSettings(spellID)
        if settings ~= nil then
            settings.alwaysShowCooldownEdge = nil
            DB.CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = DB.EnsureSpellSettings(spellID)
    settings.alwaysShowCooldownEdge = value
end

function DB.ToggleAlwaysShowCooldownEdge(spellID)
    local current = DB.GetAlwaysShowCooldownEdge(spellID)
    DB.SetAlwaysShowCooldownEdge(spellID, not current)
end

function DB.SetShowAuras(spellID, value)
    local db = DB.GetDB()
    if value == db.defaultShowAuras then
        local settings = DB.GetSpellSettings(spellID)
        if settings ~= nil then
            settings.showAuras = nil
            DB.CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = DB.EnsureSpellSettings(spellID)
    settings.showAuras = value
end

function DB.ToggleShowAuras(spellID)
    local current = DB.GetShowAuras(spellID)
    DB.SetShowAuras(spellID, not current)
end

function DB.SetShowAurasAll(value)
    local db = DB.GetDB()
    db.defaultShowAuras = value

    local keys = {}
    for spellID in pairs(db.spellSettings) do
        table.insert(keys, spellID)
    end
    for _, spellID in ipairs(keys) do
        db.spellSettings[spellID].showAuras = nil
        DB.CleanupSpellSettings(spellID)
    end
end

function DB.SetCooldownSwipeColor(spellID, colorTable)
    local db = DB.GetDB()
    if ColorsEqual(colorTable, db.defaultCooldownSwipeColor) then
        local settings = DB.GetSpellSettings(spellID)
        if settings ~= nil then
            settings.cooldownSwipeColor = nil
            DB.CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = DB.EnsureSpellSettings(spellID)
    local r, g, b, a = unpack(colorTable)
    settings.cooldownSwipeColor = {r, g, b, a}
end

function DB.SetAuraSwipeColor(spellID, colorTable)
    local db = DB.GetDB()
    if ColorsEqual(colorTable, db.defaultAuraSwipeColor) then
        local settings = DB.GetSpellSettings(spellID)
        if settings ~= nil then
            settings.auraSwipeColor = nil
            DB.CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = DB.EnsureSpellSettings(spellID)
    local r, g, b, a = unpack(colorTable)
    settings.auraSwipeColor = {r, g, b, a}
end

function DB.InitializeDB()
    WillsDB = WillsDB or {}
    local db = WillsDB

    -- Remove unknown keys. Might contain fields that we've removed or renamed in later versions.
    for k, v in pairs(db) do
        if dbDefaults[k] == nil then
            db[k] = nil
        end
    end

    DB.CleanupAllSpellSettings()
    ApplyDefaultsToTable(db, dbDefaults)
end
