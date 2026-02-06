local addonName, addon = ...
addon = addon or {}

local DB = addon.DB
local ItemsData = addon.ItemsData or {}
addon.ItemsData = ItemsData

local ITEM_EQUIP_FIRST = INVSLOT_FIRST_EQUIPPED or 1
local ITEM_EQUIP_LAST = INVSLOT_LAST_EQUIPPED or 19

local ITEM_STATE_SHOWN = "shown"
local ITEM_STATE_HIDDEN = "hidden"
local ITEM_STATE_REMOVED = "removed"

local lastOwnedItems = {}
local hasOwnedSnapshot = false

local function GetItemNameByID(itemID)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemID)
    end
    local name = GetItemInfo(itemID)
    return name
end

local function ItemSortKey(itemID)
    local name = GetItemNameByID(itemID)
    if not name or name == "" then
        return tostring(itemID)
    end
    return name:lower()
end

local function SortItemIDs(items)
    table.sort(items, function(a, b)
        local aOrder = DB.GetItemSettings(a) and DB.GetItemSettings(a).order or nil
        local bOrder = DB.GetItemSettings(b) and DB.GetItemSettings(b).order or nil
        if aOrder ~= nil and bOrder ~= nil and aOrder ~= bOrder then
            return aOrder < bOrder
        elseif aOrder ~= nil and bOrder == nil then
            return true
        elseif aOrder == nil and bOrder ~= nil then
            return false
        end
        local aName = ItemSortKey(a)
        local bName = ItemSortKey(b)
        if aName ~= bName then
            return aName < bName
        end
        return a < b
    end)
end

local function GetItemOrder(itemID)
    local settings = DB.GetItemSettings(itemID)
    return settings and settings.order or nil
end

local function SetItemOrder(itemID, order)
    local settings = DB.EnsureItemSettings(itemID)
    settings.order = order
end

local function EnsureOrderForIDs(ids)
    local maxOrder = 0
    for _, itemID in ipairs(ids) do
        local order = GetItemOrder(itemID)
        if order and order > maxOrder then
            maxOrder = order
        end
    end

    for _, itemID in ipairs(ids) do
        if GetItemOrder(itemID) == nil then
            maxOrder = maxOrder + 1
            SetItemOrder(itemID, maxOrder)
        end
    end
end

local function ReassignOrders(ids)
    for index, itemID in ipairs(ids) do
        SetItemOrder(itemID, index)
    end
end

local function InsertItemAt(state, itemID, targetItemID, insertBefore)
    itemID = tonumber(itemID) or itemID
    targetItemID = tonumber(targetItemID) or targetItemID
    local ids = ItemsData.GetItemIDsByState(state)
    local existingIndex = nil
    for index, id in ipairs(ids) do
        if id == itemID then
            existingIndex = index
            break
        end
    end

    if existingIndex then
        table.remove(ids, existingIndex)
    end

    local insertIndex = #ids + 1
    if targetItemID then
        for index, id in ipairs(ids) do
            if id == targetItemID then
                insertIndex = insertBefore and index or (index + 1)
                break
            end
        end
    end

    table.insert(ids, insertIndex, itemID)
    ReassignOrders(ids)
end

local function IsTrackableItem(itemID)
    if not itemID then
        return false
    end
    local name, spellID = C_Item.GetItemSpell(itemID)
    if spellID or name then
        return true
    end
    return false
end

local function ScanOwnedItems()
    local owned = {}

    if C_Container and NUM_BAG_SLOTS then
        for bag = 0, NUM_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if IsTrackableItem(itemID) and not (C_Item.IsEquippableItem and C_Item.IsEquippableItem(itemID)) then
                    owned[itemID] = true
                end
            end
        end
    end

    for slot = ITEM_EQUIP_FIRST, ITEM_EQUIP_LAST do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location and C_Item.DoesItemExist(location) then
            local itemID = C_Item.GetItemID(location)
            if IsTrackableItem(itemID) then
                owned[itemID] = true
            end
        end
    end

    return owned
end

local function EnsureTrackedItems(owned)
    for itemID in pairs(owned) do
        local state = DB.GetItemState(itemID)
        if state == nil then
            DB.SetItemState(itemID, ITEM_STATE_HIDDEN)
        elseif state == ITEM_STATE_REMOVED then
            if hasOwnedSnapshot and not lastOwnedItems[itemID] then
                DB.SetItemState(itemID, ITEM_STATE_HIDDEN)
            end
        end
    end
    lastOwnedItems = owned
    hasOwnedSnapshot = true
end

local function GetItemIDsByState(state)
    local ids = {}
    local db = DB.GetDB()
    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == state then
            table.insert(ids, itemID)
        end
    end
    EnsureOrderForIDs(ids)
    SortItemIDs(ids)
    return ids
end

local function GetVisibleItemIDs(owned)
    local ids = {}
    local db = DB.GetDB()
    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == ITEM_STATE_SHOWN and owned[itemID] then
            table.insert(ids, itemID)
        end
    end
    EnsureOrderForIDs(ids)
    SortItemIDs(ids)
    return ids
end

ItemsData.ITEM_STATE_SHOWN = ITEM_STATE_SHOWN
ItemsData.ITEM_STATE_HIDDEN = ITEM_STATE_HIDDEN
ItemsData.ITEM_STATE_REMOVED = ITEM_STATE_REMOVED
ItemsData.GetItemNameByID = GetItemNameByID
ItemsData.InsertItemAt = InsertItemAt
ItemsData.ScanOwnedItems = ScanOwnedItems
ItemsData.EnsureTrackedItems = EnsureTrackedItems
ItemsData.GetItemIDsByState = GetItemIDsByState
ItemsData.GetVisibleItemIDs = GetVisibleItemIDs
