-- EverBags deposit: moves items from your bags into the bank in one click.
--
-- What moves: the items matching your current search, or, with no search, the
-- section chosen in settings (Trade Goods by default).
-- Items move one at a time, waiting for the server to finish each move.
local ADDON, ns = ...

local STEP_DELAY = 0.12
local LOCK_TIMEOUT = 3
local MAX_MOVES = 200

local runner = CreateFrame("Frame")
local job

-- At a banker, and the bags window is showing this character (not a saved one).
local function AtBank()
	return ns.Bank ~= nil and ns.Bank.atBank == true and not ns.IsViewingOther()
end
ns.AtBank = AtBank

local function BagList()
	local bags = {}
	for bag = ns.BACKPACK, ns.LAST_BAG do table.insert(bags, bag) end
	return bags
end

local function ShouldDeposit(info, bag, slot)
	if not info then return false end
	if ns.HasSearch() then return ns.MatchesSearch(info, bag, slot) end
	local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
	return ns.GetCategory(bag, info, questInfo, true) == ns.db.depositCategory
end

local function AnyLocked()
	for _, bag in ipairs(BagList()) do
		for slot = 1, ns.GetNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then return true end
		end
	end
	return false
end

local function Finish(message)
	runner:SetScript("OnUpdate", nil)
	if message then ns.Print(message) end
	job = nil
	ns.RefreshAll()
end

local function Step(_, elapsed)
	job.wait = job.wait + elapsed
	if job.wait < STEP_DELAY then return end
	job.idle = job.idle + job.wait
	job.wait = 0

	if not AtBank() then Finish("deposit stopped: you left the bank.") return end
	if InCombatLockdown() then Finish("deposit stopped: you entered combat.") return end
	if AnyLocked() then
		if job.idle > LOCK_TIMEOUT then Finish("deposit stopped: items stayed locked.") end
		return
	end

	-- A slot we already sent that still holds the same item means the bank is full.
	for key, itemID in pairs(job.sent) do
		local bag, slot = key:match("^(-?%d+):(%d+)$")
		local info = C_Container.GetContainerItemInfo(tonumber(bag), tonumber(slot))
		if info and info.itemID == itemID then
			Finish(("your bank is full. Deposited %d item%s."):format(job.moved, job.moved == 1 and "" or "s"))
			return
		end
		job.sent[key] = nil
		job.moved = job.moved + 1
	end

	for _, bag in ipairs(BagList()) do
		for slot = 1, ns.GetNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if ShouldDeposit(info, bag, slot) and job.moved + 1 <= MAX_MOVES then
				job.sent[bag .. ":" .. slot] = info.itemID
				C_Container.UseContainerItem(bag, slot, nil, Enum.BankType and Enum.BankType.Character or 0)
				job.idle = 0
				return
			end
		end
	end
	Finish(job.moved > 0 and ("deposited %d item%s into the bank."):format(job.moved, job.moved == 1 and "" or "s")
		or "nothing to deposit.")
end

function ns.Deposit()
	if job then return end
	if ns.IsViewingOther() then
		ns.Print("switch back to this character to deposit items.")
		return
	end
	if not AtBank() then
		ns.Print("visit a banker to deposit items.")
		return
	end
	if InCombatLockdown() then
		ns.Print("can't deposit during combat.")
		return
	end
	job = { sent = {}, moved = 0, wait = STEP_DELAY, idle = 0 }
	runner:SetScript("OnUpdate", Step)
end

function ns.IsDepositing()
	return job ~= nil
end

-- Toolbar button: always visible; gray and inactive away from a banker.
function ns.CreateDepositButton(window)
	local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	b:SetSize(26, 22)
	b:SetText("")
	if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
	b.Icon = b:CreateTexture(nil, "OVERLAY")
	b.Icon:SetTexture("Interface\\ICONS\\INV_SideTab_Bank_c60")
	b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.Icon:SetSize(16, 16)
	b.Icon:SetPoint("CENTER")
	b:SetScript("OnClick", function() ns.Deposit() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Deposit to bank", 1, 1, 1)
		if ns.HasSearch() then
			GameTooltip:AddLine("Moves the items matching your search into the bank.", nil, nil, nil, true)
		else
			GameTooltip:AddLine(("Moves your %s into the bank. Search first to deposit something else."):format(ns.db.depositCategory), nil, nil, nil, true)
		end
		if not AtBank() then GameTooltip:AddLine("Only works while you're at a banker.", 1, 0.3, 0.3, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

function ns.UpdateDepositButton(b)
	local available = AtBank()
	b:SetEnabled(available)
	b.Icon:SetDesaturated(not available)
	b.Icon:SetAlpha(available and 1 or 0.6)
end
