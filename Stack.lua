-- EverBags stacking: merges partial stacks of the same item, one move at a time.
--
-- Each move puts an item on the cursor and drops it on another stack. The
-- server locks both slots until the move finishes, so we wait for every lock
-- to clear before planning the next move.
local ADDON, ns = ...

local STEP_DELAY = 0.1     -- seconds between checks
local LOCK_TIMEOUT = 3     -- give up if slots stay locked this long
local MAX_MOVES = 300

local runner = CreateFrame("Frame")
local job

local function MaxStack(itemID)
	local maxStack = select(8, C_Item.GetItemInfo(itemID))
	return tonumber(maxStack)
end

local function AnyLocked(bags)
	for _, bag in ipairs(bags) do
		for slot = 1, ns.GetNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked then return true end
		end
	end
	return false
end

-- Finds one merge: the smallest partial stack onto the largest one.
local function FindMove(bags, tried)
	local partial = {}
	for _, bag in ipairs(bags) do
		for slot = 1, ns.GetNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local maxStack = MaxStack(info.itemID)
				if maxStack and maxStack > 1 and info.stackCount < maxStack then
					partial[info.itemID] = partial[info.itemID] or {}
					table.insert(partial[info.itemID], {
						bag = bag, slot = slot, count = info.stackCount, max = maxStack,
						link = info.hyperlink,
					})
				end
			end
		end
	end

	for _, list in pairs(partial) do
		if #list >= 2 then
			table.sort(list, function(a, b)
				if a.count ~= b.count then return a.count > b.count end
				if a.bag ~= b.bag then return a.bag < b.bag end
				return a.slot < b.slot
			end)
			local dst = list[1]
			for i = #list, 2, -1 do
				local src = list[i]
				-- Same item ID with a different link (e.g. different enchant) may not stack.
				if src.link == dst.link then
					local key = ("%d:%d>%d:%d@%d/%d"):format(src.bag, src.slot, dst.bag, dst.slot, src.count, dst.count)
					if not tried[key] then
						tried[key] = true
						return src, dst, math.min(src.count, dst.max - dst.count)
					end
				end
			end
		end
	end
end

local function Finish(message)
	runner:SetScript("OnUpdate", nil)
	if CursorHasItem() then ClearCursor() end
	if message then ns.Print(message) end
	job = nil
	ns.RefreshAll()
end

local function Step(_, elapsed)
	job.wait = job.wait + elapsed
	if job.wait < STEP_DELAY then return end
	job.idle = job.idle + job.wait
	job.wait = 0

	if InCombatLockdown() then
		Finish("stacking stopped: you entered combat.")
		return
	end

	-- Wait for the last move to settle.
	if CursorHasItem() or AnyLocked(job.bags) then
		if job.idle > LOCK_TIMEOUT then Finish("stacking stopped: items stayed locked.") end
		return
	end

	local src, dst, amount = FindMove(job.bags, job.tried)
	if not src or job.moves >= MAX_MOVES then
		Finish(job.moves > 0 and ("merged %d stack%s."):format(job.moves, job.moves == 1 and "" or "s")
			or "nothing to stack.")
		return
	end

	if amount >= src.count then
		C_Container.PickupContainerItem(src.bag, src.slot)
	else
		C_Container.SplitContainerItem(src.bag, src.slot, amount)
	end
	C_Container.PickupContainerItem(dst.bag, dst.slot)
	job.moves = job.moves + 1
	job.idle = 0
end

function ns.StackBags(bags)
	if job then return end
	if InCombatLockdown() then
		ns.Print("can't stack during combat.")
		return
	end
	if CursorHasItem() then
		ns.Print("put down the item on your cursor first.")
		return
	end
	ns.PlaySound("UI_BAG_SORTING_01")
	job = { bags = bags, tried = {}, moves = 0, wait = STEP_DELAY, idle = 0 }
	runner:SetScript("OnUpdate", Step)
end

function ns.IsStacking()
	return job ~= nil
end
