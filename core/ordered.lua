local utils = require('/logos-library.utils.utils')
local abstract = require('/logos-library.core.abstract')
local standard = require('/logos-library.core.standard')

local get_order = utils.get_order
local new_class = utils.new_class
local table_filter = utils.table_filter
local reversed_ipairs = utils.reversed_ipairs

local StandardSlot = standard.StandardSlot
local StandardInventory = standard.StandardInventory
local StandardCluster = standard.StandardCluster
local transfer = abstract.transfer

--------------------------------
-- Ordered Slot Class.

local OrderedSlot = new_class(StandardSlot)

function OrderedSlot:new(args)
	local newOrderedSlot = StandardSlot:new(args)

	setmetatable(newOrderedSlot, OrderedSlot)
	return newOrderedSlot
end

function OrderedSlot:invPos()
	return self.parent.pos
end

function OrderedSlot:isBefore(other)
    return (self:invPos() < other:invPos() or (self:invPos() == other:invPos() and self.index < other.index))
end

function OrderedSlot:isAfter(other)
    return (self:invPos() > other:invPos() or (self:invPos() == other:invPos() and self.index > other.index))
end

function OrderedSlot:isAt(other)
    return (self:invPos() == other:invPos() and self.index == other.index)
end

--------------------------------
-- Ordered Storage Inventory

local OrderedInventory = new_class(StandardInventory)

function OrderedInventory:new(args)
	local newOrderedInventory = StandardInventory:new(args)

	-- Could not find inventory.
	if not newOrderedInventory then
		return nil
	end

	if args.pos == nil then error("missing parameter `pos`") end

	newOrderedInventory.pos = args.pos

	setmetatable(newOrderedInventory, self)
	return newOrderedInventory
end

function OrderedInventory:_repopulate()
	local items = peripheral.call(self.name, "list")
	local slots = {}

	for index=1,self.size do
		local slot = OrderedSlot:new{
			parent = self,
			index = index,
			_item = items[index],
		}

		slots[#slots+1] = slot
	end

	self.slots = slots
end

function OrderedInventory:_swap(slot0, slot1, empty_slot)
	transfer(slot0, empty_slot)
	transfer(slot1, slot0)
	transfer(empty_slot, slot1)
end

function OrderedInventory:sort()
	if self.item_count['empty'] == 0 then
		error("Inventory is full")
	end

	local pos = 1
	local cmp = function(a, b) return a > b end

	local function get_empty_slot()
		for _,slot in reversed_ipairs(self.slots) do
			if not slot:hasItem() then
				return slot
			end
		end
	end

	local empty_slot = get_empty_slot()
	for _,item_name in ipairs(get_order(self.item_count, cmp)) do
		if item_name ~= 'empty' then
			-- local item_slots = table_filter(self.slots,
			-- 	function(slot)
			-- 		return slot:itemName() == item_name
			-- 	end)
			local item_slots = {}
			for _,slot in ipairs(self.slots) do
				if slot:itemName() == item_name then
					item_slots[#item_slots+1] = slot
				end
			end
			-- print(#item_slots)

			-- print(utils.tostring(#self.slots)..' '..utils.tostring(#item_slots)..' '..utils.tostring(self.item_count[item_name]))
			for _,slot in ipairs(item_slots) do
				if slot:isAfter(self.slots[pos]) then
					self:_swap(slot, self.slots[pos], empty_slot)
				end

				if empty_slot:hasItem() then
					empty_slot = get_empty_slot()
				end

				pos = pos + 1
			end
		end
	end
end

--------------------------------
-- Ordered Storage Cluster

local OrderedCluster = new_class(StandardCluster)
function OrderedCluster:new(args)
	local newOrderedCluster = StandardCluster:new(args)

	setmetatable(newOrderedCluster, OrderedCluster)
	return newOrderedCluster
end

-- Adds a new inventory to the cluster. Data for the inventory may be build.
function OrderedCluster:registerInventory(args)
	local inv = OrderedInventory:new{
		parent = self,
		name = args.inv_name,
		pos = #self.invs+1,
	}

	-- Inventory not found in network.
	if not inv then
		return
	end

	inv:refresh()
	self:_addInventoryContribution(inv)
	table.insert(self.invs, inv)
end

-- Removes an inventory from the cluster. Data from the inventory may be deleted.
function OrderedCluster:unregisterInventory(inv_name)
	local inv_pos = self:invPos(inv_name)

	if not inv_pos then
		error('Inventory '..inv_name..' not present in cluster '..self.name)
	end

	local inv = self.invs[inv_pos]

	table.remove(self.invs, inv_pos)
	self:_removeInventoryContribution(inv)
end

-- Swaps the item in `from_slot` with the item in `to_slot`.

function OrderedCluster:_swap(from_slot, to_cluster, to_slot)
	if from_slot == to_slot then
		return
	elseif not from_slot:hasItem() then
		--toCluster:move(toSlot, self, fromSlot)
		transfer(to_slot, from_slot)
	elseif not to_slot:hasItem() then
		--self:move(fromSlot, toCluster, toSlot)
		transfer(from_slot, to_slot)
	else
		local swapSlot = self:_getInputComponents('empty').slot

		if not swapSlot then
			error("no empty space for swap")
		end

		--self:move(fromSlot, self, swapSlot)
		transfer(from_slot, swapSlot)
		--toCluster:move(toSlot, self, fromSlot)
		transfer(to_slot, from_slot)
		--self:move(swapSlot, toCluster, toSlot)
		transfer(swapSlot, to_slot)
	end
end

-- Sorts the storage.
function OrderedCluster:sort()
	if not self.item_count['empty'] == 0 then
		error("there's no space for swapping")
	end

	-- Current position on the slots list.
	local pos = 1
	local cmp = function(a, b) return a > b end

	for _,itemName in ipairs(get_order(self.item_count, cmp)) do
		if itemName ~= 'empty' then
			local all_slots = {}
			local item_slots = {}

			for _,inv in ipairs(self.invs) do
				for _,slot in ipairs(inv.slots) do
					all_slots[#all_slots+1] = slot
				end

				if inv.item_slots[itemName] then
					for slot in inv.item_slots[itemName]:iterate() do
						item_slots[#item_slots+1] = slot
					end
				end
			end

			for _,slot in ipairs(item_slots) do
				if slot:isAfter(all_slots[pos]) then
					self:_swap(slot, self, all_slots[pos])
				end

				pos = pos + 1
			end
		end
	end
end

function OrderedCluster:packItem(item_name)
	if not self:hasItem(item_name) then
		error("There's no item "..item_name.."in cluster "..self.name)
	end

	-- NOTE: We create a new list for it, because all the moving and swapping will change the properties of the inventorie's inner list mid-execution. The following list on the other hand, will be stable till the end of execution.
	local item_slots = {}
	for _, inv in ipairs(self.invs) do
		if inv:hasItem(item_name) then
			for slot in inv.item_slots[item_name]:iterate() do
				item_slots[#item_slots+1] = slot
			end
		end
	end

	local head = 1
	local tail = #item_slots

	while head ~= tail do
		--local moved = self:move(item_slots[tail], self, item_slots[head])
		local moved = transfer(item_slots[tail], item_slots[head])

		if moved == 0 then
			head = head + 1
		else
			if not item_slots[tail]:hasItem() then
				tail = tail - 1
			end
		end
	end
end

function OrderedCluster:pack()
	for item_name, item_count in pairs(self.item_count) do
		if item_name ~= 'empty' and item_count > 0 then
			self:packItem(item_name)
		end
	end
end

return {
	OrderedSlot = OrderedSlot,
	OrderedInventory = OrderedInventory,
	OrderedCluster = OrderedCluster,
}
