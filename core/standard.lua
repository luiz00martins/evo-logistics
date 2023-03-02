local utils = require('/logos-library.utils.utils')
local dl_list = require('/logos-library.utils.dl_list')
local core = require('/logos-library.core.core')

local reversed_ipairs = utils.reversed_ipairs
local table_reduce = utils.table_reduce
local new_class = utils.new_class
local table_map = utils.table_map
local table_filter = utils.table_filter

local AbstractState = core.AbstractState
local AbstractInventory = core.AbstractInventory
local AbstractCluster = core.AbstractCluster

local STANDARD_COMPONENT_PRIORITY = 1

local function _getPriority(_) return STANDARD_COMPONENT_PRIORITY end

local function _barePushItems(_, output_components, input_components, limit)
	return peripheral.call(output_components.inventory.name, 'pushItems', input_components.inventory.name, output_components.state.slot, limit, input_components.state.slot), output_components.state:itemName()
end

local function _barePullItems(_, output_components, input_components, limit)
	return peripheral.call(input_components.inventory.name, 'pullItems', output_components.inventory.name, output_components.state.slot, limit, input_components.state.slot), output_components.state:itemName()
end

local StandardState = new_class(AbstractState)

function StandardState:new (args)
	local newStandardState = AbstractState:new(args)

	-- Setting default.
	if args.full == nil then args.full = false end

	newStandardState.full = args.full

	setmetatable(newStandardState, self)
	return newStandardState
end

StandardState._getPriority = _getPriority
StandardState._barePushItems = _barePushItems
StandardState._barePullItems = _barePullItems

function StandardState:_getInputComponents(item_name)
	if not self.full and (not item_name or self:itemName() == 'empty' or self:itemName() == item_name) then
		return {
			self = self,
			state = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	end

	return nil
end

function StandardState:_getOutputComponents(item_name)
	if self:hasItem(item_name) then
		return {
			self = self,
			state = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	end

	return nil
end

function StandardState:_inputLimit(item_name, max_count)
	if not self.full and (not item_name or self:itemName() == 'empty' or self:itemName() == item_name) then
		return max_count - self:itemCount()
	end

	return 0
end

function StandardState:_outputLimit(item_name)
	if self:hasItem(item_name) then
		return self:itemCount()
	end

	return 0
end

StandardState.hasItemAvailable = StandardState.hasItem

-- Gets the up to date data about the state's items.
function StandardState:refresh()
	self._item = peripheral.call(self:invName(), 'getItemDetail', self.slot)
	self.full = false
end

-- Adds `amount` of `itemName` to the slot.
function StandardState:_itemAddedHandler(item_name, amount, _)
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
function StandardState:_itemRemovedHandler(item_name, amount, _)
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
	-- Map<item_name, DL_List<State>>: Stores all of an item's states. For O(1) access to a state that has a specific item.
	newStandardInventory.item_states = {}

	setmetatable(newStandardInventory, self)
	return newStandardInventory
end

StandardInventory._getPriority = _getPriority
StandardInventory._barePushItems = _barePushItems
StandardInventory._barePullItems = _barePullItems

function StandardInventory:_inputState(item_name, include_empty)
	if include_empty == nil then include_empty = true end

	item_name = item_name or 'empty'

	if item_name ~= 'empty' then
		local item_states = self.item_states[item_name]
		if item_states then
			local item_state = item_states.last
			if item_state and not item_state.full then
				return item_state
			end
		end
	end

	if item_name == 'empty' or include_empty then
		local item_states = self.item_states['empty']
		if item_states then
			local item_state = item_states.first
			if item_state then
				return item_state
			end
		end
	end
end

function StandardInventory:_outputState(item_name)
	local item_states

	if not item_name then
		item_name, item_states = next(self.item_states)
		if item_name == 'empty' then
			item_name, item_states = next(self.item_states, 'empty')
		end
	else
		item_states = self.item_states[item_name]
	end

	if item_states then
		return item_states.last
	else
		return nil
	end
end

function StandardInventory:_getInputComponents(item_name)
	local state = self:_inputState(item_name, true)

	if not state then return nil end

	return {
		self = self,
		state = state,
		inventory = self,
		cluster = self.parent,
	}
end

function StandardInventory:_getOutputComponents(item_name)
	local state = self:_outputState(item_name)

	if not state then return nil end

	return {
		self = self,
		state = state,
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
		item_name, _ = next(self.item_states)
		if item_name == 'empty' then
			item_name, _ = next(self.item_states, 'empty')
		end

		return item_name ~= nil
	else
		return self.item_states[item_name] ~= nil
	end
end

StandardInventory.itemIsAvailable = StandardInventory.hasItem

function StandardInventory:itemNames()
	local item_names = {}

	for item_name, _ in pairs(self.item_states) do
		if item_name ~= 'empty' then
			table.insert(item_names, item_name)
		end
	end

	return item_names
end

function StandardInventory:_repopulate()
	local states = {}

	for slot=1,self.size do
		local state = StandardState:new{
			parent = self,
			slot = slot,
		}

		states[#states+1] = state
	end

	self.states = states
end

function StandardInventory:catalog()
	self:_repopulate()
	self:refresh()
end

function StandardInventory:_cleanUp()
	for _,item_states in pairs(self.item_states) do
		local states_list = {}
		for state in item_states:iterate() do
			table.insert(states_list, state)
		end

		for _,state in ipairs(states_list) do
			item_states:remove(state)
		end
	end
end

function StandardInventory:refresh()
	self:_cleanUp()
	local items = peripheral.call(self.name, "list")

	local item_count = {}
	local item_states = {}

	for slot,state in ipairs(self.states) do
		state._item = items[slot]
		state.full = false

		local item_name = state:itemName()

		-- Creating item counter if there isn't one for the item.
		item_count[item_name] = item_count[item_name] or 0
		-- Creating item states list if there isn't one for the item.
		item_states[item_name] = item_states[item_name] or dl_list()

		-- Adding item the item states list.
		item_states[item_name]:push(state)
		-- Adding item amount to counter.
		if state:hasItem() then
			item_count[item_name] = item_count[item_name] + state:itemCount()
		else
			-- Each empty slot count +1 to the 'empty' counter.
			item_count[item_name] = item_count[item_name] + 1
		end
	end

	self.item_count = item_count
	self.item_states = item_states
end

function StandardInventory:_getItemCountDifference(item_name)
	local function item_name_filter(item)
		return item.name == item_name
	end

	local old_items = table_filter(
		table_map(self.states, function(state)
			return state:item()
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
function StandardInventory:_relocatePushedItem(target_state, item_name, amount)
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
		local new_state = self.states[i]

		moved = moved + peripheral.call(self.name, 'pushItems', self.name, new_state.slot, diff, target_state.slot)
	end

	if moved ~= amount then
		error('Moved ' .. moved .. ' items, but expected to move ' .. amount .. ' items.')
	end

	return moved
end

-- This method assumes that some items have been removed from the inventory, from the wrong slot. It does not assume which slot the items were taken from. It finds where the items removed were taken from, and moves items from the specified slot into them.
-- It is used by the barrels, which cannot remove from a specific slot.
function StandardInventory:_relocatePulledItem(source_state, item_name, amount)
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
		local new_state = self.states[i]

		moved = moved + peripheral.call(self.name, 'pushItems', self.name, source_state.slot, diff, new_state.slot)
	end

	if moved ~= amount then
		error('Moved ' .. moved .. ' items, but expected to move ' .. amount .. ' items.')
	end

	return moved
end

function StandardInventory:_itemAddedHandler(item_name, amount, input_components)
	if amount == 0 then return end

	local state = input_components.state

	-- NOTE: If the state is available (somtimes it isn't, for barrels for example), we update the inventory internal manually, as re-catalogging it is expensive...
	if state then
		-- Updating item count.
		self.item_count[item_name] = (self.item_count[item_name] or 0) + amount

		-- If the amount if items in the state == the amount moved, then it was previously empty.
		if state:itemCount() == amount then
			-- So, we gotta remove it from the 'empty' count and list.
			self.item_count['empty'] = self.item_count['empty'] - 1
			self.item_states['empty']:remove(state)

			-- Make sure the 'empty' list is removed if there's no states anymore.
			if self.item_states['empty'].length == 0 then
				self.item_states['empty'] = nil
			end

			-- and add it to the item's list.
			self.item_states[item_name] = self.item_states[item_name] or dl_list()
			self.item_states[item_name]:push(state)
		end
	else
		-- ...otherwise, we just re-catalog the inventory.
		self:catalog()
	end
end

function StandardInventory:_itemRemovedHandler(item_name, amount, output_components)
	if amount == 0 then return end

	local state = output_components.state

	-- NOTE: If the state is available (somtimes it isn't, for barrels for example), we update the inventory internal manually, as re-catalogging it is expensive...
	if state then
		-- Updating item count.
		self.item_count[item_name] = self.item_count[item_name] - amount

		-- If there's no item left delete the counter for that item.
		if self.item_count[item_name] == 0 then
			self.item_count[item_name] = nil
		end

		-- If all items were removed from the slot, we need add to the remove from the item's count/list, and add to the 'empty' item's count/list.
		if not state:hasItem() then
			-- Remove state from the item's list.
			self.item_states[item_name]:remove(state)

			-- Make sure the item list is removed if there's no states anymore.
			if self.item_states[item_name].length == 0 then
				self.item_states[item_name] = nil
			end

			-- Add it to the 'empty' list.
			self.item_states['empty'] = self.item_states['empty'] or dl_list()
			self.item_states['empty']:unshift(state)

			-- Add to counter
			self.item_count['empty'] = (self.item_count['empty'] or 0) + 1
		end
	else
		-- If the state is not available, we re-catalog the inventory.
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
	StandardState = StandardState,
	StandardInventory = StandardInventory,
	StandardCluster = StandardCluster,
}
