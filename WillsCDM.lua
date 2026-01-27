local addonName, _ = ...

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

local function ForceIgnoreSpellAuras()
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

                self:SetReverse(false)
                self:SetDrawEdge(true)
                self:SetDrawSwipe(true)
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

                self:SetDesaturation(desaturation)
                do
                    return
                end

                if cdmFrame.wasSetFromAura and cdmFrame:GetAuraDataUnit() ~= "target" then
                    -- TODO: If wasSetFromAura, it will never show swipe. This is because desatured is false when the aura is active.
                    -- Attempting to set swipe based on desaturation will not work in this case.
                    -- We also can't use wasSetFromAura to determine swipe state, because it may have a charge whether or not the aura is active.
                    -- Note that if the spell has an aura associated with it, and the aura is active, CooldownFlash will also be hidden.
                    if InCombatLockdown() then
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

local function Run()
    ForceIgnoreSpellAuras()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:SetScript("OnEvent", function(self, event, eventAddonName)
    if event == "ADDON_LOADED" and eventAddonName == addonName then
        InitializeDB()
        Run()

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
        elseif arg == "all" then
            local db = GetDB()
            db.showAurasSpellIDs = {}
            print("Cleared all spellID overrides. Reverting to default behavior.")
            Run()
        else
            print("Usage: /wcdm clear {<spellID>|all}")
        end
    elseif starts_with(msg, "default") then
        local bool = msg:match("default%s+(%S+)")
        if bool == "hide" then
            local db = GetDB()
            db.showAurasGlobal = false
            print("Hide all auras. Specific spellIDs can be overridden to show auras using /wcdm show <spellID>.")
            Run()
        elseif bool == "show" then
            local db = GetDB()
            db.showAurasGlobal = true
            print("Show all auras. Specific spellIDs can be overridden to hide auras using /wcdm hide <spellID>.")
            Run()
        else
            local db = GetDB()
            local status = db.showAurasGlobal and "Shown" or "Hidden"
            print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
            print("Usage: /wcdm default {hide|show}")
        end
    elseif msg == "list" then
        local db = GetDB()
        local status = db.showAurasGlobal and "Shown" or "Hidden"
        print("Default (used for spells not specifically hidden or shown): " .. status .. ".")
        for spellID, showing in pairs(db.showAurasSpellIDs) do
            print(spellID .. ": " .. (showing and "Shown" or "Hidden"))
        end
    else
        print("Will's CDM commands:")
        print("/wcdm settings - Open Cooldown Viewer Settings")
        print("/wcdm hide <spellID> - Hide auras for <spellID>")
        print("/wcdm show <spellID> - Show auras for <spellID>")
        print("/wcdm clear {<spellID>|all} - Clear override for <spellID> or all spell IDs")
        print("/wcdm default {hide|show} - Set whether to hide auras for spells not specifically hidden or shown")
        print("/wcdm list - List all spell IDs currently set to be hidden or shown")
    end
end
