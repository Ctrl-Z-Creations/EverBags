-- EverBags search: item names plus keywords.
--
--   Several words must all match:   "green cloak"
--   Commas mean "or":               "potion, food"
--   A leading minus excludes:       "potion -healing"
--   Item level filters:             "ilvl>50", "ilvl<30", "ilvl=45"
--   Keywords (also match by name):  food, water/drink, quality names, item types,
--                                   equipment slots, bound/soulbound, boe, new,
--                                   and the section names (equipment, consumables,
--                                   trade goods, recipes, misc, quest, junk, keys)
local ADDON, ns = ...
local CLASS, CONS, QUALITY = ns.CLASS, ns.CONSUMABLE, ns.QUALITY

------------------------------------------------------------------------
-- Food / drink detection (cached per itemID: "food", "drink", "both", false)
------------------------------------------------------------------------
local edibleCache = {}

local function TooltipEdible(info, bag, slot)
	local ok, data
	if info.snapshot then
		-- Saved items (another character): read the tooltip from the item link.
		if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and info.hyperlink) then return nil end
		ok, data = pcall(C_TooltipInfo.GetHyperlink, info.hyperlink)
	else
		if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
		ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
	end
	if not ok or not data or not data.lines then return nil end
	local eat, drink = false, false
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" and not ns.IsSecret(text) then
			local t = text:lower()
			if t:find("eating", 1, true) then eat = true end
			if t:find("drinking", 1, true) then drink = true end
		end
	end
	if eat and drink then return "both" end
	return (eat and "food") or (drink and "drink") or false
end

local function GetEdibleType(info, bag, slot)
	local itemID = info.itemID
	local cached = edibleCache[itemID]
	if cached ~= nil then return cached end

	local basics = ns.GetItemBasics(itemID)
	if basics.classID ~= CLASS.Consumable then
		edibleCache[itemID] = false
		return false
	end

	-- The use effect's spell: "Food", "Drink" or "Refreshment" (both).
	local spellName = C_Item.GetItemSpell(itemID)
	local result
	if spellName and not ns.IsSecret(spellName) then
		local s = spellName:lower()
		if s == "food" then result = "food"
		elseif s == "drink" then result = "drink"
		elseif s == "refreshment" or (s:find("food", 1, true) and s:find("drink", 1, true)) then result = "both"
		end
	end
	if result == nil then result = TooltipEdible(info, bag, slot) end
	if not result and basics.subclassID == CONS.FoodDrink then result = "both" end

	-- Only cache a firm answer; item data may still be loading.
	if result or spellName then edibleCache[itemID] = result or false end
	return result or false
end

------------------------------------------------------------------------
-- Keyword table: word -> function(info, bag, slot) -> bool
------------------------------------------------------------------------
local function classIs(classID)
	return function(info) return ns.GetItemBasics(info.itemID).classID == classID end
end

local function consumableIs(subclassID)
	return function(info)
		local b = ns.GetItemBasics(info.itemID)
		return b.classID == CLASS.Consumable and b.subclassID == subclassID
	end
end

local function qualityIs(q)
	return function(info) return info.quality == q end
end

local function slotIs(...)
	local locs = {}
	for i = 1, select("#", ...) do locs[select(i, ...)] = true end
	return function(info) return locs[ns.GetItemBasics(info.itemID).equipLoc] == true end
end

local function any(...)
	local fns = { ... }
	return function(info, bag, slot)
		for _, fn in ipairs(fns) do
			if fn(info, bag, slot) then return true end
		end
		return false
	end
end

local KEYWORDS = {
	-- Eat / drink
	food = function(info, bag, slot)
		local t = GetEdibleType(info, bag, slot)
		return t == "food" or t == "both"
	end,
	water = function(info, bag, slot)
		local t = GetEdibleType(info, bag, slot)
		return t == "drink" or t == "both"
	end,

	-- Quality
	poor = qualityIs(QUALITY.Poor),
	common = qualityIs(QUALITY.Common),
	uncommon = qualityIs(QUALITY.Uncommon),
	rare = qualityIs(QUALITY.Rare),
	epic = qualityIs(QUALITY.Epic),
	legendary = qualityIs(QUALITY.Legendary),

	-- Item types
	weapon = classIs(CLASS.Weapon),
	armor = classIs(CLASS.Armor),
	gear = function(info) return ns.IsGear(info.itemID) end,
	consumable = classIs(CLASS.Consumable),
	potion = consumableIs(CONS.Potion),
	elixir = consumableIs(CONS.Elixir),
	flask = consumableIs(CONS.Flask),
	scroll = consumableIs(CONS.Scroll),
	bandage = consumableIs(CONS.Bandage),
	quest = classIs(CLASS.Questitem),
	reagent = any(classIs(CLASS.Reagent), classIs(CLASS.Tradegoods)),
	recipe = classIs(CLASS.Recipe),
	gem = classIs(CLASS.Gem),
	bag = classIs(CLASS.Container),
	quiver = classIs(CLASS.Quiver),
	ammo = classIs(CLASS.Projectile),
	key = classIs(CLASS.Key),

	-- Binding
	bound = function(info) return info.isBound == true end,
	boe = function(info)
		if info.isBound then return false end
		local bindType = select(14, C_Item.GetItemInfo(info.hyperlink or info.itemID))
		return bindType == 2 -- Enum.ItemBind.OnEquip
	end,
	new = function(info, bag, slot) return not info.snapshot and C_NewItems.IsNewItem(bag, slot) == true end,

	-- Equipment slots
	head = slotIs("INVTYPE_HEAD"),
	neck = slotIs("INVTYPE_NECK"),
	shoulder = slotIs("INVTYPE_SHOULDER"),
	back = slotIs("INVTYPE_CLOAK"),
	chest = slotIs("INVTYPE_CHEST", "INVTYPE_ROBE"),
	shirt = slotIs("INVTYPE_BODY"),
	tabard = slotIs("INVTYPE_TABARD"),
	wrist = slotIs("INVTYPE_WRIST"),
	hands = slotIs("INVTYPE_HAND"),
	waist = slotIs("INVTYPE_WAIST"),
	legs = slotIs("INVTYPE_LEGS"),
	feet = slotIs("INVTYPE_FEET"),
	finger = slotIs("INVTYPE_FINGER"),
	trinket = slotIs("INVTYPE_TRINKET"),
	mainhand = slotIs("INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON"),
	offhand = slotIs("INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_WEAPON"),
	onehand = slotIs("INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND"),
	twohand = slotIs("INVTYPE_2HWEAPON"),
	shield = slotIs("INVTYPE_SHIELD"),
	ranged = slotIs("INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN"),
	relic = slotIs("INVTYPE_RELIC"),
}

-- Section names match exactly what's in that section (same rules as Categories view).
local function categoryIs(name)
	return function(info, bag, slot)
		return ns.GetCategory(bag, info, info.questInfo or C_Container.GetContainerItemQuestInfo(bag, slot), true) == name
	end
end
KEYWORDS.equipment = categoryIs("Equipment")
KEYWORDS.consumables = categoryIs("Consumables")
KEYWORDS.tradegoods = categoryIs("Trade Goods")
KEYWORDS.recipes = categoryIs("Recipes")
KEYWORDS.miscellaneous = categoryIs("Miscellaneous")
KEYWORDS.quest = categoryIs("Quest")
KEYWORDS.keys = categoryIs("Keys")

-- Synonyms
local ALIASES = {
	drink = "water", junk = "poor", gray = "poor", grey = "poor", white = "common",
	green = "uncommon", blue = "rare", purple = "epic", orange = "legendary",
	weapons = "weapon", equip = "gear", 
	potions = "potion", elixirs = "elixir", flasks = "flask", scrolls = "scroll",
	bandages = "bandage", reagents = "reagent", mats = "reagent", trade = "reagent",
	gems = "gem", bags = "bag",
	container = "bag", soulbound = "bound", ring = "finger", rings = "finger",
	cloak = "back", shoulders = "shoulder", wrists = "wrist", bracers = "wrist",
	gloves = "hands", hand = "hands", belt = "waist", boots = "feet", pants = "legs",
	helm = "head", necklace = "neck", trinkets = "trinket", ["1h"] = "onehand",
	["2h"] = "twohand", misc = "miscellaneous", key = "keys", arrows = "ammo", bullets = "ammo", projectile = "ammo",
}
for alias, word in pairs(ALIASES) do KEYWORDS[alias] = KEYWORDS[word] end

------------------------------------------------------------------------
-- Parsing and matching
------------------------------------------------------------------------
local function ParseTerm(word)
	local negate = false
	if #word > 1 and word:sub(1, 1) == "-" then
		negate, word = true, word:sub(2)
	end

	local op, num = word:match("^ilvl([<>=]=?)(%d+)$")
	if op then
		num = tonumber(num)
		local test
		if op == ">" then test = function(l) return l > num end
		elseif op == ">=" then test = function(l) return l >= num end
		elseif op == "<" then test = function(l) return l < num end
		elseif op == "<=" then test = function(l) return l <= num end
		else test = function(l) return l == num end end
		return { negate = negate, fn = function(info)
			local ilvl = ns.GetItemLevel(info)
			return ilvl ~= nil and test(ilvl)
		end }
	end

	local keyword = KEYWORDS[word]
	return { negate = negate, fn = function(info, bag, slot)
		if keyword and keyword(info, bag, slot) then return true end
		return ns.GetItemName(info):lower():find(word, 1, true) ~= nil
	end }
end

-- query = list of groups; a group is a list of terms that must all match.
-- An item matches when any group matches (commas separate groups).
local query = {}

function ns.SetSearch(text)
	query = {}
	text = (text or ""):lower():gsub("trade%s+goods", "tradegoods")
	for part in (text .. ","):gmatch("([^,]*),") do
		local group = {}
		for word in part:gmatch("%S+") do table.insert(group, ParseTerm(word)) end
		if #group > 0 then table.insert(query, group) end
	end
	return #query == 0
end

function ns.HasSearch()
	return #query > 0
end

local function GroupMatches(group, info, bag, slot)
	for _, term in ipairs(group) do
		local ok = term.fn(info, bag, slot)
		if term.negate then ok = not ok end
		if not ok then return false end
	end
	return true
end

function ns.MatchesSearch(info, bag, slot)
	if #query == 0 then return true end
	if not info or not info.hyperlink then return false end
	for _, group in ipairs(query) do
		if GroupMatches(group, info, bag, slot) then return true end
	end
	return false
end

ns.KEYWORDS = KEYWORDS -- exposed for testing
