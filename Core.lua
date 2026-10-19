-- EverBags core: saved settings, shared helpers and event dispatch.
local ADDON, ns = ...

-- Version comes from the .toc; the packager fills it in from the git tag.
local tocVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
ns.VERSION = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"

ns.DEFAULTS = {
	columns = 10,
	bagTitle = "Backpack",
	bankTitle = "Bank",
	bankColumns = 14,
	scale = 1,
	categorize = false,
	showItemLevel = true,
	showJunkCoin = true,
	showKeyring = true,
	compactEmpty = true,
	replaceBank = true,
	depositCategory = "Trade Goods",
	showValues = true,
	foreverArt = true,
	useAuctionPrices = true,
	suggestDrops = true,
	lowSpaceThreshold = 4,
	suggestCount = 6,
	tooltipCounts = true,
	showFarm = true,          -- farming summary in the bags footer
	farmQuestGold = true,     -- include quest reward gold in the farming summary     -- item tooltips list your other characters' counts
	characters = {},          -- ["Name-Realm"] = saved bags, bank and money (Snapshot.lua)
	collapsed = {},  -- [windowKey] = { [category] = true }
	points = {},     -- [windowKey] = { point, relativePoint, x, y }
}

------------------------------------------------------------------------
-- Enums with fallbacks (values from the Forever API documentation)
------------------------------------------------------------------------
local IC = Enum.ItemClass or {}
ns.CLASS = {
	Consumable = IC.Consumable or 0,
	Container = IC.Container or 1,
	Weapon = IC.Weapon or 2,
	Gem = IC.Gem or 3,
	Armor = IC.Armor or 4,
	Reagent = IC.Reagent or 5,
	Projectile = IC.Projectile or 6,
	Tradegoods = IC.Tradegoods or 7,
	Recipe = IC.Recipe or 9,
	Quiver = IC.Quiver or 11,
	Questitem = IC.Questitem or 12,
	Key = IC.Key or 13,
	Miscellaneous = IC.Miscellaneous or 15,
}

local SUB = Enum.ItemConsumableSubclass or {}
ns.CONSUMABLE = {
	Potion = SUB.Potion or 1,
	Elixir = SUB.Elixir or 2,
	Flask = SUB.Flasksphials or 3,
	Scroll = SUB.Scroll or 4,
	FoodDrink = SUB.Fooddrink or 5,
	Bandage = SUB.Bandage or 7,
}

local Q = Enum.ItemQuality or {}
ns.QUALITY = {
	Poor = Q.Poor or 0,
	Common = Q.Common or 1,
	Uncommon = Q.Uncommon or 2,
	Rare = Q.Rare or 3,
	Epic = Q.Epic or 4,
	Legendary = Q.Legendary or 5,
	Artifact = Q.Artifact or 6,
	Heirloom = Q.Heirloom or 7,
}

ns.KEYRING = (Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER or -1
ns.BACKPACK = (Enum.BagIndex and Enum.BagIndex.Backpack) or 0
ns.NUM_BAG_SLOTS = (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or NUM_BAG_SLOTS or 4
ns.LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or ns.NUM_BAG_SLOTS
-- The reagent bag slot (bag 5) only holds crafting reagents.
ns.REAGENT_BAG = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or (ns.LAST_BAG > ns.NUM_BAG_SLOTS and ns.NUM_BAG_SLOTS + 1) or nil
function ns.IsReagentBag(bag) return ns.REAGENT_BAG ~= nil and bag == ns.REAGENT_BAG end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function ns.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

function ns.PlaySound(key)
	local id = SOUNDKIT and SOUNDKIT[key]
	if id then PlaySound(id) end
end

-- Words players can pick for the window titles ("Thrall's Backpack").
ns.TITLE_WORDS = {
	bagTitle = { "Backpack", "Bags", "Inventory", "Pack", "Satchel", "Haversack", "Belongings", "Stash", "Hoard" },
	bankTitle = { "Bank", "Vault", "Treasury", "Coffers", "Strongbox", "Storage", "Stash", "Hoard" },
}

function ns.PlayerName()
	local name = UnitName("player")
	if not name or name == UNKNOWNOBJECT or name == "Unknown" then return nil end
	return name
end

function ns.Print(msg)
	print("|cff33ff99EverBags|r " .. msg)
end

-- Cached GetItemInfoInstant: itemID -> { classID, subclassID, equipLoc }
local instantCache = {}
function ns.GetItemBasics(itemID)
	local c = instantCache[itemID]
	if not c then
		local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
		c = { classID = classID, subclassID = subclassID, equipLoc = equipLoc or "" }
		instantCache[itemID] = c
	end
	return c
end

function ns.IsGear(itemID)
	local b = ns.GetItemBasics(itemID)
	return (b.classID == ns.CLASS.Weapon or b.classID == ns.CLASS.Armor) and b.equipLoc ~= ""
		and b.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

function ns.GetItemLevel(info)
	if not info or not info.hyperlink or not ns.IsGear(info.itemID) then return nil end
	local ilvl = C_Item.GetDetailedItemLevelInfo(info.hyperlink)
	if ilvl and not ns.IsSecret(ilvl) and ilvl > 1 then return ilvl end
	return nil
end

function ns.GetItemName(info)
	if not info or not info.hyperlink then return "" end
	return info.hyperlink:match("%[(.-)%]") or ""
end

function ns.GetNumSlots(bag)
	if bag == ns.KEYRING then
		if C_ActionBar and C_ActionBar.ShouldShowKeyring and not C_ActionBar.ShouldShowKeyring() then
			return 0
		end
		if GetKeyRingSize then
			local ok, size = pcall(GetKeyRingSize)
			if ok and size then return size end
		end
	end
	return C_Container.GetContainerNumSlots(bag) or 0
end

------------------------------------------------------------------------
-- Events: modules register handlers with ns.On(event, fn)
------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- Some events may not exist on every client build; don't error on those.
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do list[i](event, ...) end
end)

-- Callbacks run after saved variables are ready (ADDON_LOADED) and at login.
ns.onReady, ns.onLogin = {}, {}

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	EverBagsDB = EverBagsDB or {}
	for k, v in pairs(ns.DEFAULTS) do
		if EverBagsDB[k] == nil then
			EverBagsDB[k] = type(v) == "table" and {} or v
		end
	end
	EverBagsDB.protected = nil -- Protect items was removed in 0.4.14
	ns.db = EverBagsDB
	for _, fn in ipairs(ns.onReady) do fn() end
end)

ns.On("PLAYER_LOGIN", function()
	for _, fn in ipairs(ns.onLogin) do fn() end
end)

-- Settings changes call this so every window re-lays itself out.
ns.windows = {}
function ns.RefreshAll()
	for _, w in pairs(ns.windows) do
		w:SetScale(ns.db.scale)
		w:RequestLayout()
	end
end
