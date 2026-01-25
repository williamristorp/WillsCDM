local addonName, _ = ...

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

local function ForceIgnoreSpellAuras()
    local cdOverrideCurve = C_CurveUtil.CreateCurve()
    cdOverrideCurve:AddPoint(0, 0)
    cdOverrideCurve:AddPoint(0.001, 1)
    cdOverrideCurve:AddPoint(1, 1)

    local cooldownFrames = GetCooldownFrames()

    for _, cdmFrame in ipairs(cooldownFrames) do
        local desaturation = 0

        hooksecurefunc(cdmFrame.Cooldown, "SetCooldown", function(self)
            local cooldownInfo = cdmFrame:GetCooldownInfo()
            local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID

            local cooldownDuration = C_Spell.GetSpellCooldownDuration(spellID)
            self:SetCooldownFromDurationObject(cooldownDuration)
            desaturation = cooldownDuration:EvaluateRemainingPercent(cdOverrideCurve)

            if C_Spell.GetSpellCharges(spellID) then
                self:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(spellID))

                local cooldown = C_Spell.GetSpellCooldown(spellID)
                if cooldown and cooldown.isOnGCD then
                    desaturation = 0
                end
            end

            self:SetReverse(false)
            self:SetDrawEdge(true)
            self:SetSwipeColor(0, 0, 0, 0.8)
        end)

        hooksecurefunc(cdmFrame.Icon, "SetDesaturated", function(self, desaturated)
            if cdmFrame.wasSetFromAura and cdmFrame:GetAuraDataUnit() ~= "target" then
                self:SetDesaturation(desaturation)
            end

            -- TODO: If wasSetFromAura, it will never show swipe. This is because desatured is false when the aura is active.
            -- Attempting to set swipe based on desaturation will not work in this case.
            -- We also can't use wasSetFromAura to determine swipe state, because it may have a charge whether or not the aura is active.
            -- Not that if the spell has an aura associated with it, and the aura is active, CooldownFlash will also be hidden.
            -- For now, we just always hide the swipe. Ideally, swipe is shown when there are exactly 0 charges, hidden otherwise.
            cdmFrame.Cooldown:SetDrawSwipe(false)
            do
                return
            end

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
                cdmFrame.Cooldown:SetDrawSwipe(cdmFrame.cooldownChargesCount == 0 and cdmFrame.cooldownChargesShown)
            end
        end)
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
