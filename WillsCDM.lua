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

    ApplyDefaultsToTable(db, dbDefaults)
end

local function GetDB()
    return WillsDB
end

local function CreateSpellSettings(spellID)
    local db = GetDB()
    local defaultCooldownSwipeColor = db.defaultCooldownSwipeColor
    local defaultAuraSwipeColor = db.defaultAuraSwipeColor

    db.spellSettings[spellID] = {
        showAura = db.defaultShowAuras,
        cooldownSwipeColor = {unpack(defaultCooldownSwipeColor)},
        auraSwipeColor = {unpack(defaultAuraSwipeColor)}
    }
end

local function EnsureSpellSettings(spellID)
    local db = GetDB()

    if db.spellSettings[spellID] == nil then
        CreateSpellSettings(spellID)
    end

    return db.spellSettings[spellID]
end

local function GetCooldownSwipeColor(spellID)
    local settings = EnsureSpellSettings(spellID)
    return settings.cooldownSwipeColor
end

local function GetAuraSwipeColor(spellID)
    local settings = EnsureSpellSettings(spellID)
    return settings.auraSwipeColor
end

local function GetShowAura(spellID)
    local settings = EnsureSpellSettings(spellID)
    return settings.showAura
end

local function SetShowAura(spellID, value)
    local settings = EnsureSpellSettings(spellID)
    settings.showAura = value
end

local function ToggleShowAura(spellID)
    local current = GetShowAura(spellID)
    SetShowAura(spellID, not current)
end

local function SetShowAuraAll(value)
    local db = GetDB()
    for spellID, _ in pairs(db.spellSettings) do
        db.spellSettings[spellID].showAura = value
    end
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

    local spellID = cooldownInfo.spellID
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

    local spellID = cooldownInfo.spellID
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

local function AddColorSwatch(rootDescription, label, colorTable, onChanged)
    rootDescription:CreateColorSwatch(label, function()
        ColorPickerFrame:SetupColorPickerAndShow(BuildColorPickerInfo(colorTable, onChanged))
    end, GetColorSwatchDisplayInfo(colorTable))
end

local function Run()
    HookCooldownFrames()

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        HookCooldownFrames()
    end)

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
        HookCooldownFrames()
    end)

    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription, contextData)
        local spellID = owner:GetBaseSpellID()
        local settings = EnsureSpellSettings(spellID)

        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Will's CDM")

        AddColorSwatch(rootDescription, "Cooldown Swipe Color", settings.cooldownSwipeColor,
            RefreshCooldownManagerFrames)

        rootDescription:CreateCheckbox("Show Aura", function(...)
            return GetShowAura(spellID)
        end, function()
            ToggleShowAura(spellID)
            RefreshCooldownManagerFrames()
        end)

        AddColorSwatch(rootDescription, "Aura Swipe Color", settings.auraSwipeColor, RefreshCooldownManagerFrames)

        rootDescription:CreateButton("Reset to Defaults", function()
            CreateSpellSettings(spellID)
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
                    SetShowAuraAll(db.defaultShowAuras)
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULT_SHOW_AURAS")
        end)
        rootDescription:CreateDivider()

        local db = GetDB()
        AddColorSwatch(rootDescription, "Default Cooldown Swipe Color", db.defaultCooldownSwipeColor,
            RefreshCooldownManagerFrames)

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
                    local r, g, b, a = unpack(db.defaultCooldownSwipeColor)
                    for spellID, _ in pairs(db.spellSettings) do
                        db.spellSettings[spellID].cooldownSwipeColor = {r, g, b, a}
                    end
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULT_COOLDOWN_SWIPE_COLOR")
        end)

        rootDescription:CreateDivider()

        AddColorSwatch(rootDescription, "Default Aura Swipe Color", db.defaultAuraSwipeColor,
            RefreshCooldownManagerFrames)

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
                    local r, g, b, a = unpack(db.defaultAuraSwipeColor)
                    for spellID, _ in pairs(db.spellSettings) do
                        db.spellSettings[spellID].auraSwipeColor = {r, g, b, a}
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
        InitializeDB()
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
    print("/cdm - Open Advanced Cooldown Settings panel")
    print("/wcdm settings - Open Advanced Cooldown Settings panel")
    print("/wcdm force {<spellID>,all} - Disable aura (force cooldown) for <spellID> or all spell IDs")
    print("/wcdm clear {<spellID>,all} - Enable aura for <spellID> or all spell IDs")
    print("/wcdm <spellID> - Show settings for spell ID")
    print("/wcdm help - Show this help message")
    print()
    print("Note: Right click spells in the Advanced Cooldown Settings panel to change its settings.")
end

SLASH_WCDM1 = "/wcdm"
SlashCmdList["WCDM"] = function(msg, editBox)
    if msg == "settings" then
        ShowUIPanel(CooldownViewerSettings)
    elseif starts_with(msg, "force") then
        local arg = msg:match("force%s+(%S+)")
        if arg == "all" then
            SetShowAuraAll(false)
            return
        end

        local spellID = tonumber(msg:match("force%s+(%d+)"))
        if spellID then
            SetShowAura(spellID, false)
            return
        end

        print("Usage: /wcdm force {<spellID>,all}")
    elseif starts_with(msg, "clear") then
        local arg = msg:match("clear%s+(%S+)")
        if arg == "all" then
            SetShowAuraAll(true)
            return
        end

        local spellID = tonumber(msg:match("clear%s+(%d+)"))
        if spellID then
            SetShowAura(spellID, true)
            return
        end

        print("Usage: /wcdm clear {<spellID>,all}")
    elseif msg == "help" then
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
