-- EverBags bank window: replaces the default bank.
--
-- Forever's bank stores items in "bank tab" containers (bag IDs 6-14). Forever
-- has no warband bank. Blizzard's BankFrame is kept open but invisible, so
-- right-click deposits and the bank session still work.
local ADDON, ns = ...

local BagIndex = Enum.BagIndex or {}
local FIRST_BANK_BAG = BagIndex.CharacterBankTab_1 or 6
local LAST_BANK_BAG = BagIndex.CharacterBankTab_9 or 14

local BankType = Enum.BankType or { Character = 0 }

local BANKER_TYPES = {}
do
	local PIT = Enum.PlayerInteractionType or {}
	for _, name in ipairs({ "Banker", "CharacterBanker", "AccountBanker" }) do
		if PIT[name] then BANKER_TYPES[PIT[name]] = true end
	end
end

local function IsBankBag(bag)
	return type(bag) == "number" and bag >= FIRST_BANK_BAG and bag <= LAST_BANK_BAG
end


------------------------------------------------------------------------
-- Buttons: Blizzard's own bank item buttons (Forever skin when available)
------------------------------------------------------------------------
local function CreateBankButton(window, bag, slot)
	local name = ("EverBagsBankItem%d_%d"):format(bag, slot)
	local ok, b = pcall(CreateFrame, "ItemButton", name, window.Content, "CamelotBankItemButtonTemplate")
	if not ok or not b then
		b = CreateFrame("ItemButton", name, window.Content, "BankItemButtonTemplate")
	end
	b:SetSize(37, 37)
	return b
end

local function UpdateBankButton(window, b, bag, slot)
	if not b.isInitialized then
		b:Init(BankType.Character, bag, slot)
	else
		b:Refresh()
	end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local Bank = ns.CreateWindow("bank", {
	title = BANK or "Bank",
	titleKey = "bankTitle",
	Sort = function()
		if C_Container.SortBank then
			C_Container.SortBank(Enum.BankType and Enum.BankType.Character or 0)
		else
			C_Container.SortBankBags()
		end
	end,
	columnsKey = "bankColumns",
	worthLabel = "Bank Worth",
	defaultPoint = { "TOPLEFT", "TOPLEFT", 40, -120 },
	GetBags = function(self)
		local bags = {}
		local tabs = C_Bank.FetchPurchasedBankTabData(self.bankType)
		for _, tab in ipairs(tabs or {}) do table.insert(bags, tab.ID) end
		return bags
	end,
	-- Away from a banker, or browsing another character: the saved bank.
	GetSnapshot = function(self)
		if self.atBank and not ns.IsViewingOther() then return nil end
		local key = ns.ViewKey()
		return ns.GetSnapshotView(key, "bank") or ns.EmptySnapshotView(key, "bank")
	end,
	CreateButton = CreateBankButton,
	UpdateButton = UpdateBankButton,
	OnLayout = function(self)
		-- Buying bank bags needs the real bank.
		self.DefaultButton:SetShown(self.atBank and not self.snapshot)
	end,
})
ns.Bank = Bank
Bank.bankType = BankType.Character

-- Opens Blizzard's own bank (needed to buy or swap bank bags).
Bank.DefaultButton = CreateFrame("Button", nil, Bank, "UIPanelButtonTemplate")
Bank.DefaultButton:SetSize(110, 20)
Bank.DefaultButton:SetPoint("BOTTOMRIGHT", -16, 10)
Bank.DefaultButton:SetText("Default Bank")
Bank.DefaultButton:SetFrameLevel(Bank.Footer:GetFrameLevel() + 1)
Bank.DefaultButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Open Blizzard's bank window, for buying or swapping bank bags.", nil, nil, nil, nil, true)
	GameTooltip:Show()
end)
Bank.DefaultButton:SetScript("OnLeave", GameTooltip_Hide)

-- Keep Blizzard's hidden bank on the same tab, so right-click deposits from
-- the bags go to the bank type being viewed.
local function SyncBlizzardBankType(bankType)
	if InCombatLockdown() or not BankFrame or not BankFrame.TabIDToBankType then return end
	for tabID, t in pairs(BankFrame.TabIDToBankType) do
		if t == bankType and BankFrame.SetTab then
			pcall(BankFrame.SetTab, BankFrame, tabID)
			return
		end
	end
end

------------------------------------------------------------------------
-- Replacing Blizzard's bank frame
------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local closingFromServer, handingOff = false, false

local function HideBlizzardBank()
	if BankFrame and BankFrame:GetParent() ~= hiddenParent then
		BankFrame:SetParent(hiddenParent)
	end
end

function Bank:Open()
	if not ns.db.replaceBank or self.atBank then return end
	HideBlizzardBank()
	self.atBank = true
	SyncBlizzardBankType(self.bankType)
	if self.SetPortraitToUnit then self:SetPortraitToUnit("npc") end
	ns.SaveBank()
	ns.FarmRecount() -- first bank visit: its contents become part of the baseline
	if self:IsShown() then self:Layout() else self:Show() end
	OpenAllBags()
end

function Bank:CloseFromServer()
	if self.atBank then ns.SaveBank() end
	self.atBank = false
	ns.RefreshAll() -- the bags' Deposit button grays out
	closingFromServer = true
	if self:IsShown() then
		self:Hide()
		-- Blizzard's hidden bank frame won't close the bags for us.
		CloseAllBags()
	end
	closingFromServer = false
	handingOff = false
	if ns.db.replaceBank then HideBlizzardBank() end
end

Bank.DefaultButton:SetScript("OnClick", function()
	if InCombatLockdown() then return end
	handingOff = true
	Bank:Hide()
	if BankFrame then BankFrame:SetParent(UIParent) end
end)

Bank:SetScript("OnShow", function(self)
	ns.PlaySound("IG_MAINMENU_OPEN")
	self:Layout()
end)

Bank:SetScript("OnHide", function(self)
	ns.PlaySound("IG_MAINMENU_CLOSE")
	if closingFromServer or handingOff then return end
	if not self.atBank then
		-- A saved bank viewed away from a banker: nothing else to close.
		if not ns.Bags:IsShown() then ns.viewKey = nil end
		return
	end
	-- Closed by the player (X or Escape): end the bank session like Blizzard's frame does.
	if BankFrame and BankFrame:IsShown() then HideUIPanel(BankFrame) end
	if C_Bank and C_Bank.CloseBankFrame then C_Bank.CloseBankFrame() end
	CloseAllBags()
end)

-- Side tab "Bank": the live bank at a banker; anywhere else, the saved bank.
local BANK_ICON = "Interface\\ICONS\\INV_SideTab_Bank_c60"
ns.windowOpeners.bank = {
	CanShow = function()
		if not ns.db.replaceBank then return false end
		return Bank.atBank == true or ns.HasSnapshot(ns.ViewKey(), "bank")
	end,
	Show = function()
		handingOff = false
		HideBlizzardBank()
		if not Bank.atBank and Bank.SetPortraitToAsset then Bank:SetPortraitToAsset(BANK_ICON) end
		Bank:Show()
	end,
}
setmetatable(ns.windowOpeners.bank, { __index = function(_, k)
	if k == "unavailable" then
		local who = ns.IsViewingOther() and ns.CharacterLabel(ns.viewKey, true) or "this character"
		return "no saved bank for " .. who .. " yet. Visit a banker on that character once and it's saved."
	end
end })

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
table.insert(ns.onLogin, function()
	if ns.db.replaceBank then HideBlizzardBank() end
end)

ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
	if BANKER_TYPES[interactionType] then Bank:Open() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interactionType)
	if BANKER_TYPES[interactionType] then Bank:CloseFromServer() end
end)
ns.On("BANKFRAME_OPENED", function() Bank:Open() end)
ns.On("BANKFRAME_CLOSED", function() Bank:CloseFromServer() end)

for _, e in ipairs({ "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED",
"BAG_CONTAINER_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do
	ns.On(e, function() Bank:RequestLayout() end)
end
ns.On("BAG_UPDATE", function(_, bag)
	if IsBankBag(bag) then Bank:RequestLayout() end
end)
ns.On("ITEM_LOCK_CHANGED", function(_, bag)
	if Bank:IsShown() and IsBankBag(bag) then Bank:UpdateLocks() end
end)
ns.On("BAG_UPDATE_COOLDOWN", function() if Bank:IsShown() then Bank:UpdateCooldowns() end end)
