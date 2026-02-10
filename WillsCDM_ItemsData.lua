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

local racialSpellCache = nil
local racialSpellCacheDirty = true
local didMigrateLegacyEntries = false

local function MakeEntry(kind, id)
    return {
        kind = kind,
        id = id
    }
end

local function IsSpellEntry(entry)
    return entry and entry.kind == "spell"
end

local function EntriesEqual(a, b)
    return a and b and a.kind == b.kind and a.id == b.id
end

local function GetSpellNameByID(spellID)
    return C_Spell.GetSpellName(spellID)
end

local function GetRacialSpellIDsFromSpellBook()
    if racialSpellCache and not racialSpellCacheDirty then
        return racialSpellCache
    end

    local ids = {}

    for skillLineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if skillLineInfo.name == "General" then
            local offset = skillLineInfo.itemIndexOffset
            local numSpells = skillLineInfo.numSpellBookItems

            for spellBookItemIndex = offset + 1, offset + numSpells do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(spellBookItemIndex, Enum.SpellBookSpellBank.Player)
                if not spellInfo.isPassive then
                    if spellInfo.itemType == Enum.SpellBookItemType.Flyout then
                        local _, _, numSlots = GetFlyoutInfo(spellInfo.actionID)
                        for i = 1, numSlots do
                            local flyoutSpellID, _, isKnown, _, _ = GetFlyoutSlotInfo(spellInfo.actionID, i)
                            if isKnown then
                                if not C_Spell.IsSpellPassive(flyoutSpellID) then
                                    ids[flyoutSpellID] = true
                                end
                            end
                        end
                    else
                        ids[spellInfo.spellID] = true
                    end
                end
            end
        end
    end

    racialSpellCache = ids
    racialSpellCacheDirty = false
    return ids
end

local function MigrateLegacyNegativeEntries()
    if didMigrateLegacyEntries then
        return
    end
    didMigrateLegacyEntries = true

    local db = DB.GetDB()
    if not db or type(db.itemSettings) ~= "table" then
        return
    end

    db.spellItemSettings = db.spellItemSettings or {}
    local toMove = {}
    for itemID in pairs(db.itemSettings) do
        if type(itemID) == "number" and itemID < 0 then
            table.insert(toMove, itemID)
        end
    end

    for _, itemID in ipairs(toMove) do
        local spellID = -itemID
        if db.spellItemSettings[spellID] == nil then
            db.spellItemSettings[spellID] = db.itemSettings[itemID]
        end
        db.itemSettings[itemID] = nil
    end
end

function ItemsData:InvalidateRacialSpellCache()
    racialSpellCacheDirty = true
end

function ItemsData:GetItemNameByID(itemID)
    return C_Item.GetItemNameByID(itemID)
end

function ItemsData:GetEntryName(kind, id)
    if kind == "spell" then
        return GetSpellNameByID(id)
    end
    return self:GetItemNameByID(id)
end

local function GetEntrySettings(entry)
    if IsSpellEntry(entry) then
        return DB.GetSpellItemSettings(entry.id)
    end
    return DB.GetItemSettings(entry.id)
end

local function EnsureEntrySettings(entry)
    if IsSpellEntry(entry) then
        return DB.EnsureSpellItemSettings(entry.id)
    end
    return DB.EnsureItemSettings(entry.id)
end

local function EntrySortKey(entry)
    local name = ItemsData:GetEntryName(entry.kind, entry.id)
    if not name or name == "" then
        return tostring(entry.id)
    end
    return name:lower()
end

local function SortEntries(entries)
    table.sort(entries, function(a, b)
        local aOrder = GetEntrySettings(a) and GetEntrySettings(a).order or nil
        local bOrder = GetEntrySettings(b) and GetEntrySettings(b).order or nil
        if aOrder ~= nil and bOrder ~= nil and aOrder ~= bOrder then
            return aOrder < bOrder
        elseif aOrder ~= nil and bOrder == nil then
            return true
        elseif aOrder == nil and bOrder ~= nil then
            return false
        end
        local aName = EntrySortKey(a)
        local bName = EntrySortKey(b)
        if aName ~= bName then
            return aName < bName
        end
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return a.id < b.id
    end)
end

local function GetEntryOrder(entry)
    local settings = GetEntrySettings(entry)
    return settings and settings.order or nil
end

local function SetEntryOrder(entry, order)
    local settings = EnsureEntrySettings(entry)
    settings.order = order
end

local function EnsureOrderForEntries(entries)
    local maxOrder = 0
    for _, entry in ipairs(entries) do
        local order = GetEntryOrder(entry)
        if order and order > maxOrder then
            maxOrder = order
        end
    end

    for _, entry in ipairs(entries) do
        if GetEntryOrder(entry) == nil then
            maxOrder = maxOrder + 1
            SetEntryOrder(entry, maxOrder)
        end
    end
end

local function ReassignOrders(entries)
    for index, entry in ipairs(entries) do
        SetEntryOrder(entry, index)
    end
end

function ItemsData:InsertItemAt(state, entry, targetEntry, insertBefore)
    if not entry then
        return
    end

    local entries = self:GetEntriesByState(state)
    local existingIndex = nil
    for index, candidate in ipairs(entries) do
        if EntriesEqual(candidate, entry) then
            existingIndex = index
            break
        end
    end

    if existingIndex then
        table.remove(entries, existingIndex)
    end

    local insertIndex = #entries + 1
    if targetEntry then
        for index, candidate in ipairs(entries) do
            if EntriesEqual(candidate, targetEntry) then
                insertIndex = insertBefore and index or (index + 1)
                break
            end
        end
    end

    table.insert(entries, insertIndex, MakeEntry(entry.kind, entry.id))
    ReassignOrders(entries)
end

function ItemsData:GetEntryState(kind, id)
    if kind == "spell" then
        return DB.GetSpellItemState(id)
    end
    return DB.GetItemState(id)
end

function ItemsData:SetEntryState(kind, id, state)
    if kind == "spell" then
        DB.SetSpellItemState(id, state)
    else
        DB.SetItemState(id, state)
    end
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

function ItemsData:ScanOwnedItems()
    local owned = {
        items = {},
        spells = {}
    }

    if C_Container and NUM_BAG_SLOTS then
        for bag = 0, NUM_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if IsTrackableItem(itemID) and not (C_Item.IsEquippableItem and C_Item.IsEquippableItem(itemID)) then
                    owned.items[itemID] = true
                end
            end
        end
    end

    for slot = ITEM_EQUIP_FIRST, ITEM_EQUIP_LAST do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location and C_Item.DoesItemExist(location) then
            local itemID = C_Item.GetItemID(location)
            if IsTrackableItem(itemID) then
                owned.items[itemID] = true
            end
        end
    end

    local racialSpells = GetRacialSpellIDsFromSpellBook()
    for spellID in pairs(racialSpells) do
        owned.spells[spellID] = true
    end

    return owned
end

function ItemsData:EnsureTrackedItems(owned)
    MigrateLegacyNegativeEntries()

    local ownedItems = owned and owned.items or {}
    local ownedSpells = owned and owned.spells or {}

    for itemID in pairs(ownedItems) do
        local state = DB.GetItemState(itemID)
        if state == nil then
            DB.SetItemState(itemID, ITEM_STATE_HIDDEN)
        end
    end

    for spellID in pairs(ownedSpells) do
        local state = DB.GetSpellItemState(spellID)
        if state == nil then
            DB.SetSpellItemState(spellID, ITEM_STATE_HIDDEN)
        end
    end
end

function ItemsData:GetEntriesByState(state)
    local entries = {}
    local db = DB.GetDB()

    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == state then
            table.insert(entries, MakeEntry("item", itemID))
        end
    end

    for spellID, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == state then
            table.insert(entries, MakeEntry("spell", spellID))
        end
    end

    EnsureOrderForEntries(entries)
    SortEntries(entries)
    return entries
end

function ItemsData:GetItemIDsByState(state)
    local entries = self:GetEntriesByState(state)
    local ids = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "item" then
            table.insert(ids, entry.id)
        end
    end
    return ids
end

function ItemsData:GetVisibleEntries(owned)
    local entries = {}
    local db = DB.GetDB()
    local ownedItems = owned and owned.items or {}
    local ownedSpells = owned and owned.spells or {}

    for itemID, settings in pairs(db.itemSettings or {}) do
        if settings.state == ITEM_STATE_SHOWN and ownedItems[itemID] then
            table.insert(entries, MakeEntry("item", itemID))
        end
    end

    for spellID, settings in pairs(db.spellItemSettings or {}) do
        if settings.state == ITEM_STATE_SHOWN and ownedSpells[spellID] then
            table.insert(entries, MakeEntry("spell", spellID))
        end
    end

    EnsureOrderForEntries(entries)
    SortEntries(entries)
    return entries
end

ItemsData.ITEM_STATE_SHOWN = ITEM_STATE_SHOWN
ItemsData.ITEM_STATE_HIDDEN = ITEM_STATE_HIDDEN
ItemsData.ITEM_STATE_REMOVED = ITEM_STATE_REMOVED
