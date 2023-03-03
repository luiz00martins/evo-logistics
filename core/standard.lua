local utils = require('/logos-library.utils.utils')
local dl_list = require('/logos-library.utils.dl_list')
local abstract = require('/logos-library.core.abstract')

local reversed_ipairs = utils.reversed_ipairs
local table_reduce = utils.table_reduce
local new_class = utils.new_class
local table_map = utils.table_map
local table_filter = utils.table_filter

local AbstractSlot = abstract.AbstractSlot
local AbstractInventory = abstract.AbstractInventory
local AbstractCluster = abstract.AbstractCluster

local STANDARD_COMPONENT_PRIORITY = 1

local function _getPriority(_) return STANDARD_COMPONENT_PRIORITY end

local function _barePushItems(_, output_components, input_components, limit)
	return peripheral.call(output_components.inventory.name, 'pushItems', input_components.inventory.name, output_components.slot.index, limit, input_components.slot.index), output_components.slot:itemName()
end

local function _barePullItems(_, output_components, input_components, limit)
	return peripheral.call(input_components.inventory.name, 'pullItems', output_components.inventory.name, output_components.slot.index, limit, input_components.slot.index), output_components.slot:itemName()
end

local StandardSlot = new_class(AbstractSlot)

function StandardSlot:new (args)
	local newStandardSlot = AbstractSlot:new(args)

	-- Setting default.
	if args.full == nil then args.full = false end

	newStandardSlot.full = args.full

	setmetatable(newStandardSlot, self)
	return newStandardSlot
end

StandardSlot._getPriority = _getPriority
StandardSlot._barePushItems = _barePushItems
StandardSlot._barePullItems = _barePullItems

function StandardSlot:_getInputComponents(item_name)
	if not self.full and (not item_name or self:itemName() == 'empty' or self:itemName() == item_name) then
		return {
			self = self,
			slot = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	end

	return nil
end

function StandardSlot:_getOutputComponents(item_name)
	if self:hasItem(item_name) then
		return {
			self = self,
			slot = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	end

	return nil
end

function StandardSlot:_inputLimit(item_name, max_count)
	if not self.full and (not item_name or self:itemName() == 'empty' or self:itemName() == item_name) then
		return max_count - self:itemCount()
	end

	return 0
end

function StandardSlot:_outputLimit(item_name)
	if self:hasItem(item_name) then
		return self:itemCount()
	end

	return 0
end

StandardSlot.hasItemAvailable = StandardSlot.hasItem

-- Gets the up to date data about the slot's items.
function StandardSlot:refresh()
	self._item = peripheral.call(self:invName(), 'getItemDetail', self.index)
	self.full = false
end

-- Adds `amount` of `itemName` to the slot.
function StandardSlot:_itemAddedHandler(item_name, amount, _)
	if amount == 0 then
		self.full = true
	end

	if not self:hasItem() then
		self._item = {
			name = item_name,
			count = amount,
		}
	elseif item_name == self:itemName() then
		local item = self:item()
		item.count = item.count + amount
	else
		error('Item being added ('..utils.tostring(item_name)..') differs from item in slot ('..self:itemName()..')')
	end
end

-- Removes `amount` items from the slot.
function StandardSlot:_itemRemovedHandler(item_name, amount, _)
	self.full = false

	if self:itemName() == item_name then
		self._item.count = self._item.count - amount

		-- If there's no items in the slot, we delete its table.
		if self:itemCount() == 0 then
			self._item = nil
		end
	else
		error('Item being removed ('..utils.tostring(item_name)..') differs from item in slot ('..self:itemName()..')')
	end
end

--------------------------------
-- Standard Storage Inventory

local StandardInventory = new_class(AbstractInventory)

function StandardInventory:new(args)
	local newStandardInventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not newStandardInventory then
		return nil
	end

	newStandardInventory.item_count = {}
	-- Map<item_name, DL_List<Slot>>: Stores all of an item's slots. For O(1) access to a slot that has a specific item.
	newStandardInventory.item_slots = {}

	setmetatable(newStandardInventory, self)
	return newStandardInventory
end

StandardInventory._getPriority = _getPriority
StandardInventory._barePushItems = _barePushItems
StandardInventory._barePullItems = _barePullItems

function StandardInventory:_inputSlot(item_name, include_empty)
	if include_empty == nil then include_empty = true end

	item_name = item_name or 'empty'

	if item_name ~= 'empty' then
		local item_slots = self.item_slots[item_name]
		if item_slots then
			local item_slot = item_slots.last
			if item_slot and not item_slot.full then
				return item_slot
			end
		end
	end

	if item_name == 'empty' or include_empty then
		local item_slots = self.item_slots['empty']
		if item_slots then
			local item_slot = item_slots.first
			if item_slot then
				return item_slot
			end
		end
	end
end

function StandardInventory:_outputSlot(item_name)
	local item_slots

	if not item_name then
		item_name, item_slots = next(self.item_slots)
		if item_name == 'empty' then
			item_name, item_slots = next(self.item_slots, 'empty')
		end
	else
		item_slots = self.item_slots[item_name]
	end

	if item_slots then
		return item_slots.last
	else
		return nil
	end
end

function StandardInventory:_getInputComponents(item_name)
	local slot = self:_inputSlot(item_name, true)

	if not slot then return nil end

	return {
		self = self,
		slot = slot,
		inventory = self,
		cluster = self.parent,
	}
end

function StandardInventory:_getOutputComponents(item_name)
	local slot = self:_outputSlot(item_name)

	if not slot then return nil end

	return {
		self = self,
		slot = slot,
		inventory = self,
		cluster = self.parent,
	}
end

function StandardInventory:itemCount(item_name)
	if not item_name then
		return table_reduce(self.item_count, function(a,b) return a+b end) - (self.item_count['empty'] or 0)
	else
		return self.item_count[item_name] or 0
	end
end

StandardInventory.availableItemCount = StandardInventory.itemCount

function StandardInventory:hasItem(item_name)
	if not item_name then
		item_name, _ = next(self.item_slots)
		if item_name == 'empty' then
			item_name, _ = next(self.item_slots, 'empty')
		end

		return item_name ~= nil
	else
		return self.item_slots[item_name] ~= nil
	end
end

StandardInventory.itemIsAvailable = StandardInventory.hasItem

function StandardInventory:itemNames()
	local item_names = {}

	for item_name, _ in pairs(self.item_slots) do
		if item_name ~= 'empty' then
			table.insert(item_names, item_name)
		end
	end

	return item_names
end

function StandardInventory:_repopulate()
	local slots = {}

	for index=1,self.size do
		local slot = StandardSlot:new{
			parent = self,
			index = index,
		}

		slots[#slots+1] = slot
	end

	self.slots = slots
end

function StandardInventory:catalog()
	self:_repopulate()
	self:refresh()
end

function StandardInventory:_cleanUp()
	for _,item_slots in pairs(self.item_slots) do
		local slots_list = {}
		for slot in item_slots:iterate() do
			table.insert(slots_list, slot)
		end

		for _,slot in ipairs(slots_list) do
			item_slots:remove(slot)
		end
	end
end

function StandardInventory:refresh()
	self:_cleanUp()
	local items = peripheral.call(self.name, "list")

	local item_count = {}
	local item_slots = {}

	for index,slot in ipairs(self.slots) do
		slot._item = items[index]
		slot.full = false

		local item_name = slot:itemName()

		-- Creating item counter if there isn't one for the item.
		item_count[item_name] = item_count[item_name] or 0
		-- Creating item slots list if there isn't one for the item.
		item_slots[item_name] = item_slots[item_name] or dl_list()

		-- Adding item the item slots list.
		item_slots[item_name]:push(slot)
		-- Adding item amount to counter.
		if slot:hasItem() then
			item_count[item_name] = item_count[item_name] + slot:itemCount()
		else
			-- Each empty slot count +1 to the 'empty' counter.
			item_count[item_name] = item_count[item_name] + 1
		end
	end

	self.item_count = item_count
	self.item_slots = item_slots
end

function StandardInventory:_getItemCountDifference(item_name)
	local function item_name_filter(item)
		return item.name == item_name
	end

	local old_items = table_filter(
		table_map(self.slots, function(slot)
			return slot:item()
		end),
		item_name_filter)
	local new_items = table_filter(peripheral.call(self.name, 'list'), item_name_filter)

	local old_item_counts = table_map(old_items, function(item)
		return item.count
	end)
	local new_item_counts = table_map(new_items, function(item)
		return item.count
	end)

	return old_item_counts, new_item_counts
end

-- This method assumes that some items have been added to the inventory, but to the wrong slot. It does not assume which slot the items went into. It finds where the items added went, and moved them to the correct slot.
-- It is used by the barrels, which cannot move to a specific slot.
function StandardInventory:_relocatePushedItem(target_slot, item_name, amount)
	local old_item_counts, new_item_counts = self:_getItemCountDifference(item_name)

	-- Figure out what changed.
	local difference = {}
	-- NOTE: No items will be missed, as the new item counts will always be greater than the old item counts.
	for i, new_count in pairs(new_item_counts) do
		local old_count = old_item_counts[i] or 0

		local diff = new_count - old_count

		if diff > 0 then
			difference[i] = diff
		end
	end

	-- Move the items to the correct slot.
	local moved = 0
	for i, diff in pairs(difference) do
		local new_slot = self.slots[i]

		moved = moved + peripheral.call(self.name, 'pushItems', self.name, new_slot.index, diff, target_slot.index)
	end

	if moved ~= amount then
		error('Moved ' .. moved .. ' items, but expected to move ' .. amount .. ' items.')
	end

	return moved
end

-- This method assumes that some items have been removed from the inventory, from the wrong slot. It does not assume which slot the items were taken from. It finds where the items removed were taken from, and moves items from the specified slot into them.
-- It is used by the barrels, which cannot remove from a specific slot.
function StandardInventory:_relocatePulledItem(source_slot, item_name, amount)
	local old_item_counts, new_item_counts = self:_getItemCountDifference(item_name)

	-- Figure out what changed.
	local difference = {}
	-- NOTE: No items will be missed, as the old item counts will always be greater than the new item counts.
	for i, old_count in pairs(old_item_counts) do
		local new_count = new_item_counts[i] or 0

		local diff = old_count - new_count

		if diff > 0 then
			difference[i] = diff
		end
	end

	-- Move the items to the correct slots.
	local moved = 0
	for i, diff in pairs(difference) do
		local new_slot = self.slots[i]

		moved = moved + peripheral.call(self.name, 'pushItems', self.name, source_slot.index, diff, new_slot.index)
	end

	if moved ~= amount then
		error('Moved ' .. moved .. ' items, but expected to move ' .. amount .. ' items.')
	end

	return moved
end

function StandardInventory:_itemAddedHandler(item_name, amount, input_components)
	if amount == 0 then return end

	local slot = input_components.slot

	-- NOTE: If the slot is available (somtimes it isn't, for barrels for example), we update the inventory internal manually, as re-catalogging it is expensive...
	if slot then
		-- Updating item count.
		self.item_count[item_name] = (self.item_count[item_name] or 0) + amount

		-- If the amount if items in the slot == the amount moved, then it was previously empty.
		if slot:itemCount() == amount then
			-- So, we gotta remove it from the 'empty' count and list.
			self.item_count['empty'] = self.item_count['empty'] - 1
			self.item_slots['empty']:remove(slot)

			-- Make sure the 'empty' list is removed if there's no slots anymore.
			if self.item_slots['empty'].length == 0 then
				self.item_slots['empty'] = nil
			end

			-- and add it to the item's list.
			self.item_slots[item_name] = self.item_slots[item_name] or dl_list()
			self.item_slots[item_name]:push(slot)
		end
	else
		-- ...otherwise, we just re-catalog the inventory.
		self:catalog()
	end
end

function StandardInventory:_itemRemovedHandler(item_name, amount, output_components)
	if amount == 0 then return end

	local slot = output_components.slot

	-- NOTE: If the slot is available (somtimes it isn't, for barrels for example), we update the inventory internal manually, as re-catalogging it is expensive...
	if slot then
		-- Updating item count.
		self.item_count[item_name] = self.item_count[item_name] - amount

		-- If there's no item left delete the counter for that item.
		if self.item_count[item_name] == 0 then
			self.item_count[item_name] = nil
		end

		-- If all items were removed from the slot, we need add to the remove from the item's count/list, and add to the 'empty' item's count/list.
		if not slot:hasItem() then
			-- Remove slot from the item's list.
			self.item_slots[item_name]:remove(slot)

			-- Make sure the item list is removed if there's no slots anymore.
			if self.item_slots[item_name].length == 0 then
				self.item_slots[item_name] = nil
			end

			-- Add it to the 'empty' list.
			self.item_slots['empty'] = self.item_slots['empty'] or dl_list()
			self.item_slots['empty']:unshift(slot)

			-- Add to counter
			self.item_count['empty'] = (self.item_count['empty'] or 0) + 1
		end
	else
		-- If the slot is not available, we re-catalog the inventory.
		self:catalog()
	end
end

--------------------------------
-- Standard Storage Cluster

local StandardCluster = new_class(AbstractCluster)
function StandardCluster:new(args)
	local newStandardCluster = AbstractCluster:new(args)

	newStandardCluster.item_count = {}

	setmetatable(newStandardCluster, StandardCluster)
	return newStandardCluster
end

StandardCluster._getPriority = _getPriority
StandardCluster._barePushItems = _barePushItems
StandardCluster._barePullItems = _barePullItems

function StandardCluster:_getInputComponents(item_name)
	if not self.invs then return nil end

	for _,inv in reversed_ipairs(self.invs) do
		local components = inv:_getInputComponents(item_name)

		if components then
			components.self = self
			return components
		end
	end

	return nil
end

function StandardCluster:_getOutputComponents(item_name)
	if not self.invs then return nil end

	for _,inv in reversed_ipairs(self.invs) do
		local components = inv:_getOutputComponents(item_name)

		if components then
			components.self = self
			return components
		end
	end

	return nil
end

function StandardCluster:_addInventoryContribution(inv)
	for item_name,item_count in pairs(inv.item_count) do
		self.item_count[item_name] = self.item_count[item_name] or 0
		self.item_count[item_name] = self.item_count[item_name] + item_count
	end
end

function StandardCluster:_removeInventoryContribution(inv)
	for item_name,item_count in pairs(inv.item_count) do
		self.item_count[item_name] = self.item_count[item_name] - item_count

		if self.item_count[item_name] == 0 then
			self.item_count[item_name] = nil
		end
	end
end

function StandardCluster:refresh()
	for _,inv in pairs(self.invs) do
		self:_removeInventoryContribution(inv)
		inv:refresh()
		self:_addInventoryContribution(inv)
	end
end

function StandardCluster:catalog()
	self.item_count = {}

	for _,inv in pairs(self.invs) do
		inv:catalog()
		self:_addInventoryContribution(inv)
	end
end

function StandardCluster:saveData()
	local inv_names = {}
	for _,inv in ipairs(self.invs) do
		inv_names[#inv_names+1] = inv.name
	end

	local data = {
		inv_names = inv_names,
	}

	return textutils.serialize(data)
end

function StandardCluster:loadData(data)
	data = textutils.unserialize(data)

	if data.inv_names then
		for _,inv_name in ipairs(data.inv_names) do
			if peripheral.isPresent(inv_name) then
				self:registerInventory{inv_name = inv_name}
			else
				utils.log("Inventory "..inv_name.." is no longer present")
			end
		end
	end

	self:catalog()

	return true
end

function StandardCluster:dataPath()
	return "/logistics_data/"..self.name..".data"
end

function StandardCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self.item_count, function(a,b) return a+b end, 0) - (self.item_count['empty'] or 0)
	end

	return self.item_count[item_name] or 0
end

StandardCluster.availableItemCount = StandardCluster.itemCount

function StandardCluster:hasItem(item_name)
	for _,inv in ipairs(self.invs) do
		if inv:hasItem(item_name) then
			return true
		end
	end

	return false
end

StandardCluster.itemIsAvailable = StandardCluster.hasItem

function StandardCluster:itemNames()
	local item_names = {}
	for item_name, _ in pairs(self.item_count) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function StandardCluster:_itemAddedHandler(item_name, amount, _)
	if amount == 0 then return true end

	-- Updating item count.
	self.item_count[item_name] = (self.item_count[item_name] or 0) + amount
end

function StandardCluster:_itemRemovedHandler(item_name, amount, _)
	if amount == 0 then return true end

	self.item_count[item_name] = self.item_count[item_name] - amount

	-- If there's no item left delete the counter for that item.
	if self.item_count[item_name] == 0 then
		self.item_count[item_name] = nil
	end
end

function StandardCluster:invPos(inv_name)
	for i,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			return i
		end
	end

	return nil
end

function StandardCluster:_createInventory(args)
	return StandardInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function StandardCluster:registerInventory(args)
	local inv = self:_createInventory(args)

	-- Inventory not found in network.
	if not inv then
		return
	end

	inv:catalog()
	self:_addInventoryContribution(inv)
	table.insert(self.invs, inv)
end

-- Removes an inventory from the cluster. Data from the inventory may be deleted.
function StandardCluster:unregisterInventory(inv_name)
	local inv_pos = self:invPos(inv_name)

	if not inv_pos then
		error('Inventory '..inv_name..' not present in cluster '..self.name)
	end

	local inv = self.invs[inv_pos]

	table.remove(self.invs, inv_pos)
	self:_removeInventoryContribution(inv)
end

-- Returning classes.
return {
	StandardSlot = StandardSlot,
	StandardInventory = StandardInventory,
	StandardCluster = StandardCluster,
}
