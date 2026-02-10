local addonName, addon = ...
addon = addon or {}

local DB = addon.DB
local MiscPanel = addon.MiscPanel or {}
local ItemsData = addon.ItemsData
local ItemVisuals = addon.ItemVisuals
local ItemViewer = addon.ItemViewer
addon.MiscPanel = MiscPanel

local ITEM_STATE_SHOWN = ItemsData.ITEM_STATE_SHOWN
local ITEM_STATE_HIDDEN = ItemsData.ITEM_STATE_HIDDEN
local ITEM_STATE_REMOVED = ItemsData.ITEM_STATE_REMOVED

local reorderSourceItem = nil
local reorderTarget = nil
local reorderTargetItem = nil
local reorderOffset = 0
local reorderEatNextGlobalMouseUp = nil
local reorderMarker = nil
local reorderCursor = nil
local reorderCursorFollow = false

function MiscPanel:HideMiscPanel(settingsFrame)
    settingsFrame.WillsCDM_ScrollFrame:Hide()
    do return end
    if settingsFrame.WillsCDM_MiscPanel then
        settingsFrame.WillsCDM_MiscPanel:Hide()
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

local function GetMiscPanelFrame()
    return _G["CooldownViewerSettings"].WillsCDM_ScrollFrame
end

local function GetEntryKindAndID(button)
    if not button then
        return nil, nil
    end
    return button.WillsCDM_EntryKind, button.WillsCDM_EntryID
end

local function SetButtonEntry(button, kind, id)
    if not button then
        return
    end
    button.WillsCDM_EntryKind = kind
    button.WillsCDM_EntryID = id
    if kind == "item" then
        button.itemID = id
        button.spellID = nil
    else
        button.itemID = nil
        button.spellID = id
    end
end

local function BuildEntry(kind, id)
    if not kind or not id then
        return nil
    end
    return {
        kind = kind,
        id = id
    }
end

local function SetIconFromEntry(target, kind, id)
    if not target or not target.Icon then
        return
    end
    if ItemVisuals.GetEntryIcon then
        target.Icon:SetTexture(ItemVisuals:GetEntryIcon(kind, id))
        return
    end
    local icon = nil
    if kind == "spell" then
        icon = C_Spell.GetSpellTexture(id)
    else
        icon = C_Item.GetItemIconByID(id)
    end
    target.Icon:SetTexture(icon or 134400)
end

local function IsEntryOwned(owned, kind, id)
    if not owned then
        return false
    end
    if kind == "spell" then
        return owned.spells[id]
    end
    return owned.items[id]
end

local function EnsureReorderMarker()
    if reorderMarker then
        return reorderMarker
    end

    local miscPanel = GetMiscPanelFrame()
    if not miscPanel then
        return nil
    end

    local marker = nil
    if _G["CooldownViewerSettingsReorderMarkerTemplate"] then
        local ok, created = pcall(CreateFrame, "Frame", nil, miscPanel, "CooldownViewerSettingsReorderMarkerTemplate")
        if ok then
            marker = created
        end
    end

    if not marker or not marker.Texture then
        marker = CreateFrame("Frame", nil, miscPanel)
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
    local spacing = miscPanel.WillsCDM_ItemSpacing or 8
    local itemSize = miscPanel.WillsCDM_ItemSize or 38
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

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        local spacing = miscPanel.WillsCDM_ItemSpacing or 8
        local itemSize = miscPanel.WillsCDM_ItemSize or 38
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

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        miscPanel:SetScript("OnUpdate", nil)
        miscPanel:UnregisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function EndOrderChange()
    local sourceItem = reorderSourceItem
    local targetItem = reorderTargetItem

    if sourceItem and targetItem and sourceItem ~= targetItem then
        local targetState = targetItem.categoryState or sourceItem.categoryState
        local sourceKind, sourceID = GetEntryKindAndID(sourceItem)
        if sourceKind and sourceID then
            if targetItem.WillsCDM_Empty then
                if sourceItem.categoryState ~= targetState then
                    ItemsData:SetEntryState(sourceKind, sourceID, targetState)
                end
                ItemsData:InsertItemAt(targetState, BuildEntry(sourceKind, sourceID), nil, false)
            else
                local targetKind, targetID = GetEntryKindAndID(targetItem)
                if targetKind and targetID then
                    if sourceItem.categoryState ~= targetState then
                        ItemsData:SetEntryState(sourceKind, sourceID, targetState)
                    end
                    ItemsData:InsertItemAt(targetState, BuildEntry(sourceKind, sourceID),
                        BuildEntry(targetKind, targetID), reorderOffset == 0)
                end
            end
        end
    end

    CancelOrderChange()
    MiscPanel:RefreshMiscPanel()
    ItemViewer:RefreshItemViewerFrames()
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

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        miscPanel:SetScript("OnUpdate", function()
            UpdateReorderMarker()
        end)
        miscPanel:SetScript("OnEvent", function(_self, event, ...)
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
        miscPanel:RegisterEvent("GLOBAL_MOUSE_UP")
    end
end

local function ShowItemContextMenu(button)
    if not button then
        return
    end
    local kind, id = GetEntryKindAndID(button)
    if not kind or not id then
        return
    end
    local hiddenLabel = "Move to Not Displayed"

    local function Generator(owner, rootDescription)
        rootDescription:CreateButton("Show in Misc Cooldowns", function()
            ItemsData:SetEntryState(kind, id, ITEM_STATE_SHOWN)
            MiscPanel:RefreshMiscPanel()
            ItemViewer:RefreshItemViewerFrames()
        end)
        rootDescription:CreateButton(hiddenLabel, function()
            ItemsData:SetEntryState(kind, id, ITEM_STATE_HIDDEN)
            MiscPanel:RefreshMiscPanel()
            ItemViewer:RefreshItemViewerFrames()
        end)
        rootDescription:CreateButton("Stop Tracking", function()
            ItemsData:SetEntryState(kind, id, ITEM_STATE_REMOVED)
            MiscPanel:RefreshMiscPanel()
            ItemViewer:RefreshItemViewerFrames()
        end)
    end

    MenuUtil.CreateContextMenu(button, Generator)
end

local function InitializeItemButton(button)
    if button.WillsCDM_Initialized then
        return
    end

    if button.Cooldown then
        if ItemVisuals then
            ItemVisuals:ClearCooldown(button, nil)
        else
            CooldownFrame_Clear(button.Cooldown)
            button.Cooldown:SetDrawSwipe(false)
        end
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
            GameTooltip:SetText("Empty Slot")
            GameTooltip:Show()
        else
            local kind, id = GetEntryKindAndID(self)
            if kind and id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if kind == "spell" then
                    if GameTooltip.SetSpellByID then
                        GameTooltip:SetSpellByID(id)
                    else
                        local name = ItemsData:GetEntryName(kind, id)
                        if name then
                            GameTooltip:SetText(name)
                        end
                    end
                else
                    GameTooltip:SetItemByID(id)
                end
                GameTooltip:Show()
            end
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
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
            if ItemVisuals then
                ItemVisuals:SetEmptySlot(self)
            else
                self.Icon:SetTexture(nil)
                self.Icon:SetAtlas("cdm-empty", true)
            end
        else
            local kind, id = GetEntryKindAndID(self)
            if kind and id then
                SetIconFromEntry(self, kind, id)
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
end

function MiscPanel:LayoutCategory(category, entries, owned)
    ResetCategoryButtons(category)

    local size = 38
    local spacing = 8

    local miscPanel = GetMiscPanelFrame()
    if miscPanel then
        miscPanel.WillsCDM_ItemSpacing = spacing
        miscPanel.WillsCDM_ItemSize = size
    end

    if #entries == 0 then
        local emptyButton = AcquireItemButton(category)
        SetButtonEntry(emptyButton, nil, nil)
        emptyButton.WillsCDM_Empty = true
        emptyButton.categoryState = category.state
        emptyButton.layoutIndex = 1
        emptyButton:ClearAllPoints()
        emptyButton:SetSize(size, size)
        ItemVisuals:SetEmptySlot(emptyButton)
    else
        for index, entry in ipairs(entries) do
            local button = AcquireItemButton(category)
            SetButtonEntry(button, entry.kind, entry.id)
            button.WillsCDM_Empty = false
            button.categoryState = category.state
            button.layoutIndex = index
            button:ClearAllPoints()
            button:SetSize(size, size)

            SetIconFromEntry(button, entry.kind, entry.id)
            if button.Icon then
                button.Icon:SetDesaturated(not IsEntryOwned(owned, entry.kind, entry.id))
            end

            if button.Cooldown then
                CooldownFrame_Clear(button.Cooldown)
            end
        end
    end

    category.Container:Layout()
end

function MiscPanel:CreateItemCategory(parent, title, state)
    local categoryDisplay = CreateFrame("Frame", nil, parent, "CooldownViewerSettingsCategoryTemplate")
    categoryDisplay.state = state
    categoryDisplay.Header:SetHeaderText(title)

    function categoryDisplay:SetCollapsed(collapsed)
        self.Collapsed = collapsed and true or false
        self.Header:UpdateCollapsedState(self.Collapsed)
        self.Container:SetShown(not self.Collapsed)

        local frame = _G["CooldownViewerSettings"]
        if frame.WillsCDM_ScrollFrame then
            frame.WillsCDM_ScrollFrame:Hide()
            frame.WillsCDM_ScrollFrame:Show()
        end
    end

    function categoryDisplay:IsCollapsed()
        return self.Collapsed == true
    end

    function categoryDisplay:ToggleCollapsed()
        self:SetCollapsed(not self:IsCollapsed())
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
    categoryDisplay.Container:SetScript("OnEnter", function()
        SetReorderTarget(categoryDisplay)
    end)

    categoryDisplay.itemPool = CreateFramePool("Frame", categoryDisplay.Container, "CooldownViewerSettingsItemTemplate",
        function(_, frame)
            frame:Hide()
            frame.layoutIndex = nil
            frame.itemID = nil
            frame.spellID = nil
            frame.WillsCDM_EntryKind = nil
            frame.WillsCDM_EntryID = nil
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

function MiscPanel:RefreshMiscPanel(settingsFrame)
    local frame = settingsFrame or _G["CooldownViewerSettings"]
    if not frame or not frame.WillsCDM_ScrollFrame or not frame.WillsCDM_ScrollFrame:IsShown() then
        return
    end

    local owned = ItemsData:ScanOwnedItems()
    ItemsData:EnsureTrackedItems(owned)

    local showUnlearned = C_CVar.GetCVarBool("cooldownViewerShowUnlearned")
    local shownEntries = ItemsData:GetEntriesByState(ITEM_STATE_SHOWN)
    local hiddenEntries = ItemsData:GetEntriesByState(ITEM_STATE_HIDDEN)

    if frame.WillsCDM_Categories == nil then
        return
    end

    local shownCategory = frame.WillsCDM_Categories[1]
    local hiddenCategory = frame.WillsCDM_Categories[2]

    if not showUnlearned then
        -- Filter out items the player does not own (same logic as icon desaturation)
        local filteredShown = {}
        for _, entry in ipairs(shownEntries) do
            if IsEntryOwned(owned, entry.kind, entry.id) then
                table.insert(filteredShown, entry)
            end
        end
        local filteredHidden = {}
        for _, entry in ipairs(hiddenEntries) do
            if IsEntryOwned(owned, entry.kind, entry.id) then
                table.insert(filteredHidden, entry)
            end
        end
        shownEntries = filteredShown
        hiddenEntries = filteredHidden
    end

    -- Filter by search term
    local searchTerm = frame.filterText
    if searchTerm and searchTerm ~= "" then
        local function matchesSearch(entry)
            local name = ItemsData:GetEntryName(entry.kind, entry.id)
            return name and name:lower():find(searchTerm:lower(), 1, true)
        end
        local filteredShown = {}
        for _, entry in ipairs(shownEntries) do
            if matchesSearch(entry) then
                table.insert(filteredShown, entry)
            end
        end
        local filteredHidden = {}
        for _, entry in ipairs(hiddenEntries) do
            if matchesSearch(entry) then
                table.insert(filteredHidden, entry)
            end
        end
        shownEntries = filteredShown
        hiddenEntries = filteredHidden
    end

    shownCategory:SetPoint("TOPLEFT", frame.WillsCDM_ScrollChild, "TOPLEFT", 0, 0)
    hiddenCategory:SetPoint("TOPLEFT", shownCategory, "BOTTOMLEFT", 0, -18)
    self:LayoutCategory(shownCategory, shownEntries, owned)
    self:LayoutCategory(hiddenCategory, hiddenEntries, owned)
    frame.WillsCDM_ScrollFrame:UpdateScrollChildRect()

    local needsScrollPadding = frame.WillsCDM_ScrollFrame:GetVerticalScrollRange() > 0
    if needsScrollPadding then
        if not frame.WillsCDM_ScrollPadding then
            frame.WillsCDM_ScrollPadding = CreateFrame("Frame", nil, frame.WillsCDM_ScrollChild)
            frame.WillsCDM_ScrollPadding:SetHeight(18)
        end
        frame.WillsCDM_ScrollPadding:ClearAllPoints()
        frame.WillsCDM_ScrollPadding:SetPoint("TOPLEFT", hiddenCategory, "BOTTOMLEFT")
        frame.WillsCDM_ScrollPadding:SetPoint("TOPRIGHT", hiddenCategory, "BOTTOMRIGHT")
    end

    if frame.WillsCDM_ScrollPadding then
        frame.WillsCDM_ScrollPadding:SetShown(needsScrollPadding)
    end

    frame.WillsCDM_ScrollFrame:Hide()
    frame.WillsCDM_ScrollFrame:Show()
end

local function ShowMiscPanel(settingsFrame)
    settingsFrame.CooldownScroll:Hide()
    settingsFrame.WillsCDM_ScrollFrame:Show()
    MiscPanel:RefreshMiscPanel(settingsFrame)
end

function MiscPanel:EnsureMiscSettingsTab(settingsFrame)
    if settingsFrame.WillsCDM_ScrollFrame then
        return
    end

    local scrollFrame = CreateFrame("ScrollFrame", "$parent.WillsCDM_CooldownScroll", settingsFrame,
        "ScrollFrameTemplate")
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
        MiscPanel:RefreshMiscPanel(settingsFrame)
    end)

    local shownCategory = self:CreateItemCategory(scrollChild, "Misc Cooldowns", ITEM_STATE_SHOWN)
    local hiddenCategory = self:CreateItemCategory(scrollChild, "Not Displayed", ITEM_STATE_HIDDEN)

    settingsFrame.WillsCDM_Categories = { shownCategory, hiddenCategory }
    local spellsTab = settingsFrame.SpellsTab
    local aurasTab = settingsFrame.AurasTab
    scrollFrame:Hide()
    settingsFrame.WillsCDM_ScrollFrame = scrollFrame
    settingsFrame.WillsCDM_ScrollChild = scrollChild

    -- Do not parent the miscTab to settingsFrame! Doing so will add it to its .TabButtons list and will taint everything inside CooldownViewer as a result.
    local miscTab = CreateFrame("Button", "$parent.MiscTab", UIParent, "CooldownViewerSettingsTabTemplate")
    miscTab.WillsCDM_IsTabButton = true
    miscTab.tooltipText = "Misc"
    miscTab.displayMode = "misc"
    miscTab.activeAtlas = "minimap-genericevent-hornicon-small"
    miscTab.inactiveAtlas = "minimap-genericevent-hornicon-small"
    miscTab:SetChecked(false)
    miscTab:SetPoint("TOP", aurasTab, "BOTTOM", 0, -3)

    -- Hide the tab when the settings window is closed
    settingsFrame:HookScript("OnHide", function()
        miscTab:Hide()
    end)
    settingsFrame:HookScript("OnShow", function()
        miscTab:Show()
    end)

    miscTab:SetScript("OnClick", function(self)
        if settingsFrame.WillsCDM_ScrollFrame:IsShown() then
            return
        end

        spellsTab:SetChecked(false)
        aurasTab:SetChecked(false)
        self:SetChecked(true)

        ShowMiscPanel(settingsFrame)
    end)

    hooksecurefunc(settingsFrame, "SetDisplayMode", function(self, mode)
        spellsTab:SetChecked(mode == "spells")
        aurasTab:SetChecked(mode == "auras")
        miscTab:SetChecked(mode == "misc")
        MiscPanel:HideMiscPanel(self)
        settingsFrame.CooldownScroll:Show()
    end)

    hooksecurefunc(settingsFrame, "RefreshVisibleCategories", function(self)
        if self.WillsCDM_ScrollFrame and self.WillsCDM_ScrollFrame:IsShown() then
            MiscPanel:RefreshMiscPanel(self)
        end
    end)

    hooksecurefunc(settingsFrame, "ApplyFilter", function(self)
        if self.WillsCDM_ScrollFrame and self.WillsCDM_ScrollFrame:IsShown() then
            MiscPanel:RefreshMiscPanel(self)
        end
    end)

    miscTab:Show()
end
