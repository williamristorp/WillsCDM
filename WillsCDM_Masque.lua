local addonName, addon = ...
addon = addon or {}

local MasqueSupport = addon.MasqueSupport or {}
addon.MasqueSupport = MasqueSupport

local function GetMasque()
    if not LibStub then
        return nil
    end
    return LibStub("Masque", true)
end

local function GetTexture(button, name)
    if not button then
        return nil
    end
    local value = button[name]
    if value then
        return value
    end
    local getter = button["Get" .. name .. "Texture"]
    if getter then
        return getter(button)
    end
    return nil
end

local function BuildRegions(button)
    if not button then
        return nil
    end
    return {
        Icon = button.Icon,
        Cooldown = button.Cooldown,
        Normal = button.NormalTexture or GetTexture(button, "Normal"),
        Pushed = button.PushedTexture or GetTexture(button, "Pushed"),
        Disabled = button.DisabledTexture or GetTexture(button, "Disabled"),
        Checked = button.CheckedTexture or GetTexture(button, "Checked"),
        Highlight = button.Highlight or (button.GetHighlightTexture and button:GetHighlightTexture()),
        Border = button.Border,
        IconBorder = button.IconBorder,
        Backdrop = button.Background,
        Flash = button.Flash,
        HotKey = button.HotKey,
        Count = button.Count,
        Name = button.Name,
        Duration = button.Duration,
        AutoCastable = button.AutoCastable,
        AutoCast = button.AutoCast,
        SlotHighlight = button.SlotHighlight,
    }
end

local function DisableDefaultItemViewerBorder(button)
    if not button then
        return
    end
    print("Disabling default border for button:", button:GetName())

    for _, child in ipairs({ button:GetRegions() }) do
        print("Checking child:", child:GetName(), "Type:", child:GetObjectType())
        if child:GetObjectType() == "Texture" and child:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
            print("Hiding border texture:", child:GetName())
            child:Hide()
        end

        if child:GetObjectType() == "MaskTexture" then
            print("Hiding mask texture:", child:GetName())
            child:Hide()
        end
    end
end

local function EnsureGroups()
    local masque = GetMasque()
    if not masque then
        return nil
    end

    if not MasqueSupport.groups then
        MasqueSupport.groups = {
            ItemViewer = masque:Group(addonName, "Item Viewer"),
            MiscPanel = masque:Group(addonName, "Misc Panel"),
        }
    end

    return MasqueSupport.groups
end

function MasqueSupport:IsEnabled()
    return GetMasque() ~= nil
end

function MasqueSupport:ShouldManageItemViewer()
    return self:IsEnabled()
end

function MasqueSupport:RegisterItemViewerButton(button)
    local groups = EnsureGroups()
    if not groups or not button then
        return
    end
    if button.WillsCDM_MasqueGroup == "ItemViewer" then
        return
    end
    DisableDefaultItemViewerBorder(button)
    groups.ItemViewer:AddButton(button, BuildRegions(button))
    if groups.ItemViewer.ReSkin then
        groups.ItemViewer:ReSkin()
    end
    button.WillsCDM_MasqueGroup = "ItemViewer"
end

function MasqueSupport:RegisterMiscPanelButton(button)
    local groups = EnsureGroups()
    if not groups or not button then
        return
    end
    if button.WillsCDM_MasqueGroup == "MiscPanel" then
        return
    end
    groups.MiscPanel:AddButton(button, BuildRegions(button))
    if groups.MiscPanel.ReSkin then
        groups.MiscPanel:ReSkin()
    end
    button.WillsCDM_MasqueGroup = "MiscPanel"
end

function MasqueSupport:UnregisterButton(button)
    if not button or not button.WillsCDM_MasqueGroup then
        return
    end
    local groups = EnsureGroups()
    if not groups then
        button.WillsCDM_MasqueGroup = nil
        return
    end
    local group = groups[button.WillsCDM_MasqueGroup]
    if group and group.RemoveButton then
        group:RemoveButton(button)
        if group.ReSkin then
            group:ReSkin()
        end
    end
    button.WillsCDM_MasqueGroup = nil
end
