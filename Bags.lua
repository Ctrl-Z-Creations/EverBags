-- EverBags bags window: replaces the default backpack and bags.
local ADDON, ns = ...

local function Call(button, method, ...)
	local fn = button[method]
	if fn then return fn(button, ...) end
end

-- One hidden parent per bag carries the bag ID for Blizzard's item button code.
local bagParents = {}
local function GetBagParent(window, bag)
	local p = bagParents[bag]
	if not p then
		p = CreateFrame("Frame", nil, window.Content)
		p:SetID(bag)
		p:SetAllPoints(window.Content)
		p.IsCombinedBagContainer = function() return false end
		bagParents[bag] = p
	end
	return p
end

local function CreateBagButton(window, bag, slot)
	local name = ("EverBagsItem%d_%d"):format(bag + 10, slot)
	local b = CreateFrame("ItemButton", name, GetBagParent(window, bag), "ContainerFrameItemButtonTemplate")
	-- SetBagID stores the bag through a secure attribute, so using items stays untainted.
	b:SetBagID(bag)
	b:SetID(slot)
	return b
end

local function UpdateBagButton(window, b, bag, slot, info, questInfo, tooltipOwner)
	local texture = info and info.iconFileID
	local quality = info and info.quality

	ClearItemButtonOverlay(b)
	b:SetHasItem(texture)
	b:SetItemButtonTexture(texture)
	SetItemButtonQuality(b, quality, info and info.hyperlink, false, info and info.isBound)
	SetItemButtonCount(b, info and info.stackCount)
	SetItemButtonDesaturated(b, info and info.isLocked)

	Call(b, "UpdateExtended")
	Call(b, "UpdateQuestItem", questInfo.isQuestItem, questInfo.questID, questInfo.isActive)
	Call(b, "UpdateNewItem", quality)
	-- Blizzard's junk coin (top-left, merchant only) is replaced by EverBags's own.
	if b.JunkIcon then b.JunkIcon:Hide() end
	Call(b, "UpdateItemContextMatching")
	Call(b, "UpdateCooldown", texture)
	Call(b, "SetReadable", info and info.isReadable)
	Call(b, "CheckUpdateTooltip", tooltipOwner)
end

local function GetBags()
	local bags = {}
	for bag = ns.BACKPACK, ns.LAST_BAG do table.insert(bags, bag) end
	if ns.db.showKeyring then table.insert(bags, ns.KEYRING) end
	return bags
end

local Bags = ns.CreateWindow("bags", {
	title = "Backpack",
	titleKey = "bagTitle",
	portrait = "Interface\\Icons\\INV_Misc_Bag_08",
	columnsKey = "columns",
	worthLabel = "Bag Worth",
	suggestDrops = true,
	Sort = function() C_Container.SortBags() end,
	defaultPoint = { "BOTTOMRIGHT", "BOTTOMRIGHT", -80, 120 },
	GetBags = GetBags,
	-- Another character's bags come from their saved snapshot.
	GetSnapshot = function()
		if not ns.IsViewingOther() then return nil end
		return ns.GetSnapshotView(ns.viewKey, "bags") or ns.EmptySnapshotView(ns.viewKey, "bags")
	end,
	CreateButton = CreateBagButton,
	UpdateButton = UpdateBagButton,
	OnLayout = function(self)
		local snap = self.snapshot
		self.MoneyText:SetText(GetMoneyString(snap and snap.money or GetMoney(), true))
		ns.UpdateFarmDisplay()
	end,
})
ns.Bags = Bags

Bags.MoneyText = Bags.Footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
Bags.MoneyText:SetPoint("BOTTOMRIGHT", -18, 14)

-- Farming summary beside the free-slot count.
Bags.FarmButton = ns.CreateFarmButton(Bags)

-- Hovering the money lists every character's gold, with a total.
Bags.MoneyButton = CreateFrame("Frame", nil, Bags.Footer)
Bags.MoneyButton:SetPoint("TOPLEFT", Bags.MoneyText, "TOPLEFT", -4, 4)
Bags.MoneyButton:SetPoint("BOTTOMRIGHT", Bags.MoneyText, "BOTTOMRIGHT", 4, -4)
Bags.MoneyButton:EnableMouse(true)
Bags.MoneyButton:SetScript("OnEnter", function(self) ns.ShowMoneyTooltip(self) end)
Bags.MoneyButton:SetScript("OnLeave", GameTooltip_Hide)

-- Left of the view button: Deposit (gray away from a banker).
Bags.DepositButton = ns.CreateDepositButton(Bags)
Bags.DepositButton:SetPoint("RIGHT", Bags.ViewButton, "LEFT", -4, 0)
Bags.DepositButton:SetFrameLevel(Bags.ViewButton:GetFrameLevel())

-- Side tab "Bags": opens the bags from the bank window.
ns.windowOpeners.bags = {
	CanShow = function() return true end,
	Show = function() OpenAllBags() end,
}

------------------------------------------------------------------------
-- Open/close: mirror Blizzard's bag state
------------------------------------------------------------------------
local syncing = false

local function Sync()
	if syncing then return end
	syncing = true
	if IsAnyBagOpen() then
		if not Bags:IsShown() then Bags:Show() end
	elseif Bags:IsShown() then
		Bags:Hide()
	end
	syncing = false
end

Bags:SetScript("OnShow", function(self)
	ns.PlaySound("IG_BACKPACK_OPEN")
	self:Layout()
end)

Bags:SetScript("OnHide", function(self)
	ns.PlaySound("IG_BACKPACK_CLOSE")
	-- Clear "new item" glows, like the default bags do on close.
	for bag, slots in pairs(self.buttons) do
		for slot in pairs(slots) do C_NewItems.RemoveNewItem(bag, slot) end
	end
	self.SearchBox:SetText("")
	-- With every EverBags window closed, go back to this character.
	if not (ns.Bank and ns.Bank:IsShown()) then ns.viewKey = nil end
	-- Closed via Escape or the X button: tell Blizzard too.
	if not syncing and IsAnyBagOpen() then
		syncing = true
		CloseAllBags()
		syncing = false
	end
end)

local function HideBlizzardBags()
	local hidden = CreateFrame("Frame")
	hidden:Hide()
	-- Reparenting keeps Blizzard's open/closed bookkeeping (IsShown) intact
	-- while making its frames invisible.
	if ContainerFrameContainer then ContainerFrameContainer:SetParent(hidden) end
	if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetParent(hidden) end

	for _, fn in ipairs({ "OpenBackpack", "CloseBackpack", "ToggleBackpack", "OpenAllBags",
		"CloseAllBags", "ToggleAllBags", "OpenBag", "CloseBag", "ToggleBag" }) do
		if _G[fn] then hooksecurefunc(fn, Sync) end
	end
end

------------------------------------------------------------------------
-- Hovering a bag on Blizzard's bag bar outlines that bag's slots, using the
-- same edge glow the default bags use (each item button's BagIndicator).
------------------------------------------------------------------------
local function HighlightBag(bagID, on)
	local slots = bagID and Bags.buttons[bagID]
	if not slots then return end
	for _, b in pairs(slots) do
		if b.BagIndicator then b.BagIndicator:SetShown(on and b:IsShown()) end
	end
end

local function BagSlotID(bagSlot)
	return bagSlot and bagSlot.GetBagID and bagSlot:GetBagID()
end

table.insert(ns.onLogin, function()
	if not (EventRegistry and EventRegistry.RegisterCallback) then return end
	EventRegistry:RegisterCallback("BagSlot.OnEnter", function(_, bagSlot)
		HighlightBag(BagSlotID(bagSlot), true)
	end, Bags)
	EventRegistry:RegisterCallback("BagSlot.OnLeave", function(_, bagSlot)
		HighlightBag(BagSlotID(bagSlot), false)
	end, Bags)
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
table.insert(ns.onLogin, function()
	HideBlizzardBags()
	-- Pre-create buttons out of combat.
	for _, bag in ipairs(GetBags()) do
		for slot = 1, ns.GetNumSlots(bag) do Bags:GetButton(bag, slot) end
	end
end)

local function IsBagsBag(bag)
	return bag == nil or bag == ns.KEYRING or (bag >= ns.BACKPACK and bag <= ns.LAST_BAG)
end

for _, e in ipairs({ "BAG_UPDATE", "BAG_CONTAINER_UPDATE", "BAG_NEW_ITEMS_UPDATED",
	"QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
	ns.On(e, function(event, arg1)
		if event == "BAG_UPDATE" and not IsBagsBag(arg1) then return end
		Bags:RequestLayout()
	end)
end

ns.On("ITEM_LOCK_CHANGED", function() if Bags:IsShown() then Bags:UpdateLocks() end end)
ns.On("BAG_UPDATE_COOLDOWN", function() if Bags:IsShown() then Bags:UpdateCooldowns() end end)
ns.On("PLAYER_MONEY", function()
	if not Bags.snapshot then Bags.MoneyText:SetText(GetMoneyString(GetMoney(), true)) end
end)
