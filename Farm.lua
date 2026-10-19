-- EverBags farming summary: a running tally of what you've gained this session
-- (it resets when you log in, not on /reload, or when you click it), shown in the bags window's footer ("+38 items · +5g 32s").
--
-- Only looting counts as farming: kills, chests, herbs, ore, skins, fishing,
-- opened containers. Items and gold that arrive any other way (vendors, mail,
-- auction house, trades, crafting, quest rewards) are ignored, and spending or
-- selling later changes nothing. Quest gold is its own line, on by default.
--
-- Items: compares your bags + bank totals each time they're saved; increases
-- that follow loot activity are counted, valued as of when you got them.
local ADDON, ns = ...

local lastVendorValue = 0
function ns.FarmVendorValue() ns.FarmTotals() return lastVendorValue end

local function MyRecord()
	return ns.GetCharacter(ns.MyKey())
end

-- Loot activity: the loot window is open, or closed within the last 2 seconds
-- (gold and items land just as it closes, especially with auto loot).
local lootOpen, lootClosedAt, lootSinceRecount = false, -100, false
local function Looting()
	return lootOpen or (GetTime() - lootClosedAt) < 2
end
for _, e in ipairs({ "LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CLEARED" }) do
	ns.On(e, function() lootOpen, lootSinceRecount = true, true end)
end
ns.On("LOOT_CLOSED", function()
	lootOpen, lootClosedAt, lootSinceRecount = false, GetTime(), true
end)

local function NewTally(rec, bags, bank)
	return {
		start = time(),
		gold = 0,                -- gold looted
		questGold = 0,           -- gold from quest rewards
		lastMoney = GetMoney(),
		gained = {},             -- itemID -> how many you've gained (only goes up)
		links = {},
		last = { bags = bags, bank = bank },
		bankKnown = rec.bankTime ~= nil,
	}
end

-- A fresh login (not a /reload) starts a new tally, once this session's bags are saved.
local newSession, sessionStart = false, 0

function ns.FarmRecount()
	local rec = MyRecord()
	if not rec or not rec.bagsTime then return end
	if newSession then
		if rec.bagsTime < sessionStart then return end -- still last session's save
		newSession = false
		rec.farm = nil
	end
	local bags, bagLinks = ns.TallyContainers(rec.bags)
	local bank, bankLinks = ns.TallyContainers(rec.bankTime and rec.bank or nil)
	local f = rec.farm
	if not f then
		rec.farm = NewTally(rec, bags, bank)
		ns.UpdateFarmDisplay()
		return
	end
	-- The first bank visit reveals what was already there: that's not a gain.
	if rec.bankTime and not f.bankKnown then
		f.last.bank = bank
		f.bankKnown = true
	end
	-- New items only count when they came from looting.
	local fromLoot = lootSinceRecount or Looting()
	lootSinceRecount = false
	local seen = {}
	for _, t in ipairs({ bags, bank }) do
		for id in pairs(t) do
			if not seen[id] then
				seen[id] = true
				local now = (bags[id] or 0) + (bank[id] or 0)
				local before = (f.last.bags[id] or 0) + (f.last.bank[id] or 0)
				if now > before and fromLoot then
					f.gained[id] = (f.gained[id] or 0) + (now - before)
					f.links[id] = f.links[id] or bagLinks[id] or bankLinks[id]
				end
			end
		end
	end
	f.last = { bags = bags, bank = bank }
	ns.UpdateFarmDisplay()
end

function ns.FarmReset()
	local rec = MyRecord()
	if not rec then return end
	rec.farm = nil
	-- Start from exactly what you have now.
	ns.SaveBags()
	ns.SaveBank()
	ns.FarmRecount()
	ns.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
end

-- items, value of those items, gold change, seconds since the start
function ns.FarmTotals()
	local rec = MyRecord()
	local f = rec and rec.farm
	if not f then return 0, 0, 0, 0 end
	-- value = best price (vendor or auction); vendorValue = everything at vendor price.
	local items, value, vendorValue = 0, 0, 0
	for id, n in pairs(f.gained) do
		items = items + n
		local vendor, auction = ns.GetSlotValueParts({ itemID = id, stackCount = n, hyperlink = f.links[id] })
		vendorValue = vendorValue + (vendor or 0)
		value = value + math.max(vendor or 0, auction or 0)
	end
	lastVendorValue = vendorValue
	local gold = (f.gold or 0) + (ns.db.farmQuestGold and (f.questGold or 0) or 0)
	return items, value, gold, time() - (f.start or time()), f.gold or 0, f.questGold or 0
end

function ns.FarmGained(itemID)
	local rec = MyRecord()
	return rec ~= nil and rec.farm ~= nil and itemID ~= nil and (rec.farm.gained[itemID] or 0) > 0
end

local function SignedMoney(copper)
	if copper == 0 then return "0" end
	local text = GetMoneyString(math.abs(copper), true)
	return (copper < 0 and "-" or "+") .. text
end

------------------------------------------------------------------------
-- Footer text and hover
------------------------------------------------------------------------
function ns.UpdateFarmDisplay()
	local bags = ns.Bags
	if not bags or not bags.FarmButton then return end
	local show = ns.db.showFarm and not bags.snapshot
	bags.FarmButton:SetShown(show)
	if not show then return end
	local items, value, gold = ns.FarmTotals()
	local text = ("+%d item%s · %s"):format(items, items == 1 and "" or "s", SignedMoney(value + gold))
	bags.FarmText:SetText(text)
	bags.FarmButton:SetWidth(bags.FarmText:GetStringWidth() + 6)
end

local function Duration(seconds)
	if seconds < 3600 then return ("%d min"):format(math.floor(seconds / 60)) end
	return ("%d hr %d min"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

function ns.CreateFarmButton(window)
	local b = CreateFrame("Button", nil, window.Footer)
	b:SetHeight(16)
	b:SetPoint("LEFT", window.FreeText, "RIGHT", 10, 0)
	window.FarmText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.FarmText:SetPoint("LEFT", 2, 0)
	b:SetScript("OnClick", function()
		ns.FarmReset()
		if b:IsMouseOver() then b:GetScript("OnEnter")(b) end
	end)
	b:SetScript("OnEnter", function(self)
		local items, value, gold, seconds, looted, quest = ns.FarmTotals()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Farming Summary", 1, 1, 1)
		GameTooltip:AddDoubleLine(("%d item%s looted, worth"):format(items, items == 1 and "" or "s"),
			GetMoneyString(value, true), 1, 1, 1, 1, 1, 1)
		-- With auction prices in play: how much is vendor value, how much needs the auction house.
		local vendorValue = lastVendorValue
		if value > vendorValue then
			GameTooltip:AddDoubleLine("   Vendor price", GetMoneyString(vendorValue, true), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
			GameTooltip:AddDoubleLine("   Auction house extra", "+" .. GetMoneyString(value - vendorValue, true), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
		end
		GameTooltip:AddDoubleLine("Gold looted", SignedMoney(looted), 1, 1, 1, 1, 1, 1)
		if ns.db.farmQuestGold then
			GameTooltip:AddDoubleLine("Quest gold", SignedMoney(quest), 1, 1, 1, 1, 1, 1)
		end
		local total = value + gold
		local line = "Over " .. Duration(seconds)
		if seconds >= 300 and total > 0 then
			line = line .. " · " .. GetMoneyString(math.floor(total * 3600 / seconds), true) .. " per hour"
		end
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Click to reset.", 0, 1, 0)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetFrameLevel(window.FreeButton:GetFrameLevel())
	return b
end

-- Gold: only what you loot counts here; quest rewards are added up separately.
ns.On("PLAYER_MONEY", function()
	local rec = MyRecord()
	local f = rec and rec.farm
	if f then
		local now = GetMoney()
		local delta = now - (f.lastMoney or now)
		if delta > 0 and Looting() then f.gold = (f.gold or 0) + delta end
		f.lastMoney = now
	end
	ns.UpdateFarmDisplay()
end)

ns.On("QUEST_TURNED_IN", function(_, questID, xpReward, moneyReward)
	local rec = MyRecord()
	local f = rec and rec.farm
	if f and type(moneyReward) == "number" and moneyReward > 0 and not ns.IsSecret(moneyReward) then
		f.questGold = (f.questGold or 0) + moneyReward
		ns.UpdateFarmDisplay()
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
	if isInitialLogin then
		newSession, sessionStart = true, time()
	end
end)
