local addonName, addon = ...
addon = addon or {}

local ItemVisuals = addon.ItemVisuals or {}
addon.ItemVisuals = ItemVisuals

local FALLBACK_ICON = 134400

function ItemVisuals:GetItemIcon(itemID)
    local icon = C_Item.GetItemIconByID(itemID)
    if not icon and GetItemIcon then
        icon = GetItemIcon(itemID)
    end
    return icon or FALLBACK_ICON
end

function ItemVisuals:ApplyItemIcon(frame, itemID)
    if not frame or not frame.Icon then
        return
    end
    frame.Icon:SetTexture(self:GetItemIcon(itemID))
end

function ItemVisuals:SetEmptySlot(frame)
    if not frame then
        return
    end
    if frame.Icon then
        frame.Icon:SetTexture(nil)
        frame.Icon:SetAtlas("cdm-empty", true)
        frame.Icon:SetDesaturated(false)
    end
    if frame.Cooldown then
        CooldownFrame_Clear(frame.Cooldown)
    end
end

function ItemVisuals:ClearCooldown(frame, desaturation)
    if not frame then
        return
    end
    if frame.Cooldown then
        CooldownFrame_Clear(frame.Cooldown)
        frame.Cooldown:SetDrawSwipe(false)
    end
    if desaturation ~= nil and frame.Icon then
        frame.Icon:SetDesaturation(desaturation)
    end
end

function ItemVisuals:UpdateItemCooldown(frame, itemID)
    if not frame or not frame.Cooldown then
        return false
    end

    local startTime, duration, enable = C_Item.GetItemCooldown(itemID)
    if enable == 0 or not duration or duration == 0 then
        self:ClearCooldown(frame, 0)
        frame.cooldownStartTime = 0
        frame.cooldownDuration = 0
        return false
    end

    frame.Cooldown:SetCooldown(startTime, duration)
    frame.Cooldown:SetDrawSwipe(true)
    if frame.Icon then
        frame.Icon:SetDesaturation(1)
    end
    frame.cooldownStartTime = startTime or 0
    frame.cooldownDuration = duration or 0
    return true
end
