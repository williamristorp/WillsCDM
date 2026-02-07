local addonName, addon = ...
addon = addon or {}
addon.MiscPanel = addon.MiscPanel or {}

local DB = addon.DB
local MiscPanel = addon.MiscPanel
local ItemsData = addon.ItemsData
local ItemViewer = addon.ItemViewer

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

addon.GetCooldownFrames = GetCooldownFrames

local function GetBuffIconFrames()
    local frames = {}

    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer then
        for _, child in ipairs({buffViewer:GetChildren()}) do
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

local function ApplyIconSettings(cdmFrame)
    local cooldownInfo = cdmFrame:GetCooldownInfo()
    if cooldownInfo == nil then
        return
    end

    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    if not spellID then
        return
    end

    if DB.GetShowAuras(spellID) and cdmFrame.wasSetFromAura then
        cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownShowSwipe == true)
        cdmFrame.Icon:SetDesaturation(0)
        return
    end

    if cdmFrame.wasSetFromAura then
        cdmFrame.Icon:SetDesaturation(cdmFrame.WillsCDM_Desaturation)

        local spellCharges = C_Spell.GetSpellCharges(spellID)
        if spellCharges then
            if issecretvalue(spellCharges.currentCharges) or issecretvalue(spellCharges.maxCharges) then
                if issecretvalue(cdmFrame.Icon:IsDesaturated()) then
                    local flashIsShown = cdmFrame.CooldownFlash:IsShown()
                    cdmFrame.Cooldown:SetDrawSwipe(flashIsShown)
                    cdmFrame.Cooldown:SetDrawEdge(not flashIsShown or DB.GetAlwaysShowCooldownEdge(spellID))
                else
                    cdmFrame.Cooldown:SetDrawSwipe(false)
                    cdmFrame.Cooldown:SetDrawEdge(true)
                end
            else
                cdmFrame.Cooldown:SetDrawSwipe(spellCharges.currentCharges == 0)
                cdmFrame.Cooldown:SetDrawEdge(spellCharges.currentCharges < spellCharges.maxCharges or
                                                  DB.GetAlwaysShowCooldownEdge(spellID))
            end
        else
            cdmFrame.Cooldown:SetDrawSwipe(true)
        end
    end
end

local function ApplyCooldownSettings(cdmFrame)
    local cooldownInfo = cdmFrame:GetCooldownInfo()
    if cooldownInfo == nil then
        return
    end

    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
    if not spellID then
        return
    end

    if DB.GetAlwaysShowCooldownEdge(spellID) then
        cdmFrame.Cooldown:SetDrawEdge(true)
    end

    if DB.GetShowAuras(spellID) and cdmFrame.wasSetFromAura then
        cdmFrame.Cooldown:SetSwipeColor(unpack(DB.GetAuraSwipeColor(spellID)))
        cdmFrame.Cooldown:SetReverse(DB.GetAuraSwipeReversed(spellID))
        return
    end

    cdmFrame.Cooldown:SetSwipeColor(unpack(DB.GetCooldownSwipeColor(spellID)))

    local cooldownDuration = C_Spell.GetSpellCooldownDuration(spellID)
    cdmFrame.Cooldown:SetCooldownFromDurationObject(cooldownDuration)
    if C_Spell.GetSpellCharges(spellID) then
        cdmFrame.Cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(spellID))
    else
        cdmFrame.Cooldown:SetDrawSwipe(true)
    end

    local cooldown = C_Spell.GetSpellCooldown(spellID)
    if cooldown and cooldown.isOnGCD then
        cdmFrame.WillsCDM_Desaturation = 0
    else
        cdmFrame.WillsCDM_Desaturation = cooldownDuration:EvaluateRemainingPercent(desaturationCurve)
    end

    ApplyIconSettings(cdmFrame)
end

local function HookCooldownFrame(cdmFrame)
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

local function HookBuffIconFrame(cdmFrame)
    if cdmFrame.WillsCDM_Hooked or cdmFrame.Cooldown == nil or cdmFrame.Icon == nil then
        return
    end

    hooksecurefunc(cdmFrame.Cooldown, "SetCooldown", function(self)
        local cdmFrame = self:GetParent()
        local cooldownInfo = cdmFrame:GetCooldownInfo()
        if cooldownInfo == nil then
            return
        end

        local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
        if not spellID then
            return
        end

        cdmFrame.Cooldown:SetSwipeColor(unpack(DB.GetAuraSwipeColor(spellID)))
        cdmFrame.Cooldown:SetReverse(DB.GetAuraSwipeReversed(spellID))
        cdmFrame.Cooldown:SetDrawEdge(DB.GetAlwaysShowCooldownEdge(spellID))
    end)

    cdmFrame.WillsCDM_Hooked = true
end

local function HookFrames()
    local cooldownFrames = GetCooldownFrames()

    for _, cdmFrame in ipairs(cooldownFrames) do
        if not cdmFrame.WillsCDM_Hooked then
            if cdmFrame.Cooldown ~= nil then
                HookCooldownFrame(cdmFrame)
            end
        end
    end

    local buffIconFrames = GetBuffIconFrames()

    for _, cdmFrame in ipairs(buffIconFrames) do
        if not cdmFrame.WillsCDM_Hooked then
            if cdmFrame.Cooldown ~= nil then
                HookBuffIconFrame(cdmFrame)
            end
        end
    end
end

local function RefreshCooldownManagerFrames()
    if InCombatLockdown() then
        return
    end

    HookFrames()

    for _, cdmFrame in ipairs(GetCooldownFrames()) do
        if cdmFrame.Cooldown and cdmFrame.Icon then
            ApplyCooldownSettings(cdmFrame)
            ApplyIconSettings(cdmFrame)
        end
    end

    ItemViewer:RefreshItemViewerFrames()
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
    DB.InitializeDB()

    HookFrames()
    ItemViewer:Initialize()

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        HookFrames()
        ItemViewer:RefreshItemViewerFrames()
    end)

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function(arg1, settingsFrame)
        MiscPanel:EnsureMiscSettingsTab(settingsFrame)
        MiscPanel:RefreshMiscPanel(settingsFrame)
    end)

    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription, contextData)
        local cooldownID = owner.cooldownID
        local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
        local category = cdInfo.category
        local spellID = owner:GetBaseSpellID()

        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Will's CDM")

        rootDescription:CreateCheckbox("Always Show Cooldown Edge", function()
            return DB.GetAlwaysShowCooldownEdge(spellID)
        end, function()
            DB.ToggleAlwaysShowCooldownEdge(spellID)
            RefreshCooldownManagerFrames()
        end)

        if category == 0 or category == 1 then
            AddColorSwatch(rootDescription, "Cooldown Swipe Color", function()
                return DB.GetCooldownSwipeColor(spellID)
            end, function(color)
                DB.SetCooldownSwipeColor(spellID, color)
            end, RefreshCooldownManagerFrames)

            rootDescription:CreateCheckbox("Show Auras", function()
                return DB.GetShowAuras(spellID)
            end, function()
                DB.ToggleShowAuras(spellID)
                RefreshCooldownManagerFrames()
            end)
        end

        AddColorSwatch(rootDescription, "Aura Swipe Color", function()
            return DB.GetAuraSwipeColor(spellID)
        end, function(color)
            DB.SetAuraSwipeColor(spellID, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateCheckbox("Reverse Aura Swipe", function()
            return DB.GetAuraSwipeReversed(spellID)
        end, function()
            DB.ToggleAuraSwipeReversed(spellID)
            RefreshCooldownManagerFrames()
        end)

        rootDescription:CreateButton("Reset to Defaults", function()
            local db = DB.GetDB()
            db.spellSettings[spellID] = nil
            RefreshCooldownManagerFrames()
        end)
    end)

    Menu.ModifyMenu("COOLDOWN_VIEWER_SETTINGS_MENU", function(owner, rootDescription, contextData)
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Will's CDM")

        local db = DB.GetDB()
        AddColorSwatch(rootDescription, "Default Cooldown Swipe Color", function()
            return db.defaultCooldownSwipeColor
        end, function(color)
            CopyColorInto(db.defaultCooldownSwipeColor, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateCheckbox("Default Always Show Cooldown Edge", function()
            local db = DB.GetDB()
            return db.defaultAlwaysShowCooldownEdge
        end, function()
            local db = DB.GetDB()
            db.defaultAlwaysShowCooldownEdge = not db.defaultAlwaysShowCooldownEdge
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateCheckbox("Default Show Auras", function()
            local db = DB.GetDB()
            return db.defaultShowAuras
        end, function()
            local db = DB.GetDB()
            db.defaultShowAuras = not db.defaultShowAuras
        end)

        AddColorSwatch(rootDescription, "Default Aura Swipe Color", function()
            return db.defaultAuraSwipeColor
        end, function(color)
            CopyColorInto(db.defaultAuraSwipeColor, color)
        end, RefreshCooldownManagerFrames)

        rootDescription:CreateCheckbox("Default Reverse Aura Swipe", function()
            local db = DB.GetDB()
            return db.defaultAuraSwipeReversed
        end, function()
            local db = DB.GetDB()
            db.defaultAuraSwipeReversed = not db.defaultAuraSwipeReversed
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton("Apply Defaults To All Spells", function()
            StaticPopupDialogs["WILLS_CDM_APPLY_DEFAULTS_TO_ALL_SPELLS"] = {
                text = "Are you sure you want to apply the defaults to all spells?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local db = DB.GetDB()
                    local keys = {}
                    for spellID in pairs(db.spellSettings) do
                        table.insert(keys, spellID)
                    end
                    for _, spellID in ipairs(keys) do
                        db.spellSettings[spellID].auraSwipeColor = nil
                        db.spellSettings[spellID].cooldownSwipeColor = nil
                        db.spellSettings[spellID].alwaysShowCooldownEdge = nil
                        db.spellSettings[spellID].showAuras = nil
                        db.spellSettings[spellID].auraSwipeReversed = nil
                        DB.CleanupSpellSettings(spellID)
                    end
                    RefreshCooldownManagerFrames()
                end
            }

            StaticPopup_Show("WILLS_CDM_APPLY_DEFAULTS_TO_ALL_SPELLS")
        end)

        rootDescription:CreateButton("Reset Defaults", function()
            StaticPopupDialogs["WILLS_CDM_RESET_DEFAULTS"] = {
                text = "Are you sure you want to reset the default settings?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local db = DB.GetDB()
                    db.defaultAlwaysShowCooldownEdge = false
                    db.defaultAuraSwipeColor = {unpack(DB.DEFAULT_AURA_SWIPE_COLOR)}
                    db.defaultCooldownSwipeColor = {unpack(DB.DEFAULT_COOLDOWN_SWIPE_COLOR)}
                    db.defaultShowAuras = true
                    RefreshCooldownManagerFrames()
                end
            }
            StaticPopup_Show("WILLS_CDM_RESET_DEFAULTS")
        end)
    end)

    local refreshFrame = CreateFrame("Frame")
    refreshFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    refreshFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    refreshFrame:RegisterEvent("BAG_UPDATE")
    refreshFrame:RegisterEvent("SPELLS_CHANGED")
    refreshFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            if unit ~= "player" then
                return
            end
        end
        if event == "SPELLS_CHANGED" then
            if ItemsData and ItemsData.InvalidateRacialSpellCache then
                ItemsData:InvalidateRacialSpellCache()
            end
        end
        MiscPanel:RefreshMiscPanel()
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

    if DB.GetShowAuras(spellID) then
        print(spellName .. " (ID: " .. spellID .. ") has aura enabled.")
    else
        print(spellName .. " (ID: " .. spellID .. ") has aura disabled (cooldown forced).")
    end
end

local function PrintHelp()
    print("/cdm - Open Advanced Cooldown Settings panel (might not work if another addon overrides it)")
    print("/wcdm - Open Advanced Cooldown Settings panel")
    print("/wcdm settings - Open Advanced Cooldown Settings panel")
    print("/wcdm aura {<spellID>,all} [toggle|on|off] - Control the GUI 'Show Auras' option")
    print("/wcdm reset {<spellID>,all} - Reset settings for <spellID> or all spell IDs")
    print("/wcdm items add <count> - Add <count> dummy items to the Items panel")
    print("/wcdm items clear - Remove dummy items from the Items panel")
    print("/wcdm <spellID> - Show settings for spell ID")
    print("/wcdm help - Print this help message")
    print()
    print("Note: Right click spells in the Advanced Cooldown Settings panel to change its settings.")
end

SLASH_WCDM1 = "/wcdm"
SlashCmdList["WCDM"] = function(msg, editBox)
    local function Trim(str)
        if str == nil then
            return ""
        end
        return (str:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function SplitFirst(str)
        str = Trim(str)
        if str == "" then
            return "", ""
        end
        local a, b = str:match("^(%S+)%s*(.-)$")
        return a or "", b or ""
    end

    local function ParseOnOffToggle(str)
        str = Trim(str):lower()
        if str == "" or str == "toggle" then
            return "toggle"
        end
        if str == "on" or str == "enable" or str == "enabled" or str == "true" or str == "1" then
            return true
        end
        if str == "off" or str == "disable" or str == "disabled" or str == "false" or str == "0" then
            return false
        end
        return nil
    end

    local function AddDummyItems(count)
        count = tonumber(count)
        if not count or count <= 0 then
            print("Usage: /wcdm items add <count>")
            return
        end

        local itemsData = addon.ItemsData
        local db = DB.GetDB()
        db.itemSettings = db.itemSettings or {}

        local shownState = itemsData and itemsData.ITEM_STATE_SHOWN or "shown"
        local shownEntries = (itemsData and itemsData.GetEntriesByState) and itemsData:GetEntriesByState(shownState) or
                                 {}

        local maxOrder = 0
        for _, entry in ipairs(shownEntries) do
            local settings = nil
            if entry.kind == "spell" then
                settings = DB.GetSpellItemSettings(entry.id)
            else
                settings = DB.GetItemSettings(entry.id)
            end
            if settings and settings.order and settings.order > maxOrder then
                maxOrder = settings.order
            end
        end

        local baseID = 9000000
        local added = 0
        local nextID = baseID
        while added < count do
            if db.itemSettings[nextID] == nil then
                DB.SetItemState(nextID, shownState)
                local settings = DB.EnsureItemSettings(nextID)
                maxOrder = maxOrder + 1
                settings.order = maxOrder
                added = added + 1
            end
            nextID = nextID + 1
        end

        if MiscPanel and MiscPanel.RefreshMiscPanel then
            MiscPanel:RefreshMiscPanel()
        end
        if ItemViewer and ItemViewer.RefreshItemViewerFrames then
            ItemViewer:RefreshItemViewerFrames()
        end

        print("Added " .. added .. " dummy items to the Items panel.")
    end

    local function ClearDummyItems()
        local itemsData = addon.ItemsData
        local db = DB.GetDB()
        if not db.itemSettings then
            print("No dummy items to remove.")
            return
        end

        local baseID = 9000000
        local maxID = baseID + 100000
        local removed = 0

        for itemID, _ in pairs(db.itemSettings) do
            if type(itemID) == "number" and itemID >= baseID and itemID <= maxID then
                DB.SetItemState(itemID, nil)
                removed = removed + 1
            end
        end

        if itemsData and itemsData.GetItemIDsByState then
            itemsData:GetItemIDsByState(itemsData.ITEM_STATE_SHOWN)
            itemsData:GetItemIDsByState(itemsData.ITEM_STATE_HIDDEN)
        end

        if MiscPanel and MiscPanel.RefreshMiscPanel then
            MiscPanel:RefreshMiscPanel()
        end
        if ItemViewer and ItemViewer.RefreshItemViewerFrames then
            ItemViewer:RefreshItemViewerFrames()
        end

        print("Removed " .. removed .. " dummy items from the Items panel.")
    end

    msg = Trim(msg)
    if msg == "" or msg == "settings" then
        print("Use /wcdm help for command usage.")
        ShowUIPanel(CooldownViewerSettings)
    else
        local cmd, rest = SplitFirst(msg)

        if cmd == "aura" or cmd == "auras" then
            local target, modeStr = SplitFirst(rest)
            if target == "" then
                print("Usage: /wcdm aura {<spellID>,all} [toggle|on|off]")
                return
            end

            local mode = ParseOnOffToggle(modeStr)
            if mode == nil then
                print("Usage: /wcdm aura {<spellID>,all} [toggle|on|off]")
                return
            end

            if target:lower() == "all" then
                local db = DB.GetDB()
                local nextValue
                if mode == "toggle" then
                    nextValue = not db.defaultShowAuras
                else
                    nextValue = mode
                end
                DB.SetShowAurasAll(nextValue)
                RefreshCooldownManagerFrames()
                print("Default 'Show Auras' is now " .. (nextValue and "enabled" or "disabled") .. " for all spells.")
                return
            end

            local spellID = tonumber(target)
            if not spellID then
                print("Usage: /wcdm aura {<spellID>,all} [toggle|on|off]")
                return
            end

            if mode == "toggle" then
                DB.ToggleShowAuras(spellID)
            else
                DB.SetShowAuras(spellID, mode)
            end
            RefreshCooldownManagerFrames()
            PrintIsShowAura(spellID)
            return
        elseif cmd == "items" or cmd == "item" then
            local sub, subRest = SplitFirst(rest)
            local count = nil
            if sub == "add" or sub == "dummy" then
                count = Trim(subRest)
            elseif tonumber(sub) then
                count = sub
            end

            if sub == "clear" or sub == "remove" then
                ClearDummyItems()
                return
            end

            if not count then
                print("Usage: /wcdm items add <count>")
                print("Usage: /wcdm items clear")
                return
            end

            AddDummyItems(count)
            return
        elseif cmd == "reset" then
            local arg = Trim(rest)
            if arg == "all" then
                print("Are you sure you want to reset all settings? Use `/wcdm reset all settings` to confirm.")
                print("Note: This will also reset default settings.")
                return
            end

            if arg == "all settings" then
                WillsDB = nil
                DB.InitializeDB()
                RefreshCooldownManagerFrames()
                print("All settings have been reset to defaults.")
                return
            end

            local spellID = tonumber(arg)
            if spellID then
                local db = DB.GetDB()
                db.spellSettings[spellID] = nil
                RefreshCooldownManagerFrames()
                print("Settings for spell ID " .. spellID .. " have been reset to defaults.")
                return
            end

            print("Usage: /wcdm reset <spellID>")
            return
        elseif cmd == "help" or cmd == "--help" then
            PrintHelp()
            return
        else
            local spellID = tonumber(cmd)
            if spellID then
                PrintIsShowAura(spellID)
                return
            end

            print("Unknown command: " .. msg)
            PrintHelp()
            return
        end
    end
end
