-- EverBags settings: a panel in Options > AddOns, plus slash commands.
local ADDON, ns = ...

local category

local function AddCheckbox(key, label, tooltip, onChange)
	local setting = Settings.RegisterProxySetting(category, "EVERBAGS_" .. key:upper(),
		Settings.VarType.Boolean, label, ns.DEFAULTS[key],
		function() return ns.db[key] end,
		function(value)
			ns.db[key] = value
			if onChange then onChange(value) else ns.RefreshAll() end
		end)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(key, label, tooltip, minValue, maxValue, step, formatter)
	local setting = Settings.RegisterProxySetting(category, "EVERBAGS_" .. key:upper(),
		Settings.VarType.Number, label, ns.DEFAULTS[key],
		function() return ns.db[key] end,
		function(value)
			ns.db[key] = value
			ns.RefreshAll()
		end)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	Settings.CreateSlider(category, setting, options, tooltip)
end

local function AddWordDropdown(key, label, tooltip)
	local setting = Settings.RegisterProxySetting(category, "EVERBAGS_" .. key:upper(),
		Settings.VarType.String, label, ns.DEFAULTS[key],
		function() return ns.db[key] end,
		function(value)
			ns.db[key] = value
			for _, w in pairs(ns.windows) do w:UpdateTitle() end
		end)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, word in ipairs(ns.TITLE_WORDS[key]) do container:Add(word, word) end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, GetOptions, tooltip)
end

local DEPOSIT_CHOICES = { "Trade Goods", "Consumables", "Recipes", "Miscellaneous", "Junk", "Equipment" }

local function AddDepositDropdown()
	local setting = Settings.RegisterProxySetting(category, "EVERBAGS_DEPOSITCATEGORY",
		Settings.VarType.String, "Deposit button moves", ns.DEFAULTS.depositCategory,
		function() return ns.db.depositCategory end,
		function(value) ns.db.depositCategory = value end)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, name in ipairs(DEPOSIT_CHOICES) do container:Add(name, name) end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, GetOptions,
		"Which section the Deposit button moves into the bank. With a search active, it moves the items matching your search instead.")
end

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	category = Settings.RegisterVerticalLayoutCategory("EverBags")

	AddWordDropdown("bagTitle", "Bags window title",
		"The word after your character's name, e.g. \"Thrall's Backpack\".")
	AddWordDropdown("bankTitle", "Bank window title",
		"The word after your character's name, e.g. \"Thrall's Bank\".")
	AddSlider("columns", "Bag columns", "How many item slots per row in the bags window.", 6, 24, 1)
	AddSlider("bankColumns", "Bank columns", "How many item slots per row in the bank window.", 8, 30, 1)
	AddSlider("scale", "Scale", "Size of the EverBags windows.", 0.6, 1.5, 0.05,
		function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	AddCheckbox("categorize", "Group items into categories",
		"Same as the view button next to the Characters dropdown. Off shows every slot in one grid.")
	AddCheckbox("foreverArt", "Textured background",
		"The dark textured background from the Appearances screen. Off gives a plain dark background.")
	AddCheckbox("compactEmpty", "Show free slots as one slot",
		"In Categories view, shows a single empty slot with the number of free slots on it.")
	AddCheckbox("showItemLevel", "Show item level on gear")
	AddCheckbox("showJunkCoin", "Show a coin on junk",
		"Marks gray items that can be sold to a vendor.")
	AddCheckbox("showKeyring", "Show the keyring",
		"Adds your keyring as a Keys section in the bags window.")
	AddCheckbox("showValues", "Show what items are worth",
		"Shows the total value of each section and of all your bags.")
	AddCheckbox("useAuctionPrices", "Use auction prices from Auctionator",
		"When Auctionator is installed, uses its auction price if it's higher than the vendor price. Bound items always use the vendor price.")
	AddCheckbox("suggestDrops", "Suggested drops",
		"Click the free-slot count to make the items worth the least glow red. The count turns red when your bags are nearly full.")
	AddSlider("lowSpaceThreshold", "Nearly full at",
		"The free-slot count turns red at this many free slots or fewer.", 0, 12, 1,
		function(v) return ("%d free"):format(v) end)
	AddSlider("suggestCount", "Suggested drops to highlight", nil, 3, 12, 1)
	AddDepositDropdown()
	AddCheckbox("showFarm", "Farming summary",
		"Shows what you've looted (\"+38 items · +5g 32s\") in the bags footer this session: kills, chests, herbs, ore, skins and fishing. Vendors, mail, the auction house, trades and crafting don't count. It starts over when you log in, or when you click it.")
	AddCheckbox("farmQuestGold", "Include quest gold in the farming summary",
		"Adds gold from quest rewards as its own line. Off counts only what you loot.")
	AddCheckbox("tooltipCounts", "Show other characters' items in tooltips",
		"Item tooltips list your characters holding that item, e.g. \"Thrall: 5 in bags, 12 in bank\". Banks are saved when each character visits a banker.")
	AddCheckbox("replaceBank", "Replace the default bank",
		"Takes effect after /reload.", function() end)

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenSettings()
	if category then
		Settings.OpenToCategory(category:GetID())
	else
		ns.Print("the settings panel isn't available; use /eb help.")
	end
end

table.insert(ns.onReady, RegisterSettings)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_EVERBAGS1 = "/everbags"
SLASH_EVERBAGS2 = "/eb"
SlashCmdList.EVERBAGS = function(msg)
	local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
	local n = tonumber(arg)
	if cmd == "" or cmd == "config" or cmd == "options" then
		ns.OpenSettings()
		return
	elseif cmd == "cols" and n then
		ns.db.columns = math.max(6, math.min(24, math.floor(n)))
	elseif cmd == "bankcols" and n then
		ns.db.bankColumns = math.max(8, math.min(30, math.floor(n)))
	elseif cmd == "scale" and n then
		ns.db.scale = math.max(0.6, math.min(1.5, n))
	elseif cmd == "cat" then
		ns.db.categorize = not ns.db.categorize
		ns.Print("categories " .. (ns.db.categorize and "on" or "off"))
	elseif cmd == "reset" then
		wipe(ns.db.points)
		for _, w in pairs(ns.windows) do w:RestorePosition() end
		ns.Print("window positions reset.")
	elseif cmd == "expand" then
		for _, c in pairs(ns.db.collapsed) do wipe(c) end
	else
		ns.Print("v" .. ns.VERSION .. " commands:")
		print("  /eb - open settings")
		print("  /eb cols <n>, bankcols <n>, scale <0.6-1.5>")
		print("  /eb cat - switch between All Slots and Categories")
		print("  /eb expand - expand all collapsed sections")
		print("  /eb reset - reset window positions")
		print("  Search: words, -exclude, commas for 'or', ilvl>50, food, water, potion, epic, boe, head...")
		return
	end
	ns.RefreshAll()
end
