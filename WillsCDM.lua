local addonName, _ = ...

local DEFAULT_COOLDOWN_SWIPE_COLOR = {0, 0, 0, 0.7}
local DEFAULT_AURA_SWIPE_COLOR = {1, 0.95, 0.57, 0.7}

local dbDefaults = {
    defaultCooldownSwipeColor = {unpack(DEFAULT_COOLDOWN_SWIPE_COLOR)},
    defaultAuraSwipeColor = {unpack(DEFAULT_AURA_SWIPE_COLOR)},
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

local function InitializeDB()
    WillsDB = WillsDB or {}
    local db = WillsDB

    -- Remove unknown keys. Might contain fields that we've removed or renamed in later versions.
    for k, v in pairs(db) do
        if dbDefaults[k] == nil then
            db[k] = nil
        end
    end

    ApplyDefaultsToTable(db, dbDefaults)
end

local function GetDB()
    return WillsDB
end

local function GetSpellSettings(spellID)
    local db = GetDB()
    return db.spellSettings[spellID]
end

local function EnsureSpellSettings(spellID)
    local db = GetDB()
    if db.spellSettings[spellID] == nil then
        db.spellSettings[spellID] = {}
    end
    return db.spellSettings[spellID]
end

local function CleanupSpellSettings(spellID)
    local db = GetDB()
    local settings = db.spellSettings[spellID]
    if settings == nil then
        return
    end

    if settings.showAura == nil and settings.cooldownSwipeColor == nil and settings.auraSwipeColor == nil then
        db.spellSettings[spellID] = nil
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

local function GetCooldownSwipeColor(spellID)
    local db = GetDB()
    local settings = GetSpellSettings(spellID)
    return (settings and settings.cooldownSwipeColor) or db.defaultCooldownSwipeColor
end

local function GetAuraSwipeColor(spellID)
    local db = GetDB()
    local settings = GetSpellSettings(spellID)
    return (settings and settings.auraSwipeColor) or db.defaultAuraSwipeColor
end

local function GetShowAura(spellID)
    local db = GetDB()
    local settings = GetSpellSettings(spellID)
    if settings and settings.showAura ~= nil then
        return settings.showAura
    end
    return db.defaultShowAuras
end

local function SetShowAura(spellID, value)
    local db = GetDB()
    if value == db.defaultShowAuras then
        local settings = GetSpellSettings(spellID)
        if settings ~= nil then
            settings.showAura = nil
            CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = EnsureSpellSettings(spellID)
    settings.showAura = value
end

local function ToggleShowAura(spellID)
    local current = GetShowAura(spellID)
    SetShowAura(spellID, not current)
end

local function SetShowAuraAll(value)
    local db = GetDB()
    db.defaultShowAuras = value

    local keys = {}
    for spellID in pairs(db.spellSettings) do
        table.insert(keys, spellID)
    end
    for _, spellID in ipairs(keys) do
        db.spellSettings[spellID].showAura = nil
        CleanupSpellSettings(spellID)
    end
end

local function SetCooldownSwipeColor(spellID, colorTable)
    local db = GetDB()
    if ColorsEqual(colorTable, db.defaultCooldownSwipeColor) then
        local settings = GetSpellSettings(spellID)
        if settings ~= nil then
            settings.cooldownSwipeColor = nil
            CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = EnsureSpellSettings(spellID)
    local r, g, b, a = unpack(colorTable)
    settings.cooldownSwipeColor = {r, g, b, a}
end

local function SetAuraSwipeColor(spellID, colorTable)
    local db = GetDB()
    if ColorsEqual(colorTable, db.defaultAuraSwipeColor) then
        local settings = GetSpellSettings(spellID)
        if settings ~= nil then
            settings.auraSwipeColor = nil
            CleanupSpellSettings(spellID)
        end
        return
    end

    local settings = EnsureSpellSettings(spellID)
    local r, g, b, a = unpack(colorTable)
    settings.auraSwipeColor = {r, g, b, a}
end

local function GetCooldownFrames()
    local frames = {}

    local essentialViewer = _G["EssentialCooldownViewer"]
    if essentialViewer then
        for _, child in ipairs({essentialViewer:GetChildren()}) do
            if child.Cooldown then
                table.insert(frames, child)
            end
        end
    end

    local utilityViewer = _G["UtilityCooldownViewer"]
    if utilityViewer then
        for _, child in ipairs({utilityViewer:GetChildren()}) do
            if child.Cooldown then
                table.insert(frames, child)
            end
        end
    end

    return frames
end

local desaturationCurve = C_CurveUtil.CreateCurve()
desaturationCurve:AddPoint(0, 0)
desaturationCurve:AddPoint(0.001, 1)

local function ApplyCooldownSettings(cdmFrame)
    local cooldownInfo = cdmFrame:GetCooldownInfo()
    if cooldownInfo == nil then
        return
    end

    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    if not spellID then
        return
    end

    local showAura = GetShowAura(spellID)
    if showAura and cdmFrame.wasSetFromAura then
        cdmFrame.Cooldown:SetSwipeColor(unpack(GetAuraSwipeColor(spellID)))
    else
        cdmFrame.Cooldown:SetSwipeColor(unpack(GetCooldownSwipeColor(spellID)))
    end

    cdmFrame.Cooldown:SetDrawEdge(true)
    if showAura then
        return
    end

    local cooldownDuration = C_Spell.GetSpellCooldownDuration(spellID)
    cdmFrame.Cooldown:SetCooldownFromDurationObject(cooldownDuration)
    if C_Spell.GetSpellCharges(spellID) then
        cdmFrame.Cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(spellID))
    end

    local cooldown = C_Spell.GetSpellCooldown(spellID)
    if cooldown and cooldown.isOnGCD then
        cdmFrame.WillsCDM_Desaturation = 0
    else
        cdmFrame.WillsCDM_Desaturation = cooldownDuration:EvaluateRemainingPercent(desaturationCurve)
    end

    cdmFrame.Cooldown:SetReverse(false)
end

local function ApplyIconSettings(cdmFrame)
    local cooldownInfo = cdmFrame:GetCooldownInfo()
    if cooldownInfo == nil then
        return
    end

    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    if not spellID then
        return
    end

    if GetShowAura(spellID) then
        cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownShowSwipe == true)
        return
    end

    if cdmFrame.wasSetFromAura then
        cdmFrame.Icon:SetDesaturation(cdmFrame.WillsCDM_Desaturation)
    end

    if cdmFrame.wasSetFromAura and cdmFrame:GetAuraDataUnit() ~= "target" then
        if issecretvalue(cdmFrame.cooldownChargesCount) or issecretvalue(cdmFrame.cooldownChargesShown) then
            if issecretvalue(cdmFrame.Icon:IsDesaturated()) then
                cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.CooldownFlash:IsShown())
            else
                cdmFrame.Cooldown:SetDrawSwipe(false)
            end
        else
            cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownChargesCount == 0 and cdmFrame.cooldownChargesShown == true)
        end
    end
end

local function HookFrame(cdmFrame)
    if cdmFrame.WillsCDM_Hooked or cdmFrame.Cooldown == nil or cdmFrame.Icon == nil then
        return
    end

    hooksecurefunc(cdmFrame.Cooldown, "SetCooldown", function(self)
        ApplyCooldownSettings(self:GetParent())
    end)

    hooksecurefunc(cdmFrame.Icon, "SetDesaturated", function(self)
        ApplyIconSettings(self:GetParent())
    end)

    cdmFrame.WillsCDM_Hooked = true
end

local function HookCooldownFrames()
    local cooldownFrames = GetCooldownFrames()

    for _, cdmFrame in ipairs(cooldownFrames) do
        if not cdmFrame.WillsCDM_Hooked then
            if cdmFrame.Cooldown ~= nil then
                HookFrame(cdmFrame)
            end
        end
    end
end

local function RefreshCooldownManagerFrames()
    if InCombatLockdown() then
        return
    end

    HookCooldownFrames()

    for _, cdmFrame in ipairs(GetCooldownFrames()) do
        if cdmFrame.Cooldown and cdmFrame.Icon then
            ApplyCooldownSettings(cdmFrame)
            ApplyIconSettings(cdmFrame)
        end
    end
end

local function SortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end

    local function IsSpellInPlayerSpellbook(spellID)
        return C_SpellBook.IsSpellKnown(spellID)
    end

    local function SpellSortKey(spellID)
        local name = (C_Spell and C_Spell.GetSpellName) and C_Spell.GetSpellName(spellID) or nil
        if not name or name == "" then
            name = tostring(spellID)
        end
        return name:lower()
    end

    table.sort(keys, function(a, b)
        local aKnown = IsSpellInPlayerSpellbook(a)
        local bKnown = IsSpellInPlayerSpellbook(b)
        if aKnown ~= bKnown then
            return aKnown
        end

        local aName = SpellSortKey(a)
        local bName = SpellSortKey(b)
        if aName ~= bName then
            return aName < bName
        end

        return a < b
    end)
    return keys
end

local function GetColorSwatchDisplayInfo(colorTable)
    return {
        r = colorTable[1] or 0,
        g = colorTable[2] or 0,
        b = colorTable[3] or 0,
        opacity = colorTable[4] or 1,
        hasOpacity = 1
    }
end

local function BuildColorPickerInfo(colorTable, onChanged)
    local function NotifyChanged()
        if onChanged then
            onChanged()
        end
    end

    local colorInfo = GetColorSwatchDisplayInfo(colorTable)

    colorInfo.swatchFunc = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        colorTable[1] = r
        colorTable[2] = g
        colorTable[3] = b
        NotifyChanged()
    end

    colorInfo.opacityFunc = function()
        local a = ColorPickerFrame:GetColorAlpha()
        colorTable[4] = a
        NotifyChanged()
    end

    colorInfo.cancelFunc = function(previous)
        if previous and previous.r ~= nil then
            colorTable[1] = previous.r
        end
        if previous and previous.g ~= nil then
            colorTable[2] = previous.g
        end
        if previous and previous.b ~= nil then
            colorTable[3] = previous.b
        end

        local a = previous and (previous.a ~= nil and previous.a or previous.opacity)
        if a ~= nil then
            colorTable[4] = a
        end

        NotifyChanged()
    end

    return colorInfo
end

local function AddColorSwatch(rootDescription, label, getColorTable, setColorTable, onChanged)
    local function Commit(colorTable)
        if setColorTable then
            setColorTable(colorTable)
        end
        if onChanged then
            onChanged()
        end
    end

    rootDescription:CreateColorSwatch(label, function()
        local current = getColorTable and getColorTable() or {0, 0, 0, 1}
        local colorCopy = {unpack(current)}
        ColorPickerFrame:SetupColorPickerAndShow(BuildColorPickerInfo(colorCopy, function()
            Commit(colorCopy)
        end))
    end, GetColorSwatchDisplayInfo(getColorTable and getColorTable() or {0, 0, 0, 1}))
end

local function CopyColorInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end

    dst[1] = src[1]
    dst[2] = src[2]
    dst[3] = src[3]
    dst[4] = src[4]
end

local function Run()
    InitializeDB()

    HookCooldownFrames()

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        HookCooldownFrames()
    end)

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
        HookCooldownFrames()
    end)

    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription, contextData)
        local spellID = owner:GetBaseSpellID()
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Will's CDM")

        AddColorSwatch(rootDescription, "Cooldown Swipe Color", function()
            return GetCooldownSwipeColor(spellID)
        end, function(color)
            SetCooldownSwipeColor(spellID, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateCheckbox("Show Aura", function(...)
            return GetShowAura(spellID)
        end, function()
            ToggleShowAura(spellID)
            RefreshCooldownManagerFrames()
        end)

        AddColorSwatch(rootDescription, "Aura Swipe Color", function()
            return GetAuraSwipeColor(spellID)
        end, function(color)
            SetAuraSwipeColor(spellID, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateButton("Reset to Defaults", function()
            local db = GetDB()
            db.spellSettings[spellID] = nil
            RefreshCooldownManagerFrames()
        end)
    end)

    Menu.ModifyMenu("COOLDOWN_VIEWER_SETTINGS_MENU", function(owner, rootDescription, contextData)
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Will's CDM")
        rootDescription:CreateCheckbox("Default Show Auras", function()
            local db = GetDB()
            return db.defaultShowAuras
        end, function()
            local db = GetDB()
            db.defaultShowAuras = not db.defaultShowAuras
        end)
        rootDescription:CreateButton("Apply Default Show Auras", function()
            StaticPopupDialogs["WILLS_CDM_APPLY_DEFAULT_SHOW_AURAS"] = {
                text = "Are you sure you want to apply the default show auras setting to all spells?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local db = GetDB()
                    local keys = {}
                    for spellID in pairs(db.spellSettings) do
                        table.insert(keys, spellID)
                    end
                    for _, spellID in ipairs(keys) do
                        db.spellSettings[spellID].showAura = nil
                        CleanupSpellSettings(spellID)
                    end
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULT_SHOW_AURAS")
        end)
        rootDescription:CreateDivider()

        local db = GetDB()
        AddColorSwatch(rootDescription, "Default Cooldown Swipe Color", function()
            return db.defaultCooldownSwipeColor
        end, function(color)
            CopyColorInto(db.defaultCooldownSwipeColor, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateButton("Reset Default Cooldown Swipe Color", function()
            local db = GetDB()
            db.defaultCooldownSwipeColor = {unpack(DEFAULT_COOLDOWN_SWIPE_COLOR)}
            RefreshCooldownManagerFrames()
        end)

        rootDescription:CreateButton("Apply Default Cooldown Swipe Color", function()
            StaticPopupDialogs["WILLS_CDM_APPLY_DEFAULT_COOLDOWN_SWIPE_COLOR"] = {
                text = "Are you sure you want to apply the default cooldown swipe color to all spells?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local db = GetDB()
                    local keys = {}
                    for spellID in pairs(db.spellSettings) do
                        table.insert(keys, spellID)
                    end
                    for _, spellID in ipairs(keys) do
                        db.spellSettings[spellID].cooldownSwipeColor = nil
                        CleanupSpellSettings(spellID)
                    end
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULT_COOLDOWN_SWIPE_COLOR")
        end)

        rootDescription:CreateDivider()

        AddColorSwatch(rootDescription, "Default Aura Swipe Color", function()
            return db.defaultAuraSwipeColor
        end, function(color)
            CopyColorInto(db.defaultAuraSwipeColor, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateButton("Reset Default Aura Swipe Color", function()
            local db = GetDB()
            db.defaultAuraSwipeColor = {unpack(DEFAULT_AURA_SWIPE_COLOR)}
            RefreshCooldownManagerFrames()
        end)

        rootDescription:CreateButton("Apply Default Aura Swipe Color", function()
            StaticPopupDialogs["WILLS_CDM_APPLY_DEFAULT_AURA_SWIPE_COLOR"] = {
                text = "Are you sure you want to apply the default aura swipe color to all spells?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local db = GetDB()
                    local keys = {}
                    for spellID in pairs(db.spellSettings) do
                        table.insert(keys, spellID)
                    end
                    for _, spellID in ipairs(keys) do
                        db.spellSettings[spellID].auraSwipeColor = nil
                        CleanupSpellSettings(spellID)
                    end
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULT_AURA_SWIPE_COLOR")
        end)
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, eventAddonName)
    if event == "ADDON_LOADED" and eventAddonName == addonName then
        Run()

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_CDM1 = "/cdm"
SlashCmdList["CDM"] = function()
    ShowUIPanel(CooldownViewerSettings)
end

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

local function PrintIsShowAura(spellID)
    local spellName = C_Spell.GetSpellName(spellID) or "Unknown Spell"

    if GetShowAura(spellID) then
        print(spellName .. " (ID: " .. spellID .. ") has aura enabled.")
    else
        print(spellName .. " (ID: " .. spellID .. ") has aura disabled (cooldown forced).")
    end
end

local function PrintHelp()
    print("/cdm - Open Advanced Cooldown Settings panel (might not work if another addon overrides it)")
    print("/wcdm - Open Advanced Cooldown Settings panel")
    print("/wcdm settings - Open Advanced Cooldown Settings panel")
    print("/wcdm force {<spellID>,all} - Disable aura (force cooldown) for <spellID> or all spell IDs")
    print("/wcdm clear {<spellID>,all} - Enable aura for <spellID> or all spell IDs")
    print("/wcdm reset {<spellID>,all} - Reset settings for <spellID> or all spell IDs")
    print("/wcdm <spellID> - Show settings for spell ID")
    print("/wcdm help - Print this help message")
    print()
    print("Note: Right click spells in the Advanced Cooldown Settings panel to change its settings.")
end

SLASH_WCDM1 = "/wcdm"
SlashCmdList["WCDM"] = function(msg, editBox)
    if msg == "" or msg == "settings" then
        print("Use /wcdm help for command usage.")
        ShowUIPanel(CooldownViewerSettings)
    elseif starts_with(msg, "force") then
        local arg = msg:match("force%s+(.+)")
        if arg == "all" then
            SetShowAuraAll(false)
            RefreshCooldownManagerFrames()
            return
        end

        local spellID = tonumber(arg)
        if spellID then
            SetShowAura(spellID, false)
            RefreshCooldownManagerFrames()
            return
        end

        print("Usage: /wcdm force {<spellID>,all}")
    elseif starts_with(msg, "clear") then
        local arg = msg:match("clear%s+(.+)")
        if arg == "all" then
            SetShowAuraAll(true)
            RefreshCooldownManagerFrames()
            return
        end

        local spellID = tonumber(arg)
        if spellID then
            SetShowAura(spellID, true)
            RefreshCooldownManagerFrames()
            return
        end

        print("Usage: /wcdm clear {<spellID>,all}")
    elseif starts_with(msg, "reset") then
        local arg = msg:match("reset%s+(.+)")
        if arg == "all" then
            print("Are you sure you want to reset all settings? Use `/wcdm reset all settings` to confirm.")
            print("Note: This will also reset default settings.")
            return
        end

        if arg == "all settings" then
            WillsDB = nil
            InitializeDB()
            RefreshCooldownManagerFrames()
            print("All settings have been reset to defaults.")
            return
        end

        local spellID = tonumber(arg)
        if spellID then
            local db = GetDB()
            db.spellSettings[spellID] = nil
            RefreshCooldownManagerFrames()
            print("Settings for spell ID " .. spellID .. " have been reset to defaults.")
            return
        end

        print("Usage: /wcdm reset <spellID>")
    elseif msg == "help" or msg == "--help" then
        PrintHelp()
    else
        local arg = msg:match("%S+")

        local spellID = tonumber(arg)
        if spellID then
            PrintIsShowAura(spellID)
            return
        end

        print("Unknown command: " .. msg)
        PrintHelp()
    end
end
