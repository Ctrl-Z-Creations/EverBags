-- EverBags window: the shared frame, sections and layout used by both the
-- bags window and the bank window.
local ADDON, ns = ...

local BUTTON_SIZE = 37
local SPACING = 2             -- between item slots
local PADDING = 14            -- frame edge to item grid
local HEADER_HEIGHT = 18
local SECTION_GAP = 8         -- between rows of sections
local SECTION_HGAP = 14       -- between sections sharing a row
local INSET_TOP = 58          -- where the textured background starts
local CONTENT_TOP = INSET_TOP + 8
local BOTTOM_OFFSET = 32
local MIN_CONTENT_WIDTH = 300
local WORTH_GAP = 5           -- space between the last row of slots and "Bag Worth"
local WORTH_LINE = 12         -- height of the "Bag Worth" line

------------------------------------------------------------------------
-- Categories
------------------------------------------------------------------------
ns.CATEGORY_ORDER = { "Quest", "Equipment", "Consumables", "Trade Goods",
	"Recipes", "Miscellaneous", "Junk", "Keys", "Empty" }
local CATEGORY_INDEX = {}
for i, name in ipairs(ns.CATEGORY_ORDER) do CATEGORY_INDEX[name] = i end
CATEGORY_INDEX.All = 0

local C = ns.CLASS
local CLASS_TO_CATEGORY = {
	[C.Weapon] = "Equipment",
	[C.Armor] = "Equipment",
	[C.Consumable] = "Consumables",
	[C.Tradegoods] = "Trade Goods",
	[C.Reagent] = "Trade Goods",
	[C.Gem] = "Trade Goods",
	[C.Recipe] = "Recipes",
	[C.Questitem] = "Quest",
	[C.Key] = "Keys",
}

-- ignoreView: return the item's real category even in All Slots view.
function ns.GetCategory(bag, info, questInfo, ignoreView)
	if bag == ns.KEYRING then return "Keys" end
	if not ns.db.categorize and not ignoreView then return "All" end
	if not info then return "Empty" end
	if questInfo and (questInfo.isQuestItem or questInfo.questID) then return "Quest" end
	if info.quality == ns.QUALITY.Poor then return "Junk" end
	return CLASS_TO_CATEGORY[ns.GetItemBasics(info.itemID).classID] or "Miscellaneous"
end

------------------------------------------------------------------------
-- Shared search box text across windows
------------------------------------------------------------------------
local syncingSearch = false
local function OnSearchChanged(box)
	if syncingSearch then return end
	local text = box:GetText() or ""
	ns.SetSearch(text)
	syncingSearch = true
	for _, w in pairs(ns.windows) do
		if w.SearchBox ~= box and w.SearchBox:GetText() ~= text then
			w.SearchBox:SetText(text)
		end
		-- A search in progress keeps every window's search box open.
		if text ~= "" then
			w:OpenSearch(false)
		elseif not w.SearchBox:HasFocus() then
			w:CloseSearch()
		end
		w:ApplySearch()
	end
	syncingSearch = false
end

------------------------------------------------------------------------
-- Button overlays (item level, free-slot count)
------------------------------------------------------------------------
-- Item level: the number in the top-left corner, in the item's quality color.
-- (Blizzard's quality border already colors the slot edge for green and up.)
local function QualityColor(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function SetItemLevelText(b, info)
	local ilvl = ns.db.showItemLevel and ns.GetItemLevel(info)
	if not ilvl then
		if b.EverBagsLevel then b.EverBagsLevel:Hide() end
		return
	end
	if not b.EverBagsLevel then
		b.EverBagsLevel = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		b.EverBagsLevel:SetDrawLayer("OVERLAY", 7)
		b.EverBagsLevel:SetPoint("TOPLEFT", 2, -2)
		b.EverBagsLevel:SetShadowColor(0, 0, 0, 1)
		b.EverBagsLevel:SetShadowOffset(1, -1)
	end
	b.EverBagsLevel:SetTextColor(QualityColor(info.quality))
	b.EverBagsLevel:SetText(ilvl)
	b.EverBagsLevel:Show()
end

-- Coin in the top-right corner of sellable junk (Blizzard's own "bags-junkcoin" art).
local JUNK_COIN_SIZE = 11
local function SetJunkCoin(b, info)
	local show = ns.db.showJunkCoin and info and info.quality == ns.QUALITY.Poor and not info.hasNoValue
	if not show then
		if b.EverBagsJunk then b.EverBagsJunk:Hide() end
		return
	end
	if not b.EverBagsJunk then
		b.EverBagsJunk = b:CreateTexture(nil, "OVERLAY", nil, 2)
		b.EverBagsJunk:SetAtlas("bags-junkcoin")
		b.EverBagsJunk:SetSize(JUNK_COIN_SIZE, JUNK_COIN_SIZE)
		b.EverBagsJunk:SetPoint("TOPRIGHT", -2, -2)
	end
	b.EverBagsJunk:Show()
end

-- Suggested drops: a pulsing red glow, like the new-item glow but red, so the
-- two are never confused (green, blue, purple and orange mean quality; white means new).
local function SetSuggestGlow(b, on)
	if not on then
		if b.EverBagsGlow then
			b.EverBagsGlowAnim:Stop()
			b.EverBagsGlow:Hide()
		end
		return
	end
	if not b.EverBagsGlow then
		local glow = b:CreateTexture(nil, "OVERLAY", nil, 3)
		glow:SetAtlas("bags-glow-white")
		glow:SetVertexColor(1, 0.15, 0.1)
		glow:SetBlendMode("ADD")
		glow:SetPoint("TOPLEFT", -2, 2)
		glow:SetPoint("BOTTOMRIGHT", 2, -2)
		local ag = glow:CreateAnimationGroup()
		local fade = ag:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.25)
		fade:SetDuration(0.6)
		ag:SetLooping("BOUNCE")
		b.EverBagsGlow, b.EverBagsGlowAnim = glow, ag
	end
	b.EverBagsGlow:Show()
	if not b.EverBagsGlowAnim:IsPlaying() then b.EverBagsGlowAnim:Play() end
end

local function SetFreeCountText(b, count)
	if not count then
		if b.EverBagsFree then b.EverBagsFree:Hide() end
		return
	end
	if not b.EverBagsFree then
		b.EverBagsFree = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.EverBagsFree:SetPoint("BOTTOMRIGHT", -3, 3)
	end
	b.EverBagsFree:SetText(count)
	b.EverBagsFree:Show()
end

-- Reagent bag slots get a thin green inner border so they read as their own bag.
local function SetReagentTint(b, on)
	if not on then
		if b.EverBagsReagent then for _, t in ipairs(b.EverBagsReagent) do t:Hide() end end
		return
	end
	if not b.EverBagsReagent then
		b.EverBagsReagent = {}
		local function edge(p1, x1, y1, p2, x2, y2, w, h)
			local t = b:CreateTexture(nil, "OVERLAY", nil, 1)
			t:SetColorTexture(0.35, 0.85, 0.45, 0.55)
			t:SetPoint(p1, x1, y1)
			t:SetPoint(p2, x2, y2)
			if w then t:SetWidth(w) else t:SetHeight(h) end
			table.insert(b.EverBagsReagent, t)
		end
		edge("TOPLEFT", 1, -1, "TOPRIGHT", -1, -1, nil, 1)
		edge("BOTTOMLEFT", 1, 1, "BOTTOMRIGHT", -1, 1, nil, 1)
		edge("TOPLEFT", 1, -1, "BOTTOMLEFT", 1, 1, 1)
		edge("TOPRIGHT", -1, -1, "BOTTOMRIGHT", -1, 1, 1)
	end
	for _, t in ipairs(b.EverBagsReagent) do t:Show() end
end
ns.SetReagentTint = SetReagentTint

------------------------------------------------------------------------
-- Window methods
------------------------------------------------------------------------
local Window = {}

function Window:GetButton(bag, slot)
	self.buttons[bag] = self.buttons[bag] or {}
	local b = self.buttons[bag][slot]
	if not b then
		b = self.opts.CreateButton(self, bag, slot)
		self.buttons[bag][slot] = b
	end
	return b
end

-- Read-only item buttons for snapshots (another character, or your bank away
-- from a banker). Plain item buttons: hovering shows the item, shift-click links
-- it, and nothing can be used or moved.
function Window:GetViewButton(bag, slot)
	self.viewButtons[bag] = self.viewButtons[bag] or {}
	local b = self.viewButtons[bag][slot]
	if not b then
		b = CreateFrame("ItemButton", nil, self.Content)
		b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		-- Same empty-slot art as Blizzard's bag buttons (SetItemButtonTexture asks
		-- the button for it when a slot is empty).
		b.emptyBackgroundAtlas = "bags-item-slot64"
		b.GetItemButtonBackgroundTexture = function() return "bags-item-slot64", true end
		b:SetScript("OnEnter", function(btn)
			if not btn.link then return end
			GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(btn.link)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", function(btn)
			if btn.link then HandleModifiedItemClick(btn.link) end
		end)
		self.viewButtons[bag][slot] = b
	end
	return b
end

local function UpdateViewButton(b, info)
	b.link = info and info.hyperlink
	SetItemButtonTexture(b, info and info.iconFileID)
	SetItemButtonCount(b, info and info.stackCount)
	SetItemButtonQuality(b, info and info.quality, info and info.hyperlink)
	SetItemButtonDesaturated(b, false)
end

-- Section header: small gold text with a thin line under it. Click to collapse.
function Window:GetHeader(i)
	local h = self.headers[i]
	if not h then
		h = CreateFrame("Button", nil, self.Content)
		h:SetHeight(HEADER_HEIGHT - 2)
		h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.Text:SetPoint("LEFT", 0, 1)
		h.Text:SetJustifyH("LEFT")
		h.Line = h:CreateTexture(nil, "ARTWORK")
		h.Line:SetColorTexture(0.72, 0.57, 0.29, 0.45)
		h.Line:SetHeight(1)
		h.Line:SetPoint("BOTTOMLEFT", 0, 1)
		h.Line:SetPoint("BOTTOMRIGHT", 0, 1)
		local window = self
		h:SetScript("OnClick", function(btn)
			local collapsed = ns.db.collapsed[window.key]
			collapsed[btn.category] = not collapsed[btn.category] or nil
			window:Layout()
		end)
		h:SetScript("OnEnter", function(btn)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText(btn.category, 1, 1, 1)
			if btn.valueText and btn.valueText ~= "" then GameTooltip:AddLine("Worth " .. btn.valueText) end
			GameTooltip:AddLine(ns.db.collapsed[window.key][btn.category] and "Click to expand." or "Click to collapse.", 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", GameTooltip_Hide)
		self.headers[i] = h
	end
	return h
end

function Window:RequestLayout()
	self.dirty = true
	if self:IsShown() and not self.pending then
		self.pending = true
		C_Timer.After(0, function()
			self.pending = false
			if self:IsShown() and self.dirty then self:Layout() end
		end)
	end
end

local EMPTY_QUEST = {}
local function SortEntries(a, b)
	local qa = a.info and a.info.quality or -1
	local qb = b.info and b.info.quality or -1
	if qa ~= qb then return qa > qb end
	local na, nb = a.name, b.name
	if na ~= nb then return na < nb end
	if a.bag ~= b.bag then return a.bag < b.bag end
	return a.slot < b.slot
end

function Window:Layout()
	self.dirty = false
	local db = ns.db
	local tooltipOwner = GameTooltip:GetOwner()
	local sections, free, total, reagentFree, reagentTotal = {}, 0, 0, 0, 0
	local searching = ns.HasSearch()

	for _, pool in ipairs({ self.buttons, self.viewButtons }) do
		for _, slots in pairs(pool) do
			for _, b in pairs(slots) do b:Hide() end
		end
	end
	-- A snapshot (read-only) or the live bags.
	local snap = self.opts.GetSnapshot and self.opts.GetSnapshot(self) or nil
	self.snapshot = snap
	for _, h in ipairs(self.headers) do h:Hide() end

	-- Gather every slot into its section ("All" in All Slots view, plus Keys).
	local itemEntries, worth = {}, 0
	local bagList = snap and snap.bagList or (self.opts.GetBags(self))
	for _, bag in ipairs(bagList) do
		for slot = 1, (snap and snap:NumSlots(bag) or ns.GetNumSlots(bag)) do
			local info, questInfo, b
			if snap then
				info = snap:Info(bag, slot)
				questInfo = info and info.questInfo or EMPTY_QUEST
				b = self:GetViewButton(bag, slot)
				UpdateViewButton(b, info)
			else
				info = C_Container.GetContainerItemInfo(bag, slot)
				questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
				b = self:GetButton(bag, slot)
				self.opts.UpdateButton(self, b, bag, slot, info, questInfo, tooltipOwner)
			end
			SetItemLevelText(b, info)
			SetJunkCoin(b, info)
			SetFreeCountText(b, nil)
			SetSuggestGlow(b, false)
			SetReagentTint(b, ns.IsReagentBag(bag))
			local match = ns.MatchesSearch(info, bag, slot)
			b:SetMatchesSearch(match)

			local value = ns.GetSlotValue(info)
			if not snap then ns.SetSlotNote(bag, slot, nil) end

			local cat = ns.GetCategory(bag, info, questInfo)
			local section = sections[cat]
			if not section then
				section = { name = cat, entries = {}, value = 0, matches = 0 }
				sections[cat] = section
			end
			local entry = {
				button = b, bag = bag, slot = slot, info = info, questInfo = questInfo,
				name = ns.GetItemName(info), value = value,
			}
			table.insert(section.entries, entry)
			section.value = section.value + (value or 0)
			if match and info then section.matches = section.matches + 1 end
			worth = worth + (value or 0)
			if info then table.insert(itemEntries, entry) end
			if ns.IsReagentBag(bag) then
				reagentTotal = reagentTotal + 1
				if not info then reagentFree = reagentFree + 1 end
			elseif bag ~= ns.KEYRING then
				total = total + 1
				if not info then free = free + 1 end
			end
		end
	end

	-- Suggested drops glow red while the free-slot count is toggled on.
	self.suggestedCount = 0
	if self.opts.suggestDrops and db.suggestDrops and ns.showSuggestions and not snap then
		for _, e in ipairs(ns.PickSuggestions(itemEntries, db.suggestCount)) do
			SetSuggestGlow(e.button, true)
			self.suggestedCount = self.suggestedCount + 1
			local worthText = (e.value or 0) > 0 and ("worth " .. ns.FormatMoney(e.value)) or "no vendor value"
			ns.SetSlotNote(e.bag, e.slot, "Suggested drop: one of the items worth the least (" .. worthText .. ").")
		end
	end

	-- While searching in Categories view, sections with no matches disappear.
	local ordered = {}
	for _, section in pairs(sections) do
		local visible = #section.entries > 0
		if visible and searching and db.categorize and section.matches == 0 then visible = false end
		if visible then table.insert(ordered, section) end
	end
	table.sort(ordered, function(a, b) return CATEGORY_INDEX[a.name] < CATEGORY_INDEX[b.name] end)

	local cols = db[self.opts.columnsKey]
	local step = BUTTON_SIZE + SPACING
	local contentWidth = math.max(cols * step - SPACING, MIN_CONTENT_WIDTH)
	local collapsed = db.collapsed[self.key]
	-- "Bag Worth" sits under the bag slots (never under the keyring).
	local showWorth = db.showValues and worth > 0
	-- gridBottom/gridRight: the bottom-right corner of the lowest row of bag slots.
	local x, y, rowHeight, headerCount, gridRight, gridBottom = 0, 0, 0, 0, 0, 0

	-- Sections flow left to right and share a row when they fit.
	for _, section in ipairs(ordered) do
		local entries = section.entries
		if section.name ~= "All" then table.sort(entries, SortEntries) end

		-- Compact free slots: one empty slot with a count on it, plus one for the
		-- reagent bag (its slots only take reagents, so they're counted apart).
		if section.name == "Empty" and db.compactEmpty and #entries > 1 then
			local regular, reagent = {}, {}
			for _, e in ipairs(entries) do
				table.insert(ns.IsReagentBag(e.bag) and reagent or regular, e)
			end
			local keep = regular[1]
			for _, e in ipairs(regular) do
				if e.bag <= ns.NUM_BAG_SLOTS and e.bag >= ns.BACKPACK then keep = e break end
			end
			entries = {}
			if keep then SetFreeCountText(keep.button, #regular); table.insert(entries, keep) end
			if reagent[1] then SetFreeCountText(reagent[1].button, #reagent); table.insert(entries, reagent[1]) end
		end

		local showHeader = section.name ~= "All"
		local isCollapsed = showHeader and collapsed[section.name]
		local h, headerWidth = nil, 0
		if showHeader then
			headerCount = headerCount + 1
			h = self:GetHeader(headerCount)
			h.category = section.name
			h.valueText = db.showValues and ns.FormatMoney(section.value) or ""
			local label = isCollapsed and ("|cff9a8a6a+ " .. section.name .. "|r") or section.name
			h.Text:SetFormattedText("%s |cff8f8578%d|r", label, #section.entries)
			h.Line:SetShown(not isCollapsed)
			headerWidth = h.Text:GetStringWidth() + 4
		end

		local count = isCollapsed and 0 or #entries
		local itemCols = math.min(count, cols)
		local itemsWidth = itemCols > 0 and (itemCols * step - SPACING) or 0
		local width = math.min(math.max(itemsWidth, headerWidth), contentWidth)
		local rows = math.ceil(count / cols)
		local height = (showHeader and HEADER_HEIGHT or 0) + rows * step

		if x > 0 and x + width > contentWidth then
			-- The keyring starting a row of its own drops a little, clear of "Bag Worth".
			local extra = (showWorth and section.name == "Keys") and (WORTH_GAP + WORTH_LINE - SECTION_GAP + 4) or 0
			x, y, rowHeight = 0, y + rowHeight + SECTION_GAP + extra, 0
		end

		if h then
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", self.Content, "TOPLEFT", x, -y)
			h:SetWidth(width)
			h:Show()
		end
		local top = y + (showHeader and HEADER_HEIGHT or 0)
		for i = 1, count do
			local b = entries[i].button
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.Content, "TOPLEFT", x + col * step, -(top + row * step))
			b:Show()
		end

		if count > 0 and section.name ~= "Keys" then
			local bottom = top + rows * step - SPACING
			if bottom > gridBottom then
				gridBottom, gridRight = bottom, x + itemsWidth
			elseif bottom == gridBottom then
				gridRight = math.max(gridRight, x + itemsWidth)
			end
		end
		rowHeight = math.max(rowHeight, height)
		x = x + width + SECTION_HGAP
	end
	local contentHeight = y + rowHeight
	-- Room for the small "Bag Worth" line under the last row of slots.
	if showWorth then contentHeight = math.max(contentHeight, gridBottom + WORTH_GAP + WORTH_LINE) end

	self:SetSize(contentWidth + PADDING * 2, math.max(contentHeight, step) + CONTENT_TOP + BOTTOM_OFFSET + 4)
	if reagentTotal > 0 then
		self.FreeText:SetFormattedText("%d / %d free  |cff66cc77%d reagent|r", free, total, reagentFree)
	else
		self.FreeText:SetFormattedText("%d / %d free", free, total)
	end
	self.reagentFree, self.reagentTotal = reagentFree, reagentTotal
	-- The free-slot count turns red when bags are nearly full (a hint to click it).
	local nearlyFull = self.opts.suggestDrops and db.suggestDrops and free <= db.lowSpaceThreshold and not snap
	if ns.showSuggestions and self.opts.suggestDrops and not snap then
		self.FreeText:SetTextColor(1, 0.35, 0.3)
	elseif nearlyFull then
		self.FreeText:SetTextColor(1, 0.25, 0.2)
	else
		self.FreeText:SetTextColor(1, 0.82, 0)
	end
	self.FreeButton:SetWidth(self.FreeText:GetStringWidth() + 4)
	-- "Bag Worth 12g 40s": small, tucked under the grid's bottom-right corner.
	self.WorthText:SetText(showWorth
		and ("|cffffd100" .. (self.opts.worthLabel or "Worth") .. "|r  " .. ns.FormatMoney(worth)) or "")
	self.WorthText:ClearAllPoints()
	self.WorthText:SetPoint("TOPRIGHT", self.Content, "TOPLEFT", gridRight, -(gridBottom + WORTH_GAP))
	self.worth = worth
	self:UpdateControls()
	if self.opts.OnLayout then self.opts.OnLayout(self) end
end

-- Keeps the view button, orbit buttons, side tabs and title in step with the state.
function Window:UpdateControls()
	local categories = ns.db.categorize
	self.ViewButton.GridGlyph:SetShown(categories)   -- shows the view you'd switch to
	self.ViewButton.ListGlyph:SetShown(not categories)
	-- Sort only changes what you see in All Slots view.
	local sortOrbit, deposit = rawget(self, "SortOrbit"), rawget(self, "DepositButton")
	local snap = rawget(self, "snapshot")
	-- Snapshots are read-only: no Sort or Stack.
	if sortOrbit then sortOrbit:SetShown(not categories and not snap) end
	self.StackOrbit:SetShown(not snap)
	if deposit then ns.UpdateDepositButton(deposit) end
	self:UpdateCharacterName()
	self:UpdateTitle()
	for _, t in ipairs(self.SideTabs) do
		t:SetChecked(t.target == self.key)
		local available = t.target == self.key or not t.IsAvailable or t.IsAvailable()
		t.Icon:SetDesaturated(not available)
	end
	self:ApplyArtStyle()
end

-- Title: "<Name>'s <word>", with the word chosen in settings. Hidden while
-- the search box sits in the title bar.
function Window:UpdateTitle()
	local word = (self.opts.titleKey and ns.db and ns.db[self.opts.titleKey]) or self.opts.title
	local snap = rawget(self, "snapshot")
	local name = (ns.IsViewingOther() and ns.CharacterLabel(ns.viewKey, true)) or (snap and snap.name) or ns.PlayerName()
	local text = self.searchOpen and "" or (name and (name .. "'s " .. word) or word)
	-- Snapshots say how old they are: "Thrall's Bank · saved 2 hr ago".
	if text ~= "" and snap then
		text = text .. " |cffa0a0a0· " .. (snap.time and ("saved " .. ns.Ago(snap.time)) or "not saved yet") .. "|r"
	end
	if self.SetTitle then self:SetTitle(text) elseif self.TitleText then self.TitleText:SetText(text) end
end

-- Search in the title bar: the magnifying glass swaps the title for a search box.
function Window:OpenSearch(focus)
	if not self.searchOpen then
		self.searchOpen = true
		self.SearchBox:Show()
		self:UpdateTitle()
	end
	if focus then self.SearchBox:SetFocus() end
end

function Window:CloseSearch()
	if not self.searchOpen or (self.SearchBox:GetText() or "") ~= "" then return end
	self.searchOpen = false
	self.SearchBox:Hide()
	self:UpdateTitle()
end

function Window:UpdateCharacterName()
	local dd = self.CharacterDropdown
	local name = ns.IsViewingOther() and ns.CharacterLabel(ns.viewKey, true) or ns.PlayerName()
	if not dd or not name then return end
	if dd.OverrideText then
		dd:OverrideText(name)
	elseif dd.SetText then
		dd:SetText(name)
	end
end

-- The textured background can be switched off in settings (plain dark inset instead).
local BACKGROUND_ART = { "BackgroundTile", "ShadowCornerTopLeft", "ShadowCornerTopRight",
	"ShadowCornerBottomLeft", "ShadowCornerBottomRight", "ShadowCornerTop", "ShadowCornerLeft",
	"ShadowCornerRight", "ShadowCornerBottom", "OverlayShadowTopLeft", "OverlayShadowTopRight",
	"OverlayShadowBottomLeft", "OverlayShadowBottomRight", "OverlayShadowTop", "OverlayShadowLeft",
	"OverlayShadowRight", "OverlayShadowBottom" }

function Window:ApplyArtStyle()
	local on = ns.db.foreverArt
	for _, key in ipairs(BACKGROUND_ART) do
		local tex = rawget(self.Inset, key)
		if type(tex) == "table" and tex.SetShown then tex:SetShown(on) end
	end
end

function Window:ApplySearch()
	if not self:IsShown() then return end
	if ns.db.categorize or rawget(self, "snapshot") then
		self:Layout() -- sections without matches come and go
		return
	end
	for bag, slots in pairs(self.buttons) do
		for slot, b in pairs(slots) do
			if b:IsShown() then
				b:SetMatchesSearch(ns.MatchesSearch(C_Container.GetContainerItemInfo(bag, slot), bag, slot))
			end
		end
	end
end

function Window:UpdateLocks()
	for bag, slots in pairs(self.buttons) do
		for slot, b in pairs(slots) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			SetItemButtonDesaturated(b, info and info.isLocked)
		end
	end
end

function Window:UpdateCooldowns()
	for bag, slots in pairs(self.buttons) do
		for slot, b in pairs(slots) do
			if b:IsShown() and b.UpdateCooldown then
				b:UpdateCooldown(C_Container.HasContainerItem(bag, slot))
			end
		end
	end
end

function Window:HasBag(bag)
	return self.buttons[bag] ~= nil
end

function Window:RestorePosition()
	self:ClearAllPoints()
	local p = ns.db.points[self.key]
	if p then
		self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		local d = self.opts.defaultPoint
		self:SetPoint(d[1], UIParent, d[2], d[3], d[4])
	end
end

------------------------------------------------------------------------
-- Constructor pieces
------------------------------------------------------------------------
local function ToolbarButton(parent, label, width, tooltip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b.tooltip = tooltip
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label, 1, 1, 1)
		GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Minimap-style round buttons orbiting the portrait (classic minimap button art).
local function CreateOrbitButton(window, icon, tooltipTitle, tooltipText, onClick)
	local b = CreateFrame("Button", nil, window)
	b:SetSize(31, 31)
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetTexture(icon)
	b.Icon:SetSize(17, 17)
	b.Icon:SetPoint("TOPLEFT", 7, -6)
	b.Icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(tooltipTitle, 1, 1, 1)
		GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Places an orbit button on a circle around the portrait (angle in degrees,
-- 0 = right, 90 = straight up).
-- 40 px from the portrait's center hugs its rim; buttons sit 50 degrees apart
-- so they don't overlap at that distance.
local ORBIT_RADIUS = 40
local function PlaceOnOrbit(window, b, angle)
	local anchor = window.GetPortrait and window:GetPortrait() or window
	local rad = math.rad(angle)
	b:ClearAllPoints()
	if anchor == window then
		b:SetPoint("CENTER", window, "TOPLEFT", 25 + ORBIT_RADIUS * math.cos(rad), -25 + ORBIT_RADIUS * math.sin(rad))
	else
		b:SetPoint("CENTER", anchor, "CENTER", ORBIT_RADIUS * math.cos(rad), ORBIT_RADIUS * math.sin(rad))
	end
end

-- One view button: its icon shows the view you'd switch to.
local function DrawGlyph(button, parts)
	local glyph = CreateFrame("Frame", nil, button)
	glyph:SetSize(12, 12)
	glyph:SetPoint("CENTER", 0, 0)
	for _, p in ipairs(parts) do
		local t = glyph:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 0.82, 0.2, 1)
		t:SetSize(p[3], p[4])
		t:SetPoint("TOPLEFT", p[1], -p[2])
	end
	return glyph
end

local function CreateViewButton(window)
	local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	b:SetSize(26, 22)
	b:SetText("")
	-- 2x2 grid of squares = All Slots; three header bars = Categories.
	b.GridGlyph = DrawGlyph(b, { { 0, 0, 5, 5 }, { 7, 0, 5, 5 }, { 0, 7, 5, 5 }, { 7, 7, 5, 5 } })
	b.ListGlyph = DrawGlyph(b, { { 0, 0, 12, 2 }, { 0, 5, 12, 2 }, { 0, 10, 12, 2 } })
	b:SetScript("OnClick", function()
		ns.PlaySound("IG_CHARACTER_INFO_TAB")
		ns.db.categorize = not ns.db.categorize
		ns.RefreshAll()
		if b:IsMouseOver() and b:GetScript("OnEnter") then b:GetScript("OnEnter")(b) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if ns.db.categorize then
			GameTooltip:SetText("Switch to All Slots", 1, 1, 1)
			GameTooltip:AddLine("Every slot in bag order, in one grid.", nil, nil, nil, true)
		else
			GameTooltip:SetText("Switch to Categories", 1, 1, 1)
			GameTooltip:AddLine("Items grouped by type, in sections.", nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Characters dropdown: every character with saved bags. Picking another one
-- shows its bags and bank read-only.
local function CharacterName()
	return ns.PlayerName() or "You"
end

local function CreateCharacterDropdown(window)
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetWidth(130)
		dd:SetupMenu(function(_, root)
			root:CreateTitle("Characters")
			local keys = ns.CharacterKeys()
			if #keys == 0 then
				local me = CharacterName()
				root:CreateRadio(me, function() return true end, function() end, me)
				return
			end
			local isSelected = function(key) return key == ns.ViewKey() end
			local setSelected = function(key) ns.SetViewCharacter(key) end
			for _, key in ipairs(keys) do
				root:CreateRadio(ns.CharacterLabel(key), isSelected, setSelected, key)
			end
			if #keys > 1 and root.CreateDivider then
				root:CreateDivider()
				local forget = root:CreateButton("Remove a character")
				for _, key in ipairs(keys) do
					if key ~= ns.MyKey() then
						forget:CreateButton(ns.CharacterLabel(key), function()
							ns.ForgetCharacter(key)
							ns.Print("removed " .. ns.CharacterLabel(key, true) .. "'s saved bags. Logging in on that character saves them again.")
						end)
					end
				end
			end
		end)
		return dd
	end
	-- Fallback: a plain button showing the character's name.
	local b = ToolbarButton(window, CharacterName(), 130, "Your characters.")
	return b
end

-- Side tabs (Bags / Bank) on the window's right edge, like the Collections side tabs.
local SIDE_TABS = {
	{ target = "bags", icon = "Interface\\Icons\\INV_Misc_Bag_08", tooltip = "Bags" },
	{ target = "bank", icon = "Interface\\ICONS\\INV_SideTab_Bank_c60", tooltip = "Bank" },
}

local function CreateSideTabs(window)
	window.SideTabs = {}
	local last
	for _, info in ipairs(SIDE_TABS) do
		local ok, t = pcall(CreateFrame, "Frame", nil, window, "LargeSideTabButtonTemplate")
		if ok and t and t.Icon then
			t.target = info.target
			t.tooltipText = info.tooltip
			t.Icon:SetTexture(info.icon)
			if t.SetFillToInterior then t:SetFillToInterior(true) end
			if last then
				t:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
			else
				t:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -INSET_TOP)
			end
			t:SetCustomOnMouseUpHandler(function(tab, button, upInside)
				if button == "LeftButton" and upInside then ns.ShowWindow(tab.target, window) end
			end)
			t.IsAvailable = function() return ns.CanShowWindow(t.target) end
			table.insert(window.SideTabs, t)
			last = t
		end
	end
end

-- Hook for the side tabs; Bags.lua / Bank.lua fill these in.
ns.windowOpeners = {}
function ns.CanShowWindow(key)
	local opener = ns.windowOpeners[key]
	return opener ~= nil and opener.CanShow()
end
function ns.ShowWindow(key, from)
	local target = ns.windows[key]
	if not target then return end
	if target:IsShown() then
		target:Raise()
		return
	end
	local opener = ns.windowOpeners[key]
	if opener and opener.CanShow() then
		opener.Show()
	elseif opener and opener.unavailable then
		ns.Print(opener.unavailable)
	end
end

------------------------------------------------------------------------
-- Constructor
------------------------------------------------------------------------
-- opts: title, titleKey, columnsKey, defaultPoint, portrait, GetBags(window), Sort(),
--       CreateButton(window, bag, slot),
--       UpdateButton(window, button, bag, slot, info, questInfo, tooltipOwner),
--       suggestDrops, OnLayout
function ns.CreateWindow(key, opts)
	local name = "EverBags" .. key:gsub("^%l", string.upper) .. "Frame"
	-- The same frame Blizzard uses for the Collections window (portrait, gold title, ornate border).
	local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
	if not ok or not f then
		f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
	end
	for k, v in pairs(Window) do f[k] = v end
	f.key, f.opts = key, opts
	f.buttons, f.viewButtons, f.headers = {}, {}, {}
	f.dirty = true

	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())
	if f.SetTitle then f:SetTitle(opts.title) elseif f.TitleText then f.TitleText:SetText(opts.title) end
	if opts.portrait and f.SetPortraitToAsset then f:SetPortraitToAsset(opts.portrait) end

	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.points[self.key] = { point, relPoint, x, y }
	end)

	-- Textured background from the Appearances screen, without its filigree corners.
	local okInset, inset = pcall(CreateFrame, "Frame", nil, f, "CollectionsBackgroundTemplate")
	if not okInset or not inset then
		inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	end
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
	inset:SetPoint("BOTTOMRIGHT", -6, 5)
	for _, corner in ipairs({ "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }) do
		local tex = rawget(inset, corner)
		if type(tex) == "table" and tex.Hide then tex:Hide() end
	end
	f.Inset = inset

	-- Keep the orbit buttons on screen even when the window is pushed into a corner.
	if f.SetClampRectInsets then f:SetClampRectInsets(-48, 0, 46, 0) end

	-- Orbit buttons around the portrait: Sort (All Slots view only), Stack, Settings.
	if opts.Sort then
		f.SortOrbit = CreateOrbitButton(f, "Interface\\Icons\\INV_Misc_Bag_10", "Sort",
			"Blizzard's bag cleanup: groups similar items, merges stacks and gathers empty slots at the end.",
			function()
				if InCombatLockdown() then return end
				ns.PlaySound("UI_BAG_SORTING_01")
				opts.Sort()
			end)
		PlaceOnOrbit(f, f.SortOrbit, 105)
	end
	f.StackOrbit = CreateOrbitButton(f, "Interface\\Icons\\INV_Misc_Coin_02", "Stack",
		"Merge partial stacks of the same item, without moving anything else.",
		function()
			local bags = {}
			for _, bag in ipairs(opts.GetBags(f)) do
				if bag ~= ns.KEYRING then table.insert(bags, bag) end
			end
			ns.StackBags(bags)
		end)
	PlaceOnOrbit(f, f.StackOrbit, 155)
	f.SettingsOrbit = CreateOrbitButton(f, "Interface\\Icons\\INV_Misc_Gear_01", "Settings",
		"Open the EverBags settings.", function() ns.OpenSettings() end)
	PlaceOnOrbit(f, f.SettingsOrbit, 205)

	-- Under the title bar: the view button and the Characters dropdown.
	f.CharacterDropdown = CreateCharacterDropdown(f)
	f.CharacterDropdown:SetPoint("TOPRIGHT", -12, -31)
	f.ViewButton = CreateViewButton(f)
	f.ViewButton:SetPoint("RIGHT", f.CharacterDropdown, "LEFT", -6, 0)

	-- Search lives in the title bar: the magnifying glass swaps the title for a search box.
	f.SearchButton = CreateFrame("Button", nil, f)
	f.SearchButton:SetSize(18, 18)
	-- Left end of the title bar, next to the portrait, well away from the close button.
	f.SearchButton:SetPoint("TOPLEFT", 60, -3)
	local glass = f.SearchButton:CreateTexture(nil, "ARTWORK")
	glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	glass:SetSize(14, 14)
	glass:SetPoint("CENTER")
	glass:SetVertexColor(1, 0.82, 0.2)
	f.SearchButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	f.SearchButton:SetScript("OnClick", function()
		if f.searchOpen and (f.SearchBox:GetText() or "") == "" then
			f.SearchBox:ClearFocus()
			f:CloseSearch()
		else
			f:OpenSearch(true)
		end
	end)
	f.SearchButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Search", 1, 1, 1)
		GameTooltip:AddLine("Item names, or words like armor, potion, food, water, junk, quest, boe, ilvl>50.", nil, nil, nil, true)
		GameTooltip:AddLine("Commas mean \"or\": potion, food", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	f.SearchButton:SetScript("OnLeave", GameTooltip_Hide)

	f.SearchBox = CreateFrame("EditBox", name .. "Search", f, "SearchBoxTemplate")
	f.SearchBox:SetHeight(20)
	-- Same text size as the window title, for legibility.
	f.SearchBox:SetFontObject("GameFontHighlight")
	f.SearchBox:SetPoint("LEFT", f.SearchButton, "RIGHT", 6, 0)
	f.SearchBox:SetPoint("TOPRIGHT", -30, -2)
	f.SearchBox:Hide()
	if f.SearchBox.Instructions then
		f.SearchBox.Instructions:SetFontObject("GameFontDisable")
		f.SearchBox.Instructions:SetTextColor(0.75, 0.75, 0.75)
		f.SearchBox.Instructions:SetText("Search: name, armor, potion, food...")
	end
	f.SearchBox:HookScript("OnTextChanged", OnSearchChanged)
	f.SearchBox:HookScript("OnEditFocusLost", function() f:CloseSearch() end)

	f.Content = CreateFrame("Frame", nil, f)
	f.Content:SetPoint("TOPLEFT", PADDING, -CONTENT_TOP)
	f.Content:SetPoint("BOTTOMRIGHT", -PADDING, BOTTOM_OFFSET)

	CreateSideTabs(f)

	-- Footer text lives on its own frame so it draws above the background inset.
	f.Footer = CreateFrame("Frame", nil, f)
	f.Footer:SetAllPoints(f)
	f.FreeText = f.Footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.FreeText:SetPoint("BOTTOMLEFT", PADDING + 2, 14)

	-- Clicking the free-slot count shows or hides suggested drops (bags only).
	f.FreeButton = CreateFrame("Button", nil, f)
	f.FreeButton:SetPoint("LEFT", f.FreeText, "LEFT", -2, 0)
	f.FreeButton:SetHeight(16)
	f.FreeButton:SetWidth(80)
	if opts.suggestDrops then
		f.FreeButton:SetScript("OnClick", function()
			ns.showSuggestions = not ns.showSuggestions
			ns.RefreshAll()
		end)
		f.FreeButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Free slots", 1, 1, 1)
			GameTooltip:AddLine(ns.showSuggestions and "Click to stop highlighting suggested drops."
				or "Click to make the items worth the least glow red, as suggested drops.", nil, nil, nil, true)
			local w = self:GetParent()
			if (w.reagentTotal or 0) > 0 then
				GameTooltip:AddLine(("Reagent bag: %d of %d free. Only crafting reagents fit there, so it isn't counted in your free slots."):format(w.reagentFree, w.reagentTotal), 0.4, 0.8, 0.47, true)
			end
			GameTooltip:Show()
		end)
		f.FreeButton:SetScript("OnLeave", GameTooltip_Hide)
	end

	f.WorthText = f.Footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.WorthText:SetPoint("TOPRIGHT", f.Content, "BOTTOMRIGHT", 0, -3)

	-- Everything drawn inside the background sits above it.
	local above = inset:GetFrameLevel() + 2
	for _, child in ipairs({ f.Content, f.Footer, f.FreeButton, f.CharacterDropdown, f.ViewButton }) do
		child:SetFrameLevel(above)
	end
	-- Blizzard's portrait frame draws its title bar at frame level 510 and the
	-- portrait at 400, so anything we place over them has to sit higher.
	local titleLevel = (f.TitleContainer and f.TitleContainer:GetFrameLevel() or f:GetFrameLevel()) + 10
	f.SearchButton:SetFrameLevel(titleLevel)
	f.SearchBox:SetFrameLevel(titleLevel)
	for _, orbit in ipairs({ f.SortOrbit, f.StackOrbit, f.SettingsOrbit }) do
		if orbit then orbit:SetFrameLevel(titleLevel) end
	end

	ns.windows[key] = f
	table.insert(ns.onReady, function()
		ns.db.collapsed[key] = ns.db.collapsed[key] or {}
		f:SetScale(ns.db.scale)
		f:RestorePosition()
		f:UpdateControls()
	end)
	table.insert(ns.onLogin, function()
		f:UpdateCharacterName()
		f:UpdateTitle()
	end)
	return f
end
