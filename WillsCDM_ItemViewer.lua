local addonName, addon = ...
addon = addon or {}

local DB = addon.DB
local ItemsData = addon.ItemsData
local ItemViewer = addon.ItemViewer or {}
addon.ItemViewer = ItemViewer

local itemFrames = {}
local itemViewer = nil

local function EnsureItemViewer()
    if itemViewer then
        return
    end

    itemViewer = CreateFrame("Frame", "ItemsCooldownViewer", UIParent)
    itemViewer:SetSize(72, 36)
    itemViewer:Hide()
end

local function GetReferenceIconSize()
    local size = 32
    local getCooldownFrames = addon.GetCooldownFrames
    if getCooldownFrames then
        for _, cdmFrame in ipairs(getCooldownFrames()) do
            local width = cdmFrame:GetWidth()
            if width and width > 0 then
                size = width
                break
            end
        end
    end
    return size
end

local function GetGrowthDirection(layout)
    return (layout and layout.growth) or "center"
end

local function GetHorizontalAnchor(point)
    if point and point:find("LEFT") then
        return "LEFT"
    end
    if point and point:find("RIGHT") then
        return "RIGHT"
    end
    return "CENTER"
end

local function GetGrowthOffset(point, growth, totalWidth)
    if not totalWidth or totalWidth <= 0 then
        return 0
    end

    if growth == "left" then
        local anchor = GetHorizontalAnchor(point)
        if anchor == "LEFT" then
            return 0
        elseif anchor == "CENTER" then
            return -totalWidth / 2
        else
            return -totalWidth
        end
    elseif growth == "right" then
        local anchor = GetHorizontalAnchor(point)
        if anchor == "RIGHT" then
            return 0
        elseif anchor == "CENTER" then
            return totalWidth / 2
        else
            return totalWidth
        end
    end

    return 0
end

local function SetGrowthDirection(layoutName, growth)
    EnsureItemViewer()
    local layout = DB.GetItemViewerLayout(layoutName)
    local totalWidth = itemViewer:GetWidth() or 0
    local oldGrowth = GetGrowthDirection(layout)
    local oldOffset = GetGrowthOffset(layout.point, oldGrowth, totalWidth)
    local newOffset = GetGrowthOffset(layout.point, growth, totalWidth)
    layout.x = (layout.x or 0) + (oldOffset - newOffset)
    layout.growth = growth
end

local function CreateViewerItemFrame(parent)
    local templateName = nil
    local essential = _G["EssentialCooldownViewer"]
    if essential and type(essential.itemTemplate) == "string" then
        templateName = essential.itemTemplate
    end

    local frame = templateName and CreateFrame("Frame", nil, parent, templateName) or CreateFrame("Frame", nil, parent)
    if not frame.Icon then
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        frame.Icon:SetAllPoints()
        frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if not frame.Cooldown then
        frame.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        frame.Cooldown:SetAllPoints()
    end
    if frame.OutOfRange then
        frame.OutOfRange:Hide()
    end
    if frame.cooldownStartTime == nil then
        frame.cooldownStartTime = 0
    end
    if frame.cooldownDuration == nil then
        frame.cooldownDuration = 0
    end
    return frame
end

local function EnsureItemViewerFrames(count)
    EnsureItemViewer()

    for i = 1, count do
        if not itemFrames[i] then
            itemFrames[i] = CreateViewerItemFrame(itemViewer)
        end
        itemFrames[i]:Show()
    end

    for i = count + 1, #itemFrames do
        itemFrames[i]:Hide()
    end
end

local ApplyItemViewerLayout

local function UpdateItemsLayout(count)
    if not itemViewer then
        return
    end

    if count == 0 then
        itemViewer:SetSize(1, 1)
        return
    end

    local baseSize = GetReferenceIconSize()
    local layoutName = itemViewer.WillsCDM_LayoutName or "Default"
    local layout = DB.GetItemViewerLayout(layoutName)
    local spacing = layout.padding or 6
    local scale = layout.scale or 1
    local visualSize = baseSize * scale
    local adjustedSpacing = spacing - (4 * scale)
    local totalWidth = (visualSize * count) + (adjustedSpacing * (count - 1))
    itemViewer:SetSize(totalWidth, visualSize)
    if ApplyItemViewerLayout and not itemViewer.WillsCDM_IsMoving then
        ApplyItemViewerLayout(layoutName)
    end

    for i = 1, count do
        local frame = itemFrames[i]
        frame:SetSize(baseSize, baseSize)
        frame:SetScale(scale)
        if frame.Icon then
            frame.Icon:ClearAllPoints()
            frame.Icon:SetAllPoints()
        end
        if frame.Border then
            frame.Border:ClearAllPoints()
            frame.Border:SetAllPoints()
        end
        if frame.IconBorder then
            frame.IconBorder:ClearAllPoints()
            frame.IconBorder:SetAllPoints()
        end
        if frame.Background then
            frame.Background:ClearAllPoints()
            frame.Background:SetAllPoints()
        end
        if frame.Highlight then
            frame.Highlight:ClearAllPoints()
            frame.Highlight:SetAllPoints()
        end
        if frame.Cooldown then
            frame.Cooldown:ClearAllPoints()
            frame.Cooldown:SetAllPoints()
        end
        local xOffset = (i - 1) * (visualSize + adjustedSpacing) * (1 / scale)
        frame:SetPoint("LEFT", itemViewer, "LEFT", xOffset, 0)
    end
end

local function UpdateItemFrame(frame, itemID)
    if not itemID then
        frame:Hide()
        return
    end

    frame.itemID = itemID
    if frame.Icon then
        frame.Icon:SetTexture(C_Item.GetItemIconByID(itemID))
    end

    if frame.Cooldown then
        local startTime, duration, enable = C_Item.GetItemCooldown(itemID)
        if enable == 0 or not duration or duration == 0 then
            CooldownFrame_Clear(frame.Cooldown)
            frame.Cooldown:SetDrawSwipe(false)
            if frame.Icon then
                frame.Icon:SetDesaturation(0)
            end
            frame.cooldownStartTime = 0
            frame.cooldownDuration = 0
        else
            frame.Cooldown:SetCooldown(startTime, duration)
            frame.Cooldown:SetDrawSwipe(true)
            if frame.Icon then
                frame.Icon:SetDesaturation(1)
            end
            frame.cooldownStartTime = startTime or 0
            frame.cooldownDuration = duration or 0
        end
    end

    frame:Show()
end

local function ShouldShowItemViewer()
    if not itemViewer then
        return false
    end
    if not DB.GetItemViewerEnabled() then
        return false
    end
    if itemViewer.WillsCDM_ForceShow then
        return true
    end
    return itemViewer.WillsCDM_HasItems == true
end

ApplyItemViewerLayout = function(layoutName)
    EnsureItemViewer()
    local layout = DB.GetItemViewerLayout(layoutName)
    local growth = GetGrowthDirection(layout)
    local totalWidth = itemViewer:GetWidth() or 0
    local xOffset = GetGrowthOffset(layout.point, growth, totalWidth)
    itemViewer:ClearAllPoints()
    itemViewer:SetPoint(layout.point, UIParent, layout.point, (layout.x or 0) + xOffset, layout.y or 0)
    itemViewer.WillsCDM_LayoutName = layoutName
end

local function RefreshItemViewerFrames()
    EnsureItemViewer()

    local owned = ItemsData.ScanOwnedItems()
    ItemsData.EnsureTrackedItems(owned)
    local visibleIDs = ItemsData.GetVisibleItemIDs(owned)
    local count = #visibleIDs
    if itemViewer and itemViewer.WillsCDM_ForceShow and count == 0 then
        count = 1
    end

    EnsureItemViewerFrames(count)

    local db = DB.GetDB()
    for i, itemID in ipairs(visibleIDs) do
        local frame = itemFrames[i]
        if frame.Cooldown then
            frame.Cooldown:SetSwipeColor(unpack(db.defaultCooldownSwipeColor))
            frame.Cooldown:SetDrawEdge(db.defaultAlwaysShowCooldownEdge == true)
        end
        UpdateItemFrame(frame, itemID)
    end

    if count > #visibleIDs then
        for i = #visibleIDs + 1, count do
            UpdateItemFrame(itemFrames[i], nil)
        end
    end

    if not InCombatLockdown() then
        UpdateItemsLayout(count)
    end

    itemViewer.WillsCDM_HasItems = #visibleIDs > 0
    itemViewer.WillsCDM_VisibleCount = count
    itemViewer:SetShown(ShouldShowItemViewer())
end

local function InitializeItemsEditMode()
    local LEM = LibStub and LibStub("LibEditMode", true)

    EnsureItemViewer()

    local function OnPositionChanged(frame, layoutName, point, x, y)
        local layout = DB.GetItemViewerLayout(layoutName)
        local totalWidth = itemViewer:GetWidth() or 0
        local growth = GetGrowthDirection(layout)
        local offset = GetGrowthOffset(point, growth, totalWidth)
        layout.point = point
        layout.x = (x or 0) - offset
        layout.y = y
        ApplyItemViewerLayout(layoutName)
        itemViewer.WillsCDM_IsMoving = false
    end

    if LEM then
        LEM:AddFrame(itemViewer, OnPositionChanged, DB.GetItemViewerLayout("Default"), "Item Cooldowns")
        local selection = LEM.frameSelections and LEM.frameSelections[itemViewer] or nil
        if selection then
            selection:HookScript("OnDragStart", function()
                itemViewer.WillsCDM_IsMoving = true
            end)
            selection:HookScript("OnDragStop", function()
                itemViewer.WillsCDM_IsMoving = false
            end)
        end
        LEM:AddFrameSettings(itemViewer, {{
            name = "Icon Size",
            kind = LEM.SettingType.Slider,
            default = 1,
            minValue = 0.5,
            maxValue = 2.0,
            valueStep = 0.1,
            get = function(layoutName)
                local layout = DB.GetItemViewerLayout(layoutName)
                return layout.scale or 1
            end,
            set = function(layoutName, value)
                local layout = DB.GetItemViewerLayout(layoutName)
                layout.scale = value
                UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
            end,
            formatter = function(value)
                return FormatPercentage(value, true)
            end
        }, {
            name = "Icon Padding",
            kind = LEM.SettingType.Slider,
            default = 6,
            minValue = 0,
            maxValue = 14,
            valueStep = 1,
            get = function(layoutName)
                local layout = DB.GetItemViewerLayout(layoutName)
                return layout.padding or 6
            end,
            set = function(layoutName, value)
                local layout = DB.GetItemViewerLayout(layoutName)
                layout.padding = value
                UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
            end
        }, {
            name = "Growth Direction",
            kind = LEM.SettingType.Dropdown,
            default = "center",
            values = {{
                text = "Left",
                value = "left"
            }, {
                text = "Center",
                value = "center"
            }, {
                text = "Right",
                value = "right"
            }},
            get = function(layoutName)
                local layout = DB.GetItemViewerLayout(layoutName)
                return GetGrowthDirection(layout)
            end,
            set = function(layoutName, value)
                SetGrowthDirection(layoutName, value)
                UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
            end
        }})

        LEM:RegisterCallback("layout", function(layoutName)
            ApplyItemViewerLayout(layoutName)
            RefreshItemViewerFrames()
        end)

        LEM:RegisterCallback("enter", function()
            if itemViewer then
                itemViewer.WillsCDM_ForceShow = true
            end
            RefreshItemViewerFrames()
        end)

        LEM:RegisterCallback("exit", function()
            if itemViewer then
                itemViewer.WillsCDM_ForceShow = false
            end
            RefreshItemViewerFrames()
        end)
    end
end

local function InitializeItemsManager()
    InitializeItemsEditMode()
    ApplyItemViewerLayout("Default")
    RefreshItemViewerFrames()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function()
        RefreshItemViewerFrames()
    end)
end

ItemViewer.RefreshItemViewerFrames = RefreshItemViewerFrames
ItemViewer.InitializeItemsManager = InitializeItemsManager
