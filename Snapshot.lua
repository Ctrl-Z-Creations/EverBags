-- EverBags snapshots: every character's bags, bank and money, saved account-wide.
--
-- Each character's record is refreshed whenever its bags change, and its bank
-- while it's at a banker. The windows show these records read-only when you
-- browse another character (or your own bank away from a banker), and item
-- tooltips list who else holds an item.
local ADDON, ns = ...

local BagIndex = Enum.BagIndex or {}
local FIRST_BANK_BAG = BagIndex.CharacterBankTab_1 or 6
local LAST_BANK_BAG = BagIndex.CharacterBankTab_9 or 14

------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------
local myKey

-- Realm names in one spelling, without spaces or dashes ("Classic Beta PvP" -> "ClassicBetaPvP"),
-- which is what GetNormalizedRealmName returns once it's available.
local function Normalize(realm)
	return ((realm or ""):gsub("[%s%-]", ""))
end

local function Realm()
	return Normalize((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()))
end

-- Characters are saved under the game's unique character ID (GUID), since in
-- Forever two characters can share a first name. nil until the ID is known.
function ns.MyKey()
	if myKey then return myKey end
	local guid = UnitGUID and UnitGUID("player")
	if not guid or ns.IsSecret(guid) or guid == "" then return nil end
	myKey = guid
	return myKey
end

-- The old key (0.5.0): "FirstName-Realm".
local function OldKey()
	local name, realm = ns.PlayerName(), Realm()
	if not name or realm == "" then return nil end
	return name .. "-" .. realm
end

-- Saved settings load after the windows are built (Blizzard's dropdown builds
-- its menu right away), so this can run before ns.db exists.
local function Characters()
	if not ns.db then return {} end
	ns.db.characters = ns.db.characters or {}
	return ns.db.characters
end

function ns.GetCharacter(key)
	return key and Characters()[key]
end

local function MyRecord()
	local key = ns.MyKey()
	if not key then return nil end
	local chars = Characters()
	local rec = chars[key]
	if not rec then
		rec = { bags = {}, bank = {} }
		chars[key] = rec
	end
	rec.name = ns.PlayerName()
	rec.realm = Realm()
	rec.class = select(2, UnitClass("player"))
	rec.lastSeen = time()
	return rec
end

-- Characters sorted: you first, then by name.
function ns.CharacterKeys()
	local keys, me = {}, ns.MyKey()
	for key in pairs(Characters()) do
		if key ~= me then table.insert(keys, key) end
	end
	table.sort(keys)
	if me and Characters()[me] then table.insert(keys, 1, me) end
	return keys
end

-- Name in class color; realm added when it differs from yours.
function ns.CharacterLabel(key, plain)
	local rec = ns.GetCharacter(key)
	local name = rec and rec.name or (key and key:match("^[^-]+")) or "?"
	if rec and rec.realm and Normalize(rec.realm) ~= Realm() then name = name .. "-" .. rec.realm end
	if plain then return name end
	local color = rec and rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
	if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
	return name
end

function ns.ForgetCharacter(key)
	if not key or key == ns.MyKey() then return end
	Characters()[key] = nil
	ns.InvalidateCounts(key)
	if ns.viewKey == key then ns.viewKey = nil end
	ns.RefreshAll()
end

------------------------------------------------------------------------
-- Saving
------------------------------------------------------------------------
local function SaveSlot(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then return nil end
	local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
	return {
		id = info.itemID,
		c = info.stackCount or 1,
		q = info.quality,
		l = info.hyperlink,
		b = info.isBound and true or nil,
		nv = info.hasNoValue and true or nil,
		qi = quest and (quest.isQuestItem or quest.questID) and true or nil,
	}
end

local function SaveContainers(bags)
	local out = {}
	for _, bag in ipairs(bags) do
		local size = ns.GetNumSlots(bag)
		if size > 0 then
			local items = {}
			for slot = 1, size do items[slot] = SaveSlot(bag, slot) end
			out[bag] = { size = size, items = items }
		end
	end
	return out
end

-- At login and logout the game reports empty bags and 0 gold for a moment.
-- Saving then would wipe the character's record, so wait for real data
-- (the backpack always has slots).
local function InventoryLoaded()
	return ns.GetNumSlots(ns.BACKPACK) > 0
end

function ns.SaveBags()
	if not InventoryLoaded() then return end
	local rec = MyRecord()
	if not rec then return end
	local bags = {}
	for bag = ns.BACKPACK, ns.LAST_BAG do table.insert(bags, bag) end
	table.insert(bags, ns.KEYRING)
	rec.bags = SaveContainers(bags)
	rec.bagsTime = time()
	rec.money = GetMoney()
	ns.InvalidateCounts(ns.MyKey())
end

function ns.SaveBank()
	local rec = MyRecord()
	if not rec or not (ns.Bank and ns.Bank.atBank) then return end
	local tabs = ns.Bank.opts.GetBags(ns.Bank)
	if #tabs == 0 then return end
	rec.bank = SaveContainers(tabs)
	rec.bankTime = time()
	ns.InvalidateCounts(ns.MyKey())
end

function ns.SaveMoney()
	if not InventoryLoaded() then return end
	local rec = MyRecord()
	if rec then rec.money = GetMoney() end
end

------------------------------------------------------------------------
-- Read-only views for the windows
------------------------------------------------------------------------
local EMPTY_QUEST = {}

-- Turns a saved slot into the same shape as C_Container.GetContainerItemInfo.
local function ToInfo(s)
	local link = s.l
	return {
		itemID = s.id,
		stackCount = s.c,
		quality = s.q or (C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(s.id)),
		hyperlink = link,
		iconFileID = C_Item.GetItemIconByID and C_Item.GetItemIconByID(s.id),
		isBound = s.b == true,
		hasNoValue = s.nv == true,
		questInfo = s.qi and { isQuestItem = true } or EMPTY_QUEST,
		snapshot = true,
	}
end

local View = {}
View.__index = View

function View:NumSlots(bag)
	local c = self.containers[bag]
	return c and c.size or 0
end

function View:Info(bag, slot)
	local c = self.containers[bag]
	local s = c and c.items[slot]
	if not s then return nil end
	self.infoCache[bag] = self.infoCache[bag] or {}
	local info = self.infoCache[bag][slot]
	if not info then
		info = ToInfo(s)
		self.infoCache[bag][slot] = info
	end
	return info
end

-- kind: "bags" or "bank". Returns nil when there's no saved record.
function ns.GetSnapshotView(key, kind)
	local rec = ns.GetCharacter(key)
	local containers = rec and rec[kind]
	local savedAt = rec and rec[kind .. "Time"]
	if not savedAt then return nil end
	local bagList = {}
	for bag in pairs(containers) do
		if bag ~= ns.KEYRING or (kind == "bags" and ns.db.showKeyring) then table.insert(bagList, bag) end
	end
	table.sort(bagList, function(a, b)
		if a == ns.KEYRING then return false elseif b == ns.KEYRING then return true end
		return a < b
	end)
	return setmetatable({
		key = key, kind = kind, name = rec.name, time = savedAt, money = rec.money,
		containers = containers, bagList = bagList, infoCache = {},
	}, View)
end

-- An empty view, for a character with nothing saved yet (title says "not saved yet").
function ns.EmptySnapshotView(key, kind)
	local rec = ns.GetCharacter(key)
	return setmetatable({ key = key, kind = kind, name = rec and rec.name, money = rec and rec.money,
		containers = {}, bagList = {}, infoCache = {} }, View)
end

function ns.HasSnapshot(key, kind)
	local rec = ns.GetCharacter(key)
	return rec ~= nil and rec[kind .. "Time"] ~= nil
end

-- "just now", "5 min ago", "3 hr ago", "2 days ago"
function ns.Ago(t)
	local s = math.max(0, time() - (t or 0))
	if s < 60 then return "just now" end
	if s < 3600 then return ("%d min ago"):format(math.floor(s / 60)) end
	if s < 86400 then return ("%d hr ago"):format(math.floor(s / 3600)) end
	local d = math.floor(s / 86400)
	return ("%d day%s ago"):format(d, d == 1 and "" or "s")
end

------------------------------------------------------------------------
-- Item counts across characters (for tooltips)
------------------------------------------------------------------------
local counts = {} -- [key] = { bags = { [itemID] = n }, bank = { [itemID] = n } }

function ns.InvalidateCounts(key)
	if key then counts[key] = nil else wipe(counts) end
end

-- itemID -> total count, plus itemID -> an item link.
local function Tally(containers)
	local t, links = {}, {}
	for _, c in pairs(containers or {}) do
		for _, s in pairs(c.items or {}) do
			t[s.id] = (t[s.id] or 0) + (s.c or 1)
			links[s.id] = links[s.id] or s.l
		end
	end
	return t, links
end
ns.TallyContainers = Tally

local function CountsFor(key)
	local c = counts[key]
	if not c then
		local rec = ns.GetCharacter(key)
		c = { bags = Tally(rec and rec.bags), bank = Tally(rec and rec.bank) }
		counts[key] = c
	end
	return c
end

-- { { key, bags, bank }, ... } for every character holding the item, you first.
function ns.WhoHas(itemID)
	local out = {}
	for _, key in ipairs(ns.CharacterKeys()) do
		local c = CountsFor(key)
		local bags, bank = c.bags[itemID] or 0, c.bank[itemID] or 0
		if bags + bank > 0 then table.insert(out, { key = key, bags = bags, bank = bank }) end
	end
	return out
end

local function CountText(bags, bank)
	local parts = {}
	if bags > 0 then table.insert(parts, bags .. " in bags") end
	if bank > 0 then table.insert(parts, bank .. " in bank") end
	return table.concat(parts, ", ")
end

function ns.AddItemCounts(tooltip, itemID)
	if not (ns.db and ns.db.tooltipCounts) or not itemID or ns.IsSecret(itemID) then return end
	local who = ns.WhoHas(itemID)
	if #who == 0 then return end
	-- Only your own copies: nothing new to tell.
	if #who == 1 and who[1].key == ns.MyKey() then return end
	tooltip:AddLine(" ")
	local total = 0
	for _, w in ipairs(who) do
		tooltip:AddDoubleLine(ns.CharacterLabel(w.key), CountText(w.bags, w.bank), 1, 1, 1, 1, 1, 1)
		total = total + w.bags + w.bank
	end
	if #who > 1 then tooltip:AddDoubleLine("Total", tostring(total), 1, 0.82, 0, 1, 0.82, 0) end
end

local function HookTooltips()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		-- Skip the side-by-side comparison tooltips.
		if tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then return end
		if not data or not data.id or ns.IsSecret(data.id) then return end
		ns.AddItemCounts(tooltip, data.id)
	end)
end

------------------------------------------------------------------------
-- Money across characters (tooltip on the bags window's money)
------------------------------------------------------------------------
function ns.ShowMoneyTooltip(owner)
	ns.SaveMoney()
	local list, total = {}, 0
	for _, key in ipairs(ns.CharacterKeys()) do
		local rec = ns.GetCharacter(key)
		local money = (key == ns.MyKey()) and GetMoney() or (rec and rec.money) or 0
		table.insert(list, { key = key, money = money })
		total = total + money
	end
	table.sort(list, function(a, b) return a.money > b.money end)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText("Gold on your characters", 1, 1, 1)
	for _, e in ipairs(list) do
		GameTooltip:AddDoubleLine(ns.CharacterLabel(e.key), GetMoneyString(e.money, true), 1, 1, 1, 1, 1, 1)
	end
	if #list > 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Total", GetMoneyString(total, true), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end

------------------------------------------------------------------------
-- Which character the windows are showing (nil = you, live)
------------------------------------------------------------------------
ns.viewKey = nil

function ns.ViewKey()
	return ns.viewKey or ns.MyKey()
end

function ns.IsViewingOther()
	return ns.viewKey ~= nil and ns.viewKey ~= ns.MyKey()
end

function ns.SetViewCharacter(key)
	if key == ns.MyKey() then key = nil end
	if ns.viewKey == key then return end
	ns.viewKey = key
	ns.PlaySound("IG_CHARACTER_INFO_TAB")
	ns.RefreshAll()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local pending = false
local function SaveSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		ns.SaveBags()
		ns.SaveBank()
		-- Bags and bank are both current now (a deposit shows up in both at once).
		if ns.FarmRecount then ns.FarmRecount() end
	end)
end

-- 0.5.0 could save a character twice ("Name-ClassicBetaPvP" and "Name-Classic Beta PvP").
-- Merge them, keeping the newer bags and bank.
-- Copies the better bags/bank from one record into another:
-- real data beats an empty save; otherwise the newer one wins.
local function MergeInto(from, into)
	for _, kind in ipairs({ "bags", "bank" }) do
		local mine, theirs = next(from[kind] or {}) ~= nil, next(into[kind] or {}) ~= nil
		if (mine and not theirs) or (mine == theirs and (from[kind .. "Time"] or 0) > (into[kind .. "Time"] or 0)) then
			into[kind], into[kind .. "Time"] = from[kind], from[kind .. "Time"]
			if kind == "bags" then into.money = from.money end
		end
	end
end

local function IsGUIDKey(key)
	return key:match("^Player%-") ~= nil
end

-- Moves this character's record from its old "Name-Realm" key to its ID.
function ns.MigrateToGUID()
	local guid, old = ns.MyKey(), OldKey()
	local chars = Characters()
	if not guid or not old or not chars[old] then return end
	if chars[guid] then
		MergeInto(chars[old], chars[guid])
	else
		chars[guid] = chars[old]
	end
	chars[old] = nil
	ns.InvalidateCounts()
end

function ns.MergeRealmSpellings()
	local chars = Characters()
	local keys = {}
	for key in pairs(chars) do table.insert(keys, key) end
	for _, key in ipairs(keys) do
		local rec = chars[key]
		local name, realm = key:match("^([^-]+)-(.*)$")
		if IsGUIDKey(key) then
			if rec.realm then rec.realm = Normalize(rec.realm) end
		elseif name and Normalize(realm) ~= realm then
			local fixed = name .. "-" .. Normalize(realm)
			local other = chars[fixed]
			chars[key] = nil
			if not other then
				chars[fixed] = rec
				other = rec
			else
				MergeInto(rec, other)
			end
			other.realm = Normalize(realm)
		elseif rec.realm then
			rec.realm = Normalize(rec.realm)
		end
	end
	ns.InvalidateCounts()
end

table.insert(ns.onLogin, function()
	ns.db.characters = ns.db.characters or {}
	ns.MergeRealmSpellings()
	ns.MigrateToGUID()
	HookTooltips()
	-- Item data can still be loading right at login; save again shortly after.
	ns.SaveBags()
	C_Timer.After(3, function()
		ns.SaveBags()
		if ns.FarmRecount then ns.FarmRecount() end
	end)
end)

ns.On("BAG_UPDATE_DELAYED", SaveSoon)
ns.On("PLAYER_MONEY", ns.SaveMoney)
ns.On("BAG_UPDATE", function(_, bag)
	if type(bag) == "number" and bag >= FIRST_BANK_BAG and bag <= LAST_BANK_BAG then SaveSoon() end
end)
