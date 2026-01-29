local addonName, _ = ...

local panelFrame

AuraMode = {
    SHOW = 1,
    HIDE = 2
}

local dbDefaults = {
    showAurasGlobal = AuraMode.HIDE,
    showAurasSpellIDs = {}
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

local function getAuraModeForSpellID(spellID)
    local db = GetDB()

    if db.showAurasSpellIDs[spellID] ~= nil then
        return db.showAurasSpellIDs[spellID]
    else
        return db.showAurasGlobal
    end
end

local desaturationCurve = C_CurveUtil.CreateCurve()
desaturationCurve:AddPoint(0, 0)
desaturationCurve:AddPoint(0.001, 1)

local function HookFrame(cdmFrame)
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
        local auraMode = getAuraModeForSpellID(spellID)
        self:SetDrawEdge(true)

        if auraMode == AuraMode.SHOW then
            -- Blizzard already shows the aura by default, so we just don't interfere.
            return
        end

        local cooldownDuration = C_Spell.GetSpellCooldownDuration(spellID)

        self:SetCooldownFromDurationObject(cooldownDuration)
        if C_Spell.GetSpellCharges(spellID) then
            self:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(spellID))
        end

        local cooldown = C_Spell.GetSpellCooldown(spellID)
        if cooldown and cooldown.isOnGCD then
            cdmFrame.WillsCDM_Desaturation = 0
        else
            cdmFrame.WillsCDM_Desaturation = cooldownDuration:EvaluateRemainingPercent(desaturationCurve)
        end

        if auraMode == AuraMode.HIDE then
            -- Blizzard sets the swipe color when showing aura duration.
            self:SetSwipeColor(0, 0, 0, 0.7)
            self:SetReverse(false)
        end
    end)

    hooksecurefunc(cdmFrame.Icon, "SetDesaturated", function(self, desaturated)
        local cdmFrame = self:GetParent()
        local cooldownInfo = cdmFrame:GetCooldownInfo()

        if cooldownInfo == nil then
            return
        end

        local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
        local auraMode = getAuraModeForSpellID(spellID)

        if auraMode == AuraMode.SHOW then
            cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownShowSwipe == true)
            return
        end

        if cdmFrame.wasSetFromAura then
            self:SetDesaturation(cdmFrame.WillsCDM_Desaturation)
        end

        if cdmFrame.wasSetFromAura and cdmFrame:GetAuraDataUnit() ~= "target" then
            -- TODO: If wasSetFromAura, it will never show swipe. This is because desatured is false when the aura is active.
            -- Attempting to set swipe based on desaturation will not work in this case.
            -- We also can't use wasSetFromAura to determine swipe state, because it may have a charge whether or not the aura is active.
            -- Note that if the spell has an aura associated with it, and the aura is active, CooldownFlash will also be hidden.
            if issecretvalue(cdmFrame.cooldownChargesCount) or issecretvalue(cdmFrame.cooldownChargesShown) then
                -- We can use isSecret to determine if the spell has exactly 1 charge or not.
                if issecretvalue(desaturated) then
                    -- The spell either has 0 or 2+ charges.
                    -- We can use CooldownFlash to determine if we are at 0 charges (flash shown) or 2+ charges (flash hidden).
                    cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.CooldownFlash:IsShown())
                else
                    -- The spell has exactly 1 charge.
                    cdmFrame.Cooldown:SetDrawSwipe(false)
                end
            else
                -- We're not in combat, so we can use cooldownChargesCount and cooldownChargesShown.
                cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownChargesCount == 0 and cdmFrame.cooldownChargesShown)
            end
        end
    end)

    cdmFrame.WillsCDM_Hooked = true
end

local function HookFrames()
    local cooldownFrames = GetCooldownFrames()

    for _, cdmFrame in ipairs(cooldownFrames) do
        if not cdmFrame.WillsCDM_Hooked then
            if cdmFrame.Cooldown ~= nil then
                HookFrame(cdmFrame)
            end
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

local function RefreshPanel()
    if not panelFrame or not panelFrame:IsShown() then
        return
    end

    if not panelFrame.overrideScrollFrame or not panelFrame.overrideContent then
        return
    end

    local db = GetDB()

    local globalStatus = db.showAurasGlobal == AuraMode.SHOW and "Show All Auras" or "Hide All Auras"
    panelFrame.globalDropdown:OverrideText(globalStatus)

    local keys = SortedKeys(db.showAurasSpellIDs)

    local rowSpacing = 40

    for index, spellID in ipairs(keys) do
        local row = panelFrame.overrideRows[index]

        if not row then
            row = CreateFrame("Frame", nil, panelFrame.overrideContent)
            row:SetSize(220, 32)
            row:SetPoint("TOPLEFT", panelFrame.overrideContent, "TOPLEFT", 0, -(index - 1) * rowSpacing)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(32, 32)
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

            row.dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
            row.dropdown:SetSize(140, 24)
            row.dropdown:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)

            row.clearButton = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
            row.clearButton:SetSize(24, 24)
            row.clearButton:SetPoint("LEFT", row.dropdown, "RIGHT", 3, 0)
            row.clearButton:SetText("X")

            row.icon:SetScript("OnEnter", function(self)
                if not row.spellID then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(row.spellID)
                GameTooltip:Show()
            end)
            row.icon:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row.dropdown:SetupMenu(function(owner, rootDescription)
                rootDescription:CreateButton("Show Auras", function()
                    if not row.spellID then
                        return
                    end

                    local db = GetDB()
                    db.showAurasSpellIDs[row.spellID] = AuraMode.SHOW
                    RefreshPanel()
                end)
                rootDescription:CreateButton("Hide Auras", function()
                    if not row.spellID then
                        return
                    end

                    local db = GetDB()
                    db.showAurasSpellIDs[row.spellID] = AuraMode.HIDE
                    RefreshPanel()
                end)
            end)

            row.clearButton:SetScript("OnClick", function(button, ...)
                if not row.spellID then
                    return
                end

                local db = GetDB()
                db.showAurasSpellIDs[row.spellID] = nil
                RefreshPanel()
            end)

            panelFrame.overrideRows[index] = row
        else
            row:SetParent(panelFrame.overrideContent)
            row:SetPoint("TOPLEFT", panelFrame.overrideContent, "TOPLEFT", 0, -(index - 1) * rowSpacing)
        end

        local auraMode = db.showAurasSpellIDs[spellID]

        row.spellID = spellID
        row.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        if auraMode == AuraMode.SHOW then
            row.dropdown:OverrideText("Show Auras")
        elseif auraMode == AuraMode.HIDE then
            row.dropdown:OverrideText("Hide Auras")
        end
        row:Show()
    end

    local scrollFrame = panelFrame.overrideScrollFrame
    local content = panelFrame.overrideContent
    local contentHeight = math.max(#keys * rowSpacing, scrollFrame:GetHeight())
    content:SetHeight(contentHeight)

    local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    end

    for index = #keys + 1, #panelFrame.overrideRows do
        panelFrame.overrideRows[index]:Hide()
        panelFrame.overrideRows[index].spellID = nil
    end
end

local function AttachPanelToCooldownViewerSettings()
    if not panelFrame then
        return
    end

    local cooldownViewerSettings = _G["CooldownViewerSettings"]

    local xOffset = 55

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", cooldownViewerSettings, "TOPRIGHT", xOffset, 0)
    panelFrame:SetPoint("BOTTOMLEFT", cooldownViewerSettings, "BOTTOMRIGHT", xOffset, 3)
    panelFrame:SetWidth(256)

    cooldownViewerSettings:HookScript("OnShow", function()
        if panelFrame and not InCombatLockdown() then
            panelFrame:Show()
            panelFrame:SetFrameStrata("DIALOG")
            RefreshPanel()
        end
    end)

    cooldownViewerSettings:HookScript("OnHide", function()
        if panelFrame then
            panelFrame:Hide()
        end
    end)

    if cooldownViewerSettings:IsShown() then
        panelFrame:Show()
    else
        panelFrame:Hide()
    end
end

local function CreateWillsCDMSettingsFrame()
    local frame = CreateFrame("Frame", "WillsCDMSettings", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(256, 512)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, -2)
    frame.title:SetText("Will's CDM Aura Settings")

    frame.overrideRows = {}
    panelFrame = frame

    frame:Hide()

    local db = GetDB()

    local globalLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    globalLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
    globalLabel:SetText("Global")

    local globalDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    globalDropdown:SetSize(216, 24)
    globalDropdown:SetPoint("TOPLEFT", globalLabel, "TOPLEFT", 0, -15)
    globalDropdown:SetupMenu(function(owner, rootDescription)
        rootDescription:CreateTitle("Default Aura Display");
        rootDescription:CreateButton("Show All Auras", function(data)
            db.showAurasGlobal = AuraMode.SHOW
            owner:OverrideText("Show All Auras")
        end);
        rootDescription:CreateButton("Hide All Auras", function(data)
            db.showAurasGlobal = AuraMode.HIDE
            owner:OverrideText("Hide All Auras")
        end);
    end)
    if db.showAurasGlobal == AuraMode.SHOW then
        globalDropdown:OverrideText("Show All Auras")
    elseif db.showAurasGlobal == AuraMode.HIDE then
        globalDropdown:OverrideText("Hide All Auras")
    end
    frame.globalDropdown = globalDropdown

    local overrideLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    overrideLabel:SetPoint("TOPLEFT", globalDropdown, "BOTTOMLEFT", 0, -20)
    overrideLabel:SetText("Overrides")

    local overrideAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    overrideAddButton:SetSize(100, 24)
    overrideAddButton:SetPoint("TOPRIGHT", globalDropdown, "BOTTOMRIGHT", 0, -14)
    overrideAddButton:SetText("Add Override")
    overrideAddButton:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(overrideAddButton, function(owner, rootDescription)
            rootDescription:CreateTitle("Select Spell to Override");
            for _, cdmFrame in ipairs(GetCooldownFrames()) do
                local cooldownInfo = cdmFrame:GetCooldownInfo()
                if cooldownInfo then
                    local spellID = cooldownInfo.spellID
                    if db.showAurasSpellIDs[spellID] == nil then
                        local spellName = C_Spell.GetSpellName(spellID)
                        local texture = C_Spell.GetSpellTexture(spellID)
                        local iconTag = texture and ("|T" .. texture .. ":14:14:0:0|t ") or ""
                        local label = iconTag .. spellName .. " (ID: " .. spellID .. ")"

                        rootDescription:CreateButton(label, function()
                            local db = GetDB()
                            db.showAurasSpellIDs[spellID] = AuraMode.SHOW
                            RefreshPanel()
                        end)
                    end
                end
            end
            rootDescription:CreateDivider()
            rootDescription:CreateButton("Manual Spell ID Entry", function()
                local inputFrame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
                inputFrame:SetSize(300, 120)
                inputFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                inputFrame.title = inputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                inputFrame.title:SetPoint("CENTER", inputFrame.TitleBg, "CENTER", 0, -2)
                inputFrame.title:SetText("Enter Spell ID to Override")
                inputFrame.inputBox = CreateFrame("EditBox", nil, inputFrame, "InputBoxTemplate")
                inputFrame.inputBox:SetSize(200, 30)
                inputFrame.inputBox:SetPoint("TOP", inputFrame, "TOP", 0, -40)
                inputFrame.inputBox:SetAutoFocus(true)
                inputFrame.inputBox:SetNumeric(true)
                inputFrame.inputBox:SetFocus()
                inputFrame.confirmButton = CreateFrame("Button", nil, inputFrame, "GameMenuButtonTemplate")
                inputFrame.confirmButton:SetSize(80, 24)
                inputFrame.confirmButton:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOMRIGHT", -10, 10)
                inputFrame.confirmButton:SetText("Confirm")
                inputFrame.confirmButton:SetScript("OnClick", function()
                    local spellID = tonumber(inputFrame.inputBox:GetText())
                    if spellID then
                        db.showAurasSpellIDs[spellID] = AuraMode.SHOW
                        RefreshPanel()
                        inputFrame:Hide()
                    else
                        print("Invalid Spell ID entered.")
                    end
                end)
                inputFrame:Show()
            end)
        end)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -120)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 8)
    scrollFrame:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
    scrollFrame:SetScrollChild(content)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local step = 30
        local newScroll = self:GetVerticalScroll() - (delta * step)
        if newScroll < 0 then
            newScroll = 0
        elseif newScroll > maxScroll then
            newScroll = maxScroll
        end
        self:SetVerticalScroll(newScroll)
    end)

    scrollFrame:SetScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
        RefreshPanel()
    end)

    frame.overrideScrollFrame = scrollFrame
    frame.overrideContent = content

    RefreshPanel()
    AttachPanelToCooldownViewerSettings()
end

local function Run()
    HookFrames()

    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        HookFrames()
    end)
end

local function ClosePanelsForCombat()
    if panelFrame and panelFrame:IsShown() then
        panelFrame:Hide()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function(self, event, eventAddonName)
    if event == "ADDON_LOADED" and eventAddonName == addonName then
        InitializeDB()
        C_Timer.After(1, Run)
        C_Timer.After(1, CreateWillsCDMSettingsFrame)

        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_DISABLED" then
        ClosePanelsForCombat()
    end
end)

SLASH_CDM1 = "/cdm"
SlashCmdList["CDM"] = function()
    ShowUIPanel(CooldownViewerSettings)
end

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

SLASH_WCDM1 = "/wcdm"
SlashCmdList["WCDM"] = function(msg, editBox)
    if msg == "settings" then
        ShowUIPanel(CooldownViewerSettings)
    elseif starts_with(msg, "hide") then
        local spellID = tonumber(msg:match("hide%s+(%d+)"))
        if spellID then
            local db = GetDB()
            db.showAurasSpellIDs[spellID] = AuraMode.HIDE
            print("Hiding auras for spellID " .. spellID .. ".")
            RefreshPanel()
        else
            print("Usage: /wcdm hide <spellID>")
        end
    elseif starts_with(msg, "show") then
        local spellID = tonumber(msg:match("show%s+(%d+)"))
        if spellID then
            local db = GetDB()
            db.showAurasSpellIDs[spellID] = AuraMode.SHOW
            print("Showing auras for spellID " .. spellID .. ".")
            RefreshPanel()
        else
            print("Usage: /wcdm show <spellID>")
        end
    elseif starts_with(msg, "clear") then
        local arg = msg:match("clear%s+(%S+)")
        local spellID = tonumber(arg)
        if spellID then
            local db = GetDB()
            db.showAurasSpellIDs[spellID] = nil
            print("Cleared spellID override for " .. spellID .. ". Reverting to default behavior.")
            RefreshPanel()
        elseif arg == "all" then
            local db = GetDB()
            db.showAurasSpellIDs = {}
            print("Cleared all spellID overrides. Reverting to default behavior.")
            RefreshPanel()
        else
            print("Usage: /wcdm clear {<spellID>,all}")
        end
    elseif starts_with(msg, "default") then
        local arg = msg:match("default%s+(%S+)")
        if arg == "hide" then
            local db = GetDB()
            db.showAurasGlobal = AuraMode.HIDE
            print("Hide all auras. Specific spellIDs can be overridden to show auras using /wcdm show <spellID>.")
            RefreshPanel()
        elseif arg == "show" then
            local db = GetDB()
            db.showAurasGlobal = AuraMode.SHOW
            print("Show all auras. Specific spellIDs can be overridden to hide auras using /wcdm hide <spellID>.")
            RefreshPanel()
        else
            local db = GetDB()
            local status
            if db.showAurasGlobal == AuraMode.SHOW then
                status = "Show Auras"
            elseif db.showAurasGlobal == AuraMode.HIDE then
                status = "Hide Auras"
            end
            print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
            print("Usage: /wcdm default {hide,show}")
        end
    elseif msg == "list" then
        local db = GetDB()
        local status
        if db.showAurasGlobal == AuraMode.SHOW then
            status = "Show Auras"
        elseif db.showAurasGlobal == AuraMode.HIDE then
            status = "Hide Auras"
        end
        print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
        for spellID, showing in pairs(db.showAurasSpellIDs) do
            local spellStatus
            if showing == AuraMode.SHOW then
                spellStatus = "Show Auras"
            elseif showing == AuraMode.HIDE then
                spellStatus = "Hide Auras"
            end
            print(spellID .. ": " .. spellStatus)
        end
    else
        print("/cdm - Open Advanced Cooldown Settings panel")
        print("/wcdm hide <spellID> - Hide auras for <spellID>")
        print("/wcdm show <spellID> - Show auras for <spellID>")
        print("/wcdm clear {<spellID>,all} - Clear override for <spellID> or all spell IDs")
        print("/wcdm default {hide,show} - Set whether to hide auras for spells not specifically hidden or shown")
        print("/wcdm list - List all spell IDs currently set to be hidden or shown")
    end
end
