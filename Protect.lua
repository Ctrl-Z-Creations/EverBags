-- EverBags protected items: items you mark "keep".
--
-- Protection is stored per item (item ID), so every copy of a protected item
-- is protected. Protected items show a small lock, are never suggested as
-- drops, and Stack and Deposit leave them alone. (Blizzard's own Sort and
-- Sell All Junk can't be told about them.)
--
-- Protect mode: while it's on, clicking an item toggles its protection instead
-- of using it. The clicks land on plain overlay buttons laid over the item
-- slots, so Blizzard's item buttons are never touched.
local ADDON, ns = ...

ns.protectMode = false

function ns.IsProtected(info)
	return info ~= nil and info.itemID ~= nil and ns.db.protected[info.itemID] == true
end

-- Small lock in the bottom-left corner of protected items.
function ns.SetProtectedIcon(b, info)
	local show = ns.IsProtected(info)
	if not show then
		if b.EverBagsLock then b.EverBagsLock:Hide() end
		return
	end
	if not b.EverBagsLock then
		b.EverBagsLock = b:CreateTexture(nil, "OVERLAY", nil, 4)
		b.EverBagsLock:SetAtlas("LFG-lock")
		b.EverBagsLock:SetSize(12, 14)
		b.EverBagsLock:SetPoint("BOTTOMLEFT", 2, 2)
	end
	b.EverBagsLock:Show()
end

local function ToggleProtect(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then return end
	if ns.db.protected[info.itemID] then
		ns.db.protected[info.itemID] = nil
		ns.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
	else
		ns.db.protected[info.itemID] = true
		ns.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	end
	ns.RefreshAll()
end

-- One transparent click-catcher per visible slot while protect mode is on.
local function GetCatcher(window, i)
	window.catchers = window.catchers or {}
	local c = window.catchers[i]
	if not c then
		c = CreateFrame("Button", nil, window.Content)
		c:SetFrameLevel(window.Content:GetFrameLevel() + 20)
		c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local hl = c:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.25)
		c:SetScript("OnClick", function(self) ToggleProtect(self.bag, self.slot) end)
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(self.bag, self.slot)
			local info = C_Container.GetContainerItemInfo(self.bag, self.slot)
			if info then
				GameTooltip:AddLine(ns.IsProtected(info) and "Click to stop protecting this item."
					or "Click to protect this item.", 1, 0.82, 0, true)
				GameTooltip:Show()
			end
		end)
		c:SetScript("OnLeave", GameTooltip_Hide)
		window.catchers[i] = c
	end
	return c
end

function ns.UpdateProtectCatchers(window)
	local n = 0
	if ns.protectMode then
		for bag, slots in pairs(window.buttons) do
			for slot, b in pairs(slots) do
				if b:IsShown() and C_Container.GetContainerItemInfo(bag, slot) then
					n = n + 1
					local c = GetCatcher(window, n)
					c.bag, c.slot = bag, slot
					c:ClearAllPoints()
					c:SetAllPoints(b)
					c:Show()
				end
			end
		end
	end
	for i = n + 1, #(window.catchers or {}) do window.catchers[i]:Hide() end
end

function ns.SetProtectMode(on)
	ns.protectMode = on and true or false
	if ns.protectMode then
		ns.Print("protect mode: click items to protect them, or click again to unprotect. Click the lock button when you're done.")
	end
	ns.RefreshAll()
end

-- Toolbar button: a lock. Lit while protect mode is on.
function ns.CreateProtectButton(window)
	local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	b:SetSize(26, 22)
	b:SetText("")
	b.Icon = b:CreateTexture(nil, "OVERLAY")
	b.Icon:SetAtlas("LFG-lock")
	b.Icon:SetSize(12, 14)
	b.Icon:SetPoint("CENTER")
	b:SetScript("OnClick", function() ns.SetProtectMode(not ns.protectMode) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Protect items", 1, 1, 1)
		GameTooltip:AddLine(ns.protectMode and "Click to finish protecting items."
			or "Click, then click items you always want to keep. Protected items are never suggested as drops, and Stack and Deposit leave them alone.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

function ns.UpdateProtectButton(b)
	if ns.protectMode then b:LockHighlight() else b:UnlockHighlight() end
end
