local addonName, addon = ...
addon = addon or {}

local DB = addon.DB
local ItemsPanel = addon.ItemsPanel or {}
local ItemsData = addon.ItemsData
local ItemViewer = addon.ItemViewer
addon.ItemsPanel = ItemsPanel

local ITEM_STATE_SHOWN = ItemsData.ITEM_STATE_SHOWN
local ITEM_STATE_HIDDEN = ItemsData.ITEM_STATE_HIDDEN
local ITEM_STATE_REMOVED = ItemsData.ITEM_STATE_REMOVED

local itemContextMenu = nil
local reorderSourceItem = nil
local reorderTarget = nil
local reorderTargetItem = nil
local reorderOffset = 0
local reorderEatNextGlobalMouseUp = nil
local reorderMarker = nil
local reorderCursor = nil
local reorderCursorFollow = false

local function IsTabButton(child)
    if not child then
        return false
    end
    if child.WillsCDM_IsTabButton then
        return true
    end
    local name = child:GetName()
    return name and name:find("Tab") ~= nil
end

local function HideItemsPanel(settingsFrame)
    if settingsFrame.WillsCDM_ItemsPanel then
        settingsFrame.WillsCDM_ItemsPanel:Hide()
    end

    local hidden = settingsFrame.WillsCDM_HiddenChildren
    if hidden then
        for _, child in ipairs(hidden) do
            if child and not child:IsShown() then
                child:Show()
            end
        end
        settingsFrame.WillsCDM_HiddenChildren = nil
    end
end

local function EnsureItemContextMenu()
    if not itemContextMenu then
        itemContextMenu = CreateFrame("Frame", "WillsCDM_ItemContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return itemContextMenu
end

local function GetItemsPanelFrame()
    local settings = _G["CooldownViewerSettings"]
    return settings and settings.WillsCDM_ItemsPanel or nil
end

local function EnsureReorderMarker()
    if reorderMarker then
        return reorderMarker
    end

    local itemsPanel = GetItemsPanelFrame()
    if not itemsPanel then
        return nil
    end

    local marker = nil
    if _G["CooldownViewerSettingsReorderMarkerTemplate"] then
        local ok, created = pcall(CreateFrame, "Frame", nil, itemsPanel, "CooldownViewerSettingsReorderMarkerTemplate")
        if ok then
            marker = created
        end
    end

    if not marker or not marker.Texture then
        marker = CreateFrame("Frame", nil, itemsPanel)
        marker:SetSize(12, 12)
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
    end

    if not marker.SetHorizontal then
        function marker:SetHorizontal()
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-vertical", true)
            elseif self.Texture then
                self.Texture:SetColorTexture(1, 1, 1, 1)
            end
        end
    end

    marker:Hide()
    local spacing = itemsPanel.WillsCDM_ItemSpacing or 8
    local itemSize = itemsPanel.WillsCDM_ItemSize or 38
    marker:SetSize(spacing, itemSize)
    reorderMarker = marker
    return reorderMarker
end

local function EnsureReorderCursor()
    if reorderCursor then
        return reorderCursor
    end

    local frame = CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")
    frame:Hide()
    reorderCursor = frame
    return reorderCursor
end

local function PickupItemCursor(itemButton)
    local cursor = EnsureReorderCursor()
    if not cursor then
        return
    end

    if cursor.SetToCursor then
        cursor:SetToCursor(itemButton)
        reorderCursorFollow = false
    else
        if cursor.Icon and itemButton and itemButton.Icon then
            cursor.Icon:SetTexture(itemButton.Icon:GetTexture())
        end
        cursor:Show()
        reorderCursorFollow = true
    end
end

local function ClearItemCursor()
    if reorderCursor then
        if reorderCursor.StopMovingOrSizing then
            reorderCursor:StopMovingOrSizing()
        end
        reorderCursor:Hide()
    end
    reorderCursorFollow = false
end

local function IsReordering()
    return reorderSourceItem ~= nil
end

local function SetReorderTarget(target)
    if IsReordering() then
        reorderTarget = target
    end
end

local function UpdateReorderMarker()
    local marker = EnsureReorderMarker()
    if not marker then
        return
    end

    local itemsPanel = GetItemsPanelFrame()
    if itemsPanel then
        local spacing = itemsPanel.WillsCDM_ItemSpacing or 8
        local itemSize = itemsPanel.WillsCDM_ItemSize or 38
        marker:SetSize(spacing, itemSize)
    end

    local target = reorderTarget
    marker:SetShown(target ~= nil)
    if not target then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = GetAppropriateTopLevelParent():GetScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local targetItem = target.GetBestCooldownItemTarget and target:GetBestCooldownItemTarget(cursorX, cursorY) or nil
    reorderTargetItem = targetItem
    if targetItem and targetItem.UpdateReorderMarkerPosition then
        marker:ClearAllPoints()
        local isMarkerAfterTarget = targetItem:UpdateReorderMarkerPosition(marker, cursorX, cursorY)
        reorderOffset = isMarkerAfterTarget and 1 or 0
    end

    if reorderCursorFollow and reorderCursor then
        reorderCursor:ClearAllPoints()
        reorderCursor:SetPoint("TOPLEFT", GetAppropriateTopLevelParent(), "BOTTOMLEFT", cursorX, cursorY)
    end
end

local function CancelOrderChange()
    if reorderSourceItem and reorderSourceItem.SetReorderLocked then
        reorderSourceItem:SetReorderLocked(false)
    end
    if reorderMarker then
        reorderMarker:Hide()
    end
    reorderSourceItem = nil
    reorderTarget = nil
    reorderTargetItem = nil
    reorderOffset = 0
    reorderEatNextGlobalMouseUp = nil
    ClearItemCursor()

    local itemsPanel = GetItemsPanelFrame()
    if itemsPanel then
        itemsPanel:SetScript("OnUpdate", nil)
        itemsPanel:UnregisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function EndOrderChange()
    local sourceItem = reorderSourceItem
    local targetItem = reorderTargetItem

    if sourceItem and targetItem and sourceItem ~= targetItem then
        local targetState = targetItem.categoryState or sourceItem.categoryState
        if targetItem.WillsCDM_Empty then
            if sourceItem.categoryState ~= targetState then
                DB.SetItemState(sourceItem.itemID, targetState)
            end
            ItemsData.InsertItemAt(targetState, sourceItem.itemID, nil, false)
        else
            if sourceItem.categoryState ~= targetState then
                DB.SetItemState(sourceItem.itemID, targetState)
            end
            ItemsData.InsertItemAt(targetState, sourceItem.itemID, targetItem.itemID, reorderOffset == 0)
        end
    end

    CancelOrderChange()
    RefreshItemsPanel()
    ItemViewer.RefreshItemViewerFrames()
end

local function BeginOrderChange(itemButton, eatNextGlobalMouseUp)
    if IsReordering() or not itemButton or itemButton.WillsCDM_Empty then
        return
    end

    reorderSourceItem = itemButton
    reorderTarget = itemButton
    reorderTargetItem = itemButton
    reorderOffset = 0
    reorderEatNextGlobalMouseUp = eatNextGlobalMouseUp

    if itemButton.SetReorderLocked then
        itemButton:SetReorderLocked(true)
    end

    PickupItemCursor(itemButton)
    EnsureReorderMarker()

    local itemsPanel = GetItemsPanelFrame()
    if itemsPanel then
        itemsPanel:SetScript("OnUpdate", function()
            UpdateReorderMarker()
        end)
        itemsPanel:SetScript("OnEvent", function(_self, event, ...)
            if event == "GLOBAL_MOUSE_UP" then
                local button = ...
                if reorderEatNextGlobalMouseUp == button then
                    reorderEatNextGlobalMouseUp = nil
                    return
                end
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_DROP_OBJECT then
                    PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
                end
                if button == "LeftButton" then
                    EndOrderChange()
                elseif button == "RightButton" then
                    CancelOrderChange()
                end
            end
        end)
        itemsPanel:RegisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function ShowItemContextMenu(button)
    local itemID = button.itemID
    if not itemID then
        return
    end
    if not EasyMenu then
        return
    end

    local itemName = ItemsData.GetItemNameByID(itemID) or ("Item " .. itemID)
    local menuFrame = EnsureItemContextMenu()

    local function SetState(state)
        DB.SetItemState(itemID, state)
        RefreshItemsPanel()
        ItemViewer.RefreshItemViewerFrames()
    end

    local menu = {{
        text = itemName,
        isTitle = true,
        notCheckable = true
    }, {
        text = "Show in Item Cooldowns",
        notCheckable = true,
        func = function()
            SetState(ITEM_STATE_SHOWN)
        end
    }, {
        text = "Move to Not Displayed",
        notCheckable = true,
        func = function()
            SetState(ITEM_STATE_HIDDEN)
        end
    }, {
        text = "Stop Tracking",
        notCheckable = true,
        func = function()
            SetState(ITEM_STATE_REMOVED)
        end
    }}

    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

local function InitializeItemButton(button)
    if button.WillsCDM_Initialized then
        return
    end

    if button.Cooldown then
        CooldownFrame_Clear(button.Cooldown)
        button.Cooldown:SetDrawSwipe(false)
        button.Cooldown:SetDrawEdge(false)
    end

    if button.OutOfRange then
        button.OutOfRange:Hide()
    end

    button:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowItemContextMenu(self)
        elseif mouseButton == "LeftButton" and not self.WillsCDM_Empty then
            if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
                PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
            end
            BeginOrderChange(self, mouseButton)
        end
    end)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if self.WillsCDM_Empty then
            return
        end
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
            PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
        end
        BeginOrderChange(self)
    end)
    button:SetScript("OnEnter", function(self)
        SetReorderTarget(self)
        if self.WillsCDM_Empty then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip_SetTitle then
                GameTooltip_SetTitle(GameTooltip, "Empty Slot")
            else
                GameTooltip:SetText("Empty Slot")
            end
            GameTooltip:Show()
        elseif self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    function button:SetReorderLocked(locked)
        self.WillsCDM_ReorderLocked = locked and true or false
        if self.Icon then
            self.Icon:SetDesaturated(self.WillsCDM_ReorderLocked)
        end
    end

    function button:IsReorderLocked()
        return self.WillsCDM_ReorderLocked == true
    end

    function button:IsEmptyCategory()
        return self.WillsCDM_Empty == true
    end

    function button:GetBestCooldownItemTarget(_cursorX, _cursorY)
        return self
    end

    function button:UpdateReorderMarkerPosition(marker, cursorX, _cursorY)
        if marker and marker.SetHorizontal then
            marker:SetHorizontal()
        end
        local centerX = self:GetCenter()
        if centerX and cursorX < centerX then
            marker:SetPoint("CENTER", self, "LEFT", -4, 0)
            return false
        else
            marker:SetPoint("CENTER", self, "RIGHT", 4, 0)
            return true
        end
    end

    button:HookScript("OnShow", function(self)
        if not self.Icon then
            return
        end
        if self.WillsCDM_Empty then
            self.Icon:SetTexture(nil)
            self.Icon:SetAtlas("cdm-empty", true)
        elseif self.itemID then
            local icon = C_Item.GetItemIconByID(self.itemID)
            if not icon and GetItemIcon then
                icon = GetItemIcon(self.itemID)
            end
            if icon then
                self.Icon:SetTexture(icon)
            else
                self.Icon:SetTexture(134400)
            end
        end
    end)

    button.WillsCDM_Initialized = true
end

local function AcquireItemButton(category)
    local button = category.itemPool:Acquire()
    InitializeItemButton(button)
    button:Show()
    return button
end

local function ResetCategoryButtons(category)
    category.itemPool:ReleaseAll()

    local container = category.Container
    if container then
        for _, child in ipairs({container:GetChildren()}) do
            if child.layoutIndex ~= nil then
                child.layoutIndex = nil
            end
        end
    end
end

local function LayoutCategory(category, itemIDs, owned)
    ResetCategoryButtons(category)

    local container = category.Container or category.Content
    local headerHeight = category.Header:GetHeight()
    local isCollapsed = category.IsCollapsed and category:IsCollapsed() or category.Collapsed
    if isCollapsed then
        if category.SetCollapsed then
            category:SetCollapsed(true)
        elseif container then
            container:Hide()
        end
        category:SetHeight(headerHeight)
        return
    end

    if category.SetCollapsed then
        category:SetCollapsed(false)
    elseif container then
        container:Show()
    end

    local size = 38
    local spacing = 8

    local itemsPanel = GetItemsPanelFrame()
    if itemsPanel then
        itemsPanel.WillsCDM_ItemSpacing = spacing
        itemsPanel.WillsCDM_ItemSize = size
    end

    if #itemIDs == 0 then
        local emptyButton = AcquireItemButton(category)
        emptyButton.itemID = nil
        emptyButton.WillsCDM_Empty = true
        emptyButton.categoryState = category.state
        emptyButton.layoutIndex = 1
        emptyButton:ClearAllPoints()
        emptyButton:SetSize(size, size)
        if emptyButton.Icon then
            emptyButton.Icon:SetTexture(nil)
            emptyButton.Icon:SetAtlas("cdm-empty", true)
            emptyButton.Icon:SetDesaturated(false)
        end
        if emptyButton.Cooldown then
            CooldownFrame_Clear(emptyButton.Cooldown)
        end
    else
        for index, itemID in ipairs(itemIDs) do
            local button = AcquireItemButton(category)
            button.itemID = itemID
            button.WillsCDM_Empty = false
            button.categoryState = category.state
            button.layoutIndex = index
            button:ClearAllPoints()
            button:SetSize(size, size)

            if button.Icon then
                local icon = C_Item.GetItemIconByID(itemID)
                if not icon and GetItemIcon then
                    icon = GetItemIcon(itemID)
                end
                if icon then
                    button.Icon:SetTexture(icon)
                else
                    button.Icon:SetTexture(134400)
                end
                button.Icon:SetDesaturated(not owned[itemID])
            end

            if button.Cooldown then
                CooldownFrame_Clear(button.Cooldown)
            end
        end
    end

    if container and container.Layout then
        container.childXPadding = spacing
        container.childYPadding = spacing
        container.isHorizontal = true
        container.stride = 7
        container.layoutFramesGoingRight = true
        container.layoutFramesGoingUp = false
        container.alwaysUpdateLayout = true
        container:Layout()
    end

    local contentHeight = container and container:GetHeight() or 0
    local totalHeight = nil
    if category.Header and container then
        local headerTop = category.Header:GetTop()
        local containerBottom = container:GetBottom()
        if headerTop and containerBottom then
            totalHeight = headerTop - containerBottom
        end
    end
    category:SetHeight(totalHeight or (headerHeight + 6 + contentHeight))
end

local function CreateItemCategory(parent, title, state)
    local categoryDisplay = CreateFrame("Frame", nil, parent, "CooldownViewerSettingsCategoryTemplate")
    categoryDisplay.state = state
    categoryDisplay.Collapsed = false
    categoryDisplay.Header:SetHeaderText(title)

    function categoryDisplay:SetCollapsed(collapsed)
        self.Collapsed = collapsed and true or false
        if self.Header and self.Header.UpdateCollapsedState then
            self.Header:UpdateCollapsedState(self.Collapsed)
        end
        if self.Header then
            local title = self.Header.TitleText or self.Header.Title
            if title then
                if not self.Header.WillsCDM_TitlePoints then
                    self.Header.WillsCDM_TitlePoints = {}
                    for i = 1, title:GetNumPoints() do
                        self.Header.WillsCDM_TitlePoints[i] = {title:GetPoint(i)}
                    end
                end
                if self.Header.WillsCDM_TitlePoints and #self.Header.WillsCDM_TitlePoints > 0 then
                    title:ClearAllPoints()
                    for _, point in ipairs(self.Header.WillsCDM_TitlePoints) do
                        title:SetPoint(unpack(point))
                    end
                end
            end
        end
        if self.Container then
            self.Container:SetShown(not self.Collapsed)
            if self.Container.Layout then
                self.Container:Layout()
            end
        end
    end

    function categoryDisplay:IsCollapsed()
        return self.Collapsed == true
    end

    function categoryDisplay:ToggleCollapsed()
        self:SetCollapsed(not self:IsCollapsed())
        RefreshItemsPanel()
    end

    if categoryDisplay.Header then
        if categoryDisplay.Header.CollapseButton then
            categoryDisplay.Header.CollapseButton:Hide()
            categoryDisplay.Header.CollapseButton:Disable()
        end
        if categoryDisplay.Header.Toggle then
            categoryDisplay.Header.Toggle:Hide()
            categoryDisplay.Header.Toggle:Disable()
        end
    end

    if not categoryDisplay.Container then
        categoryDisplay.Container = CreateFrame("Frame", nil, categoryDisplay)
        categoryDisplay.Container:SetPoint("TOPLEFT", categoryDisplay, "TOPLEFT", 0, 0)
        categoryDisplay.Container:SetPoint("TOPRIGHT", categoryDisplay, "TOPRIGHT", 0, 0)
    end

    categoryDisplay:SetScript("OnEnter", function(self)
        SetReorderTarget(self)
    end)
    if categoryDisplay.Container then
        categoryDisplay.Container:SetScript("OnEnter", function()
            SetReorderTarget(categoryDisplay)
        end)
    end

    categoryDisplay.itemPool = CreateFramePool("Frame", categoryDisplay.Container, "CooldownViewerSettingsItemTemplate",
        function(_, frame)
            frame:Hide()
            frame.layoutIndex = nil
            frame.itemID = nil
            frame.WillsCDM_Empty = nil
            if frame.Icon then
                frame.Icon:SetTexture(nil)
            end
        end)

    function categoryDisplay:GetNearestItemToCursorWeighted(cursorX, cursorY)
        local nearestItem = nil
        local nearestVertical = math.huge
        local nearestHorizontal = math.huge

        for item in self.itemPool:EnumerateActive() do
            local left, right, bottom, top = item:GetLeft(), item:GetRight(), item:GetBottom(), item:GetTop()
            if left and right and bottom and top then
                local centerX = (left + right) / 2
                local centerY = (bottom + top) / 2
                local horizontalDistance = math.abs(centerX - cursorX)
                local verticalDistance = math.abs(centerY - cursorY)
                if cursorY > bottom and cursorY < top then
                    verticalDistance = 0
                end
                if verticalDistance < nearestVertical or
                    (verticalDistance == nearestVertical and horizontalDistance < nearestHorizontal) then
                    nearestItem = item
                    nearestVertical = verticalDistance
                    nearestHorizontal = horizontalDistance
                end
            end
        end

        return nearestItem
    end

    function categoryDisplay:GetBestCooldownItemTarget(cursorX, cursorY)
        return self:GetNearestItemToCursorWeighted(cursorX, cursorY)
    end

    if categoryDisplay.Header and categoryDisplay.Header.SetClickHandler then
        categoryDisplay.Header:SetClickHandler(function(_, button)
            if button == "LeftButton" then
                categoryDisplay:ToggleCollapsed()
            end
        end)
    elseif categoryDisplay.Header then
        categoryDisplay.Header:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                categoryDisplay:ToggleCollapsed()
            end
        end)
    end

    categoryDisplay:SetCollapsed(false)

    return categoryDisplay
end

RefreshItemsPanel = function(settingsFrame)
    local owned = ItemsData.ScanOwnedItems()
    ItemsData.EnsureTrackedItems(owned)

    local frame = settingsFrame or _G["CooldownViewerSettings"]
    if not frame then
        return
    end

    local itemsPanel = frame.WillsCDM_ItemsPanel
    if not itemsPanel then
        return
    end

    if itemsPanel.SetPortraitToSpecIcon then
        itemsPanel:SetPortraitToSpecIcon()
    end

    local enable = itemsPanel.WillsCDM_EnableCheckbox
    if enable then
        enable:SetChecked(DB.GetItemViewerEnabled())
    end

    local shownIDs = ItemsData.GetItemIDsByState(ITEM_STATE_SHOWN)
    local hiddenIDs = ItemsData.GetItemIDsByState(ITEM_STATE_HIDDEN)

    local categories = itemsPanel.WillsCDM_Categories
    if not categories then
        return
    end

    LayoutCategory(categories[1], shownIDs, owned)
    LayoutCategory(categories[2], hiddenIDs, owned)

    local scrollChild = itemsPanel.WillsCDM_ScrollChild
    if scrollChild then
        local yOffset = 0
        local previousCategory = nil
        for _, category in ipairs(categories) do
            category:ClearAllPoints()
            if previousCategory then
                category:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT", 0, -18)
            else
                category:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
            end
            yOffset = yOffset + category:GetHeight() + (previousCategory and 18 or 0)
            previousCategory = category
        end
        scrollChild:SetHeight(math.max(1, yOffset))

        local scrollFrame = itemsPanel.WillsCDM_ScrollFrame
        if scrollFrame then
            local needsScrollPadding = previousCategory and scrollFrame:GetVerticalScrollRange() > 0
            if needsScrollPadding then
                if not itemsPanel.WillsCDM_ScrollPadding then
                    itemsPanel.WillsCDM_ScrollPadding = CreateFrame("Frame", nil, scrollChild)
                    itemsPanel.WillsCDM_ScrollPadding:SetHeight(18)
                end
                itemsPanel.WillsCDM_ScrollPadding:ClearAllPoints()
                itemsPanel.WillsCDM_ScrollPadding:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT")
                itemsPanel.WillsCDM_ScrollPadding:SetPoint("TOPRIGHT", previousCategory, "BOTTOMRIGHT")
                itemsPanel.WillsCDM_ScrollPadding:Show()
            elseif itemsPanel.WillsCDM_ScrollPadding then
                itemsPanel.WillsCDM_ScrollPadding:Hide()
            end
        end
    end
end

local function ShowItemsPanel(settingsFrame)
    local itemsPanel = settingsFrame.WillsCDM_ItemsPanel
    if not itemsPanel then
        return
    end

    local hidden = {}
    for _, child in ipairs({settingsFrame:GetChildren()}) do
        if child:IsShown() and child ~= itemsPanel and not IsTabButton(child) then
            child:Hide()
            table.insert(hidden, child)
        end
    end

    settingsFrame.WillsCDM_HiddenChildren = hidden
    RefreshItemsPanel(settingsFrame)
    itemsPanel:Show()
end

local function EnsureItemsSettingsTab(settingsFrame)
    if settingsFrame.WillsCDM_ItemsPanel then
        return
    end

    local itemsPanel = CreateFrame("Frame", nil, settingsFrame, "ButtonFrameTemplate")
    itemsPanel:SetAllPoints(settingsFrame)
    itemsPanel:Hide()
    itemsPanel.Inset.Bg:SetAtlas("character-panel-background", true)
    itemsPanel.Inset.Bg:SetHorizTile(false)
    itemsPanel.Inset.Bg:SetVertTile(false)
    itemsPanel.TitleContainer.TitleText:SetText("Cooldown Settings")

    if itemsPanel.CloseButton then
        itemsPanel.CloseButton:SetScript("OnClick", function()
            HideUIPanel(settingsFrame)
        end)
    end

    settingsFrame.WillsCDM_ItemsPanel = itemsPanel

    local scrollFrame = CreateFrame("ScrollFrame", "$parent.CooldownScroll", itemsPanel, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 17, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 29)

    local scrollChild = CreateFrame("Frame", "$parent.Content", scrollFrame)
    scrollChild:SetSize(300, 1)
    scrollChild:SetPoint("TOPLEFT", 0, 0)
    scrollChild:SetPoint("TOPRIGHT", 0, 0)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
    scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)

    scrollFrame:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(self:GetWidth())
        RefreshItemsPanel(settingsFrame)
    end)

    itemsPanel:HookScript("OnShow", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
        RefreshItemsPanel(settingsFrame)
    end)

    local shownCategory = CreateItemCategory(scrollChild, "Item Cooldowns", ITEM_STATE_SHOWN)
    local hiddenCategory = CreateItemCategory(scrollChild, "Not Displayed", ITEM_STATE_HIDDEN)

    itemsPanel.WillsCDM_Categories = {shownCategory, hiddenCategory}
    itemsPanel.WillsCDM_ScrollChild = scrollChild
    itemsPanel.WillsCDM_ScrollFrame = scrollFrame
    local spellsTab = settingsFrame.SpellsTab
    local aurasTab = settingsFrame.AurasTab

    spellsTab.WillsCDM_IsTabButton = true
    aurasTab.WillsCDM_IsTabButton = true

    local itemsTab = CreateFrame("Button", "$parent.ItemsTab", settingsFrame, "CooldownViewerSettingsTabTemplate")
    itemsTab.WillsCDM_IsTabButton = true
    itemsTab.tooltipText = "Items"
    itemsTab.displayMode = "items"
    itemsTab.activeAtlas = "minimap-genericevent-hornicon-small"
    itemsTab.inactiveAtlas = "minimap-genericevent-hornicon-small"
    itemsTab:SetChecked(false)
    if itemsTab.Text then
        itemsTab.Text:SetText("Items")
    else
        itemsTab:SetText("Items")
    end
    itemsTab:SetPoint("TOP", aurasTab, "BOTTOM", 0, -3)

    itemsTab:SetScript("OnClick", function(self)
        if settingsFrame.WillsCDM_ItemsPanel:IsShown() then
            return
        end

        spellsTab:SetChecked(false)
        aurasTab:SetChecked(false)
        self:SetChecked(true)

        ShowItemsPanel(settingsFrame)
    end)

    if settingsFrame.SetDisplayMode then
        hooksecurefunc(settingsFrame, "SetDisplayMode", function(self, mode)
            spellsTab:SetChecked(mode == "spells")
            aurasTab:SetChecked(mode == "auras")
            itemsTab:SetChecked(mode == "items")
            HideItemsPanel(self)
        end)
    end

    itemsTab:Show()
end

ItemsPanel.RefreshItemViewerFrames = ItemViewer.RefreshItemViewerFrames
ItemsPanel.InitializeItemsManager = ItemViewer.InitializeItemsManager
ItemsPanel.EnsureItemsSettingsTab = EnsureItemsSettingsTab
ItemsPanel.RefreshItemsPanel = RefreshItemsPanel
ItemsPanel.HideItemsPanel = HideItemsPanel
