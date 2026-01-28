local addonName, _ = ...

local panelFrame

local defaults = {
    showAurasGlobal = false,
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

    ApplyDefaultsToTable(db, defaults)
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

local function showAurasForSpellID(spellID)
    local db = GetDB()

    if db.showAurasSpellIDs[spellID] ~= nil then
        return db.showAurasSpellIDs[spellID]
    else
        return db.showAurasGlobal
    end
end

local function HookCooldowns()
    local desaturationCurve = C_CurveUtil.CreateCurve()
    desaturationCurve:AddPoint(0, 0)
    desaturationCurve:AddPoint(0.001, 1)

    local cooldownFrames = GetCooldownFrames()

    for _, cdmFrame in ipairs(cooldownFrames) do
        if not cdmFrame.WillsCDM_Hooked then
            cdmFrame.WillsCDM_Hooked = true
            local desaturation = 0

            hooksecurefunc(cdmFrame.Cooldown, "SetCooldown", function(self)
                local cdmFrame = self:GetParent()
                local cooldownInfo = cdmFrame:GetCooldownInfo()

                if cooldownInfo == nil then
                    return
                end

                local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID

                if showAurasForSpellID(spellID) then
                    return
                end

                local cooldownDuration = C_Spell.GetSpellCooldownDuration(spellID)

                if C_Spell.GetSpellCharges(spellID) then
                    self:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(spellID))
                else
                    self:SetCooldownFromDurationObject(cooldownDuration)
                end

                local cooldown = C_Spell.GetSpellCooldown(spellID)
                if cooldown and cooldown.isOnGCD then
                    desaturation = 0
                else
                    desaturation = cooldownDuration:EvaluateRemainingPercent(desaturationCurve)
                end

                self:SetDrawEdge(true)
                self:SetReverse(false)
                self:SetSwipeColor(0, 0, 0, 0.7)
            end)

            hooksecurefunc(cdmFrame.Icon, "SetDesaturated", function(self, desaturated)
                local cdmFrame = self:GetParent()
                local cooldownInfo = cdmFrame:GetCooldownInfo()

                if cooldownInfo == nil then
                    return
                end

                local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID

                if showAurasForSpellID(spellID) then
                    cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownShowSwipe == true)
                    return
                end

                if cdmFrame.wasSetFromAura then
                    self:SetDesaturation(desaturation)
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
                        cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownChargesCount == 0 and
                                                           cdmFrame.cooldownChargesShown)
                    end
                end
            end)
        end
    end
end

local function SortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys)
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
                    db.showAurasSpellIDs[row.spellID] = true
                    print("Set to show auras for spellID " .. row.spellID)
                    RefreshPanel()
                end)
                rootDescription:CreateButton("Hide Auras", function()
                    if not row.spellID then
                        return
                    end
                    db.showAurasSpellIDs[row.spellID] = false
                    print("Set to hide auras for spellID " .. row.spellID)
                    RefreshPanel()
                end)
            end)

            row.clearButton:SetScript("OnClick", function()
                if not row.spellID then
                    return
                end
                db.showAurasSpellIDs[row.spellID] = nil
                print("Cleared spellID override for " .. row.spellID .. ". Reverting to default behavior.")
                RefreshPanel()
            end)

            panelFrame.overrideRows[index] = row
        else
            row:SetParent(panelFrame.overrideContent)
            row:SetPoint("TOPLEFT", panelFrame.overrideContent, "TOPLEFT", 0, -(index - 1) * rowSpacing)
        end

        row.spellID = spellID
        row.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        if showAurasForSpellID(spellID) then
            row.dropdown:SetDefaultText("Show Auras")
        else
            row.dropdown:SetDefaultText("Hide Auras")
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

    if panelFrame.WillsCDM_AttachedToCooldownViewerSettings then
        return
    end

    local cooldownViewerSettings = _G["CooldownViewerSettings"]
    if not cooldownViewerSettings then
        C_Timer.After(1, AttachPanelToCooldownViewerSettings)
        return
    end

    local xOffset = 55

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", cooldownViewerSettings, "TOPRIGHT", xOffset, 0)
    panelFrame:SetPoint("BOTTOMLEFT", cooldownViewerSettings, "BOTTOMRIGHT", xOffset, 3)
    panelFrame:SetWidth(256)

    cooldownViewerSettings:HookScript("OnShow", function()
        if panelFrame then
            panelFrame:Show()
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

    panelFrame.WillsCDM_AttachedToCooldownViewerSettings = true
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

    local cooldownFrames = GetCooldownFrames()
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
            db.showAurasGlobal = true
            print("Set default to show all auras.")
            owner:SetDefaultText("Show All Auras")
        end);
        rootDescription:CreateButton("Hide All Auras", function(data)
            db.showAurasGlobal = false
            print("Set default to hide all auras.")
            owner:SetDefaultText("Hide All Auras")
        end);
    end)
    if db.showAurasGlobal then
        globalDropdown:SetDefaultText("Show All Auras")
    else
        globalDropdown:SetDefaultText("Hide All Auras")
    end

    local overrideLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    overrideLabel:SetPoint("TOPLEFT", globalDropdown, "BOTTOMLEFT", 0, -20)
    overrideLabel:SetText("Overrides")

    local overrideAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    overrideAddButton:SetSize(100, 24)
    overrideAddButton:SetPoint("TOPRIGHT", globalDropdown, "BOTTOMRIGHT", 0, -14)
    overrideAddButton:SetText("Add Override")
    overrideAddButton:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(UIParent, function(owner, rootDescription)
            rootDescription:CreateTitle("Select Spell to Override");
            for _, cdmFrame in ipairs(cooldownFrames) do
                local cooldownInfo = cdmFrame:GetCooldownInfo()
                if cooldownInfo then
                    local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
                    if db.showAurasSpellIDs[spellID] == nil then
                        local spellName = cdmFrame:GetNameText() or C_Spell.GetSpellName(spellID) or
                                              ("Spell " .. spellID)
                        local texture = C_Spell.GetSpellTexture(spellID)
                        local iconTag = texture and ("|T" .. texture .. ":14:14:0:0|t ") or ""
                        local label = iconTag .. spellName .. " (ID: " .. spellID .. ")"

                        rootDescription:CreateButton(label, function()
                            db.showAurasSpellIDs[spellID] = not db.showAurasGlobal
                            local action = db.showAurasSpellIDs[spellID] and "show" or "hide"
                            print("Added override for spellID " .. spellID .. " (defaulting to " .. action .. " auras)")
                            RefreshPanel()
                        end)
                    end
                end
            end
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
    HookCooldowns()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:SetScript("OnEvent", function(self, event, eventAddonName)
    if event == "ADDON_LOADED" and eventAddonName == addonName then
        InitializeDB()
        C_Timer.After(1, Run)
        C_Timer.After(1, CreateWillsCDMSettingsFrame)

        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        Run()
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
            db.showAurasSpellIDs[spellID] = false
            print("Hiding auras for spellID " .. spellID .. ".")
            Run()
            RefreshPanel()
        else
            print("Usage: /wcdm hide <spellID>")
        end
    elseif starts_with(msg, "show") then
        local spellID = tonumber(msg:match("show%s+(%d+)"))
        if spellID then
            local db = GetDB()
            db.showAurasSpellIDs[spellID] = true
            print("Showing auras for spellID " .. spellID .. ".")
            Run()
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
            Run()
            RefreshPanel()
        elseif arg == "all" then
            local db = GetDB()
            db.showAurasSpellIDs = {}
            print("Cleared all spellID overrides. Reverting to default behavior.")
            Run()
            RefreshPanel()
        else
            print("Usage: /wcdm clear {<spellID>,all}")
        end
    elseif starts_with(msg, "default") then
        local bool = msg:match("default%s+(%S+)")
        if bool == "hide" then
            local db = GetDB()
            db.showAurasGlobal = false
            print("Hide all auras. Specific spellIDs can be overridden to show auras using /wcdm show <spellID>.")
            Run()
            RefreshPanel()
        elseif bool == "show" then
            local db = GetDB()
            db.showAurasGlobal = true
            print("Show all auras. Specific spellIDs can be overridden to hide auras using /wcdm hide <spellID>.")
            Run()
            RefreshPanel()
        else
            local db = GetDB()
            local status = db.showAurasGlobal and "Shown" or "Hidden"
            print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
            print("Usage: /wcdm default {hide,show}")
        end
    elseif msg == "list" then
        local db = GetDB()
        local status = db.showAurasGlobal and "Shown" or "Hidden"
        print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
        for spellID, showing in pairs(db.showAurasSpellIDs) do
            print(spellID .. ": " .. (showing and "Shown" or "Hidden"))
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
