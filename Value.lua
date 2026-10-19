-- EverBags value and cleanup helpers:
--   * what each slot is worth (vendor price, or Auctionator's price when higher)
--   * suggested drops when bags are nearly full
--   * notes added to item tooltips explaining why an item is suggested
local ADDON, ns = ...

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------
local sellPriceCache = {}

local function LoadItemInfo(itemID)
	if sellPriceCache[itemID] == nil then
		local sellPrice = select(11, C_Item.GetItemInfo(itemID))
		if sellPrice then sellPriceCache[itemID] = sellPrice end
	end
end


local function AuctionPrice(info)
	if not ns.db.useAuctionPrices or info.isBound then return nil end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.GetAuctionPriceByItemLink) then return nil end
	local ok, price = pcall(api.GetAuctionPriceByItemLink, ADDON, info.hyperlink)
	if ok and type(price) == "number" and price > 0 then return price end
	return nil
end

function ns.HasAuctionPrices()
	return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
end

-- Vendor value and auction value (nil without a price) for the whole stack,
-- or nil while item data loads.
function ns.GetSlotValueParts(info)
	if not info or not info.itemID then return 0, nil end
	LoadItemInfo(info.itemID)
	local unit = sellPriceCache[info.itemID]
	if unit == nil then return nil end
	if info.hasNoValue then unit = 0 end
	local count = info.stackCount or 1
	local auction = AuctionPrice(info)
	return unit * count, auction and auction * count or nil
end

-- Total copper for the whole stack in a slot (the higher of vendor and
-- auction price), or nil while item data loads.
function ns.GetSlotValue(info)
	local vendor, auction = ns.GetSlotValueParts(info)
	if vendor == nil then return nil end
	if auction then return math.max(vendor, auction) end
	return vendor
end

function ns.FormatMoney(copper)
	if not copper or copper <= 0 then return "" end
	return GetMoneyString(copper, true)
end

------------------------------------------------------------------------
-- Suggested drops (bags window): lowest value per slot
------------------------------------------------------------------------
ns.showSuggestions = false -- toggled by clicking the free-slots text

function ns.ShouldSuggestDrops(free)
	if not ns.db.suggestDrops then return false end
	return ns.showSuggestions or free <= ns.db.lowSpaceThreshold
end

-- entries: { info, questInfo, bag, slot, value } for every item slot.
-- Returns the chosen entries (at most count), cheapest first.
function ns.PickSuggestions(entries, count)
	local candidates = {}
	for _, e in ipairs(entries) do
		local info = e.info
		local eligible = info and e.bag ~= ns.KEYRING and e.value ~= nil
		if eligible then
			-- Never suggest items a quest needs, or items that can't be sold.
			if (e.questInfo and (e.questInfo.isQuestItem or e.questInfo.questID)) or info.hasNoValue then
				eligible = false
			end
		end
		if eligible then table.insert(candidates, e) end
	end
	table.sort(candidates, function(a, b)
		if a.value ~= b.value then return a.value < b.value end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
	local picked = {}
	for i = 1, math.min(count, #candidates) do picked[i] = candidates[i] end
	return picked
end

------------------------------------------------------------------------
-- Tooltip notes: explains why an item is flagged
------------------------------------------------------------------------
local notes = {} -- [bag][slot] = text

function ns.SetSlotNote(bag, slot, text)
	notes[bag] = notes[bag] or {}
	notes[bag][slot] = text
end

local function AddNote(tooltip, bag, slot)
	local text = notes[bag] and notes[bag][slot]
	if text then
		tooltip:AddLine("EverBags: " .. text, 1, 0.82, 0, true)
		tooltip:Show()
	end
end

table.insert(ns.onLogin, function()
	if GameTooltip and GameTooltip.SetBagItem then
		hooksecurefunc(GameTooltip, "SetBagItem", AddNote)
	end
end)

