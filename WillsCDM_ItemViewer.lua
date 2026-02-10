local addonName, addon = ...
addon = addon or {}

local DB = addon.DB
local ItemsData = addon.ItemsData
local ItemVisuals = addon.ItemVisuals
local MasqueSupport = addon.MasqueSupport
local ItemViewer = addon.ItemViewer or {}
addon.ItemViewer = ItemViewer

local itemFrames = {}
local itemViewer = nil

local ItemViewerFrame = {}
ItemViewerFrame.__index = ItemViewerFrame

function ItemViewerFrame:New(parent)
    local templateName = _G["EssentialCooldownViewer"].itemTemplate

    local frame = CreateFrame("Frame", nil, parent, templateName)
    local obj = setmetatable({
        frame = frame
    }, ItemViewerFrame)
    obj:Initialize()
    return obj
end

function ItemViewerFrame:Initialize()
    local frame = self.frame
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

    if MasqueSupport and MasqueSupport.RegisterItemViewerButton then
        MasqueSupport:RegisterItemViewerButton(frame)
    end
end

function ItemViewerFrame:Show()
    self.frame:Show()
end

function ItemViewerFrame:Hide()
    self.frame:Hide()
end

function ItemViewerFrame:UpdateEntry(entry)
    local frame = self.frame
    if not entry then
        frame.WillsCDM_EntryKind = nil
        frame.WillsCDM_EntryID = nil
        frame:Hide()
        return
    end

    frame.WillsCDM_EntryKind = entry.kind
    frame.WillsCDM_EntryID = entry.id

    ItemVisuals:ApplyEntryIcon(frame, entry.kind, entry.id)
    ItemVisuals:UpdateEntryCooldown(frame, entry.kind, entry.id)

    frame:Show()
end

function ItemViewer:EnsureItemViewer()
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

function ItemViewer:SetGrowthDirection(layoutName, growth)
    self:EnsureItemViewer()
    local layout = DB.GetItemViewerLayout(layoutName)
    local totalWidth = itemViewer:GetWidth() or 0
    local oldGrowth = GetGrowthDirection(layout)
    local oldOffset = GetGrowthOffset(layout.point, oldGrowth, totalWidth)
    local newOffset = GetGrowthOffset(layout.point, growth, totalWidth)
    layout.x = (layout.x or 0) + (oldOffset - newOffset)
    layout.growth = growth
end

function ItemViewer:EnsureItemViewerFrames(count)
    self:EnsureItemViewer()

    for i = 1, count do
        if not itemFrames[i] then
            itemFrames[i] = ItemViewerFrame:New(itemViewer)
        end
        itemFrames[i]:Show()
    end

    for i = count + 1, #itemFrames do
        itemFrames[i]:Hide()
    end
end

function ItemViewer:UpdateItemsLayout(count)
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
    if not itemViewer.WillsCDM_IsMoving then
        self:ApplyItemViewerLayout(layoutName)
    end

    for i = 1, count do
        local frame = itemFrames[i].frame
        frame:SetSize(baseSize, baseSize)
        frame:SetScale(scale)
        local xOffset = (i - 1) * (visualSize + adjustedSpacing) * (1 / scale)
        frame:SetPoint("LEFT", itemViewer, "LEFT", xOffset, 0)
    end
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

function ItemViewer:ApplyItemViewerLayout(layoutName)
    self:EnsureItemViewer()
    local layout = DB.GetItemViewerLayout(layoutName)
    local growth = GetGrowthDirection(layout)
    local totalWidth = itemViewer:GetWidth() or 0
    local xOffset = GetGrowthOffset(layout.point, growth, totalWidth)
    itemViewer:ClearAllPoints()
    itemViewer:SetPoint(layout.point, UIParent, layout.point, (layout.x or 0) + xOffset, layout.y or 0)
    itemViewer.WillsCDM_LayoutName = layoutName
end

function ItemViewer:RefreshItemViewerFrames()
    self:EnsureItemViewer()

    local owned = ItemsData:ScanOwnedItems()
    ItemsData:EnsureTrackedItems(owned)
    local visibleEntries = ItemsData:GetVisibleEntries(owned)
    local count = #visibleEntries
    if itemViewer and itemViewer.WillsCDM_ForceShow and count == 0 then
        count = 1
    end

    self:EnsureItemViewerFrames(count)

    local db = DB.GetDB()
    for i, entry in ipairs(visibleEntries) do
        local frame = itemFrames[i].frame
        if frame.Cooldown then
            frame.Cooldown:SetSwipeColor(unpack(db.defaultCooldownSwipeColor))
            frame.Cooldown:SetDrawEdge(db.defaultAlwaysShowCooldownEdge == true)
        end
        itemFrames[i]:UpdateEntry(entry)
    end

    if count > #visibleEntries then
        for i = #visibleEntries + 1, count do
            itemFrames[i]:UpdateEntry(nil)
        end
    end

    if not InCombatLockdown() then
        self:UpdateItemsLayout(count)
    end

    itemViewer.WillsCDM_HasItems = #visibleEntries > 0
    itemViewer.WillsCDM_VisibleCount = count
    itemViewer:SetShown(ShouldShowItemViewer())
end

function ItemViewer:InitializeItemsEditMode()
    local LEM = LibStub and LibStub("LibEditMode", true)

    self:EnsureItemViewer()

    local function OnPositionChanged(frame, layoutName, point, x, y)
        local layout = DB.GetItemViewerLayout(layoutName)
        local totalWidth = itemViewer:GetWidth() or 0
        local growth = GetGrowthDirection(layout)
        local offset = GetGrowthOffset(point, growth, totalWidth)
        layout.point = point
        layout.x = (x or 0) - offset
        layout.y = y
        self:ApplyItemViewerLayout(layoutName)
        itemViewer.WillsCDM_IsMoving = false
    end

    if LEM then
        LEM:AddFrame(itemViewer, OnPositionChanged, DB.GetItemViewerLayout("Default"), "Misc Cooldowns")
        local selection = LEM.frameSelections and LEM.frameSelections[itemViewer] or nil
        if selection then
            selection:HookScript("OnDragStart", function()
                itemViewer.WillsCDM_IsMoving = true
            end)
            selection:HookScript("OnDragStop", function()
                itemViewer.WillsCDM_IsMoving = false
            end)
        end
        LEM:AddFrameSettings(itemViewer, { {
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
                self:UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
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
                self:UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
            end
        }, {
            name = "Growth Direction",
            kind = LEM.SettingType.Dropdown,
            default = "center",
            values = { {
                text = "Left",
                value = "left"
            }, {
                text = "Center",
                value = "center"
            }, {
                text = "Right",
                value = "right"
            } },
            get = function(layoutName)
                local layout = DB.GetItemViewerLayout(layoutName)
                return GetGrowthDirection(layout)
            end,
            set = function(layoutName, value)
                self:SetGrowthDirection(layoutName, value)
                self:UpdateItemsLayout(itemViewer and itemViewer.WillsCDM_VisibleCount or #itemFrames)
            end
        } })

        LEM:RegisterCallback("layout", function(layoutName)
            self:ApplyItemViewerLayout(layoutName)
            self:RefreshItemViewerFrames()
        end)

        LEM:RegisterCallback("enter", function()
            if itemViewer then
                itemViewer.WillsCDM_ForceShow = true
            end
            self:RefreshItemViewerFrames()
        end)

        LEM:RegisterCallback("exit", function()
            if itemViewer then
                itemViewer.WillsCDM_ForceShow = false
            end
            self:RefreshItemViewerFrames()
        end)
    end
end

function ItemViewer:Initialize()
    self:InitializeItemsEditMode()
    self:ApplyItemViewerLayout("Default")
    self:RefreshItemViewerFrames()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:SetScript("OnEvent", function()
        self:RefreshItemViewerFrames()
    end)
end
