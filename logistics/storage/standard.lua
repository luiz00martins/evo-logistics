local utils = require('/logos.utils')
local dl_list = require('/logos.logistics.utils.dl_list')
local core = require('/logos.logistics.storage.core')

local reversed_ipairs = utils.reversed_ipairs
local table_reduce = utils.table_reduce
local new_class = utils.new_class

local AbstractState = core.AbstractState
local AbstractInventory = core.AbstractInventory
local AbstractCluster = core.AbstractCluster

local StandardState = new_class(AbstractState)

function StandardState:new (args)
	local newState = AbstractState:new(args)

	-- Setting default.
	if args.full == nil then args.full = false end

	newState.full = args.full
	--newState.maxOutput = args.maxOutput or peripheral.call(newState:invName(), 'getItemLimit', args.slot)

	setmetatable(newState, self)
	return newState
end

StandardState.hasItemAvailable = StandardState.hasItem

-- Gets the up to date data about the state's items.
function StandardState:update()
	self._item = peripheral.call(self:invName(), 'getItemDetail', self.slot)
	self.full = false
end

function StandardState:_moveItem(target_state, limit)
	local item = self:item()

	-- If there`s no item to move, return 0.
	if not item then return 0 end
	-- If the states are the same, there's no need to move an item.
	if self == target_state then return 0 end

	-- If no limit (or negative limit) was given, then we assume every item is to be moved.
	if not limit or limit < 0 then
		limit = item.count
	end

	-- Moving item
	local moved = peripheral.call(
			self:invName(), 'pushItems',
			target_state:invName(), self.slot, limit, target_state.slot
		)

	return moved
end

-- Adds `amount` of `itemName` to the slot.
function StandardState:_handleItemAdded(item_name, amount, _)
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
		error('Item being added ('..item_name..') differs from item in slot ('..self:itemName()..')')
	end
end

-- Removes `amount` items from the slot.
function StandardState:_handleItemRemoved(item_name, amount, _)
	self.full = false

	if self:itemName() == item_name then
		self._item.count = self._item.count - amount

		-- If there's no items in the slot, we delete its table.
		if self:itemCount() == 0 then
			self._item = nil
		end
	else
		error('Item being removed ('..item_name..') differs from item in slot ('..self:itemName()..')')
	end
end

function StandardState:bareMoveItem(target_state, limit)
	return peripheral.call(
		self:invName(), "pushItems",
		target_state:invName(), self.slot, limit, target_state.slot
	)
end

function StandardState:moveItem(target_state, limit)
	local super = getmetatable(StandardState)

	-- If the slot is full, no item can be moved.
	if target_state.full then return 0 end

	local moved = super.moveItem(self, target_state, limit)

	-- If some item was moved, then the state is not empty anymore.
	if moved > 0 then
		self.full = false
	end
	-- If not all items that could be moved were moved, the target state filled up.
	if moved ~= limit and self:hasItem() then
		target_state.full = true
	end

	return moved
end

--------------------------------
-- Standard Storage Inventory

local StandardInventory = new_class(AbstractInventory)

function StandardInventory:new(args)
	local newInventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not newInventory then
		return nil
	end

	newInventory._itemCount = {}
	-- Map<item_name, DL_List<State>>: Stores all of an item's states. For O(1) access to a state that has a specific item.
	newInventory.itemStates = {}

	setmetatable(newInventory, self)
	return newInventory
end

function StandardInventory:inputState(item_name, include_empty)
	if include_empty == nil then include_empty = true end

	item_name = item_name or 'empty'

	if item_name ~= 'empty' then
		local item_states = self.itemStates[item_name]
		if item_states then
			local item_state = item_states.last
			if item_state and not item_state.full then
				return item_state
			end
		end
	end

	if item_name == 'empty' or include_empty then
		local item_states = self.itemStates['empty']
		if item_states then
			local item_state = item_states.first
			if item_state then
				return item_state
			end
		end
	end
end

function StandardInventory:outputState(item_name)
	local item_states

	if not item_name then
		item_name, item_states = next(self.itemStates)
		if item_name == 'empty' then
			item_name, item_states = next(self.itemStates, 'empty')
		end
	else
		item_states = self.itemStates[item_name]
	end

	if item_states then
		return item_states.last
	else
		return nil
	end
end


function StandardInventory:itemCount(item_name)
	if not item_name then
		return table_reduce(self._itemCount, function(a,b) return a+b end) - (self._itemCount['empty'] or 0)
	end

	return self._itemCount[item_name] or 0
end

StandardInventory.availableItemCount = StandardInventory.itemCount

function StandardInventory:hasItem(item_name)
	if not item_name then
		item_name, _ = next(self.itemStates)
		if item_name == 'empty' then
			item_name, _ = next(self.itemStates, 'empty')
		end

		return item_name ~= nil
	else
		return self.itemStates[item_name] ~= nil
	end
end

StandardInventory.itemIsAvailable = StandardInventory.hasItem

function StandardInventory:itemNames()
	local item_names = {}

	for item_name, _ in pairs(self.itemStates) do
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
	for _,item_states in pairs(self.itemStates) do
		local states_list = {}
		for state in item_states:iterate() do
			table.insert(states_list, state)
		end

		for _,state in ipairs(states_list) do
			item_states:remove(state)
		end
	end
end

-- TODO: Is refresh really necessary? Paralellizing catalog should be more than enough. Perhaps you should remove this.
function StandardInventory:refresh()
	self:_cleanUp()
	local items = peripheral.call(self.name, "list")

	local itemCount = {}
	local itemStates = {}

	for slot,state in ipairs(self.states) do
		state._item = items[slot]
		state.full = false

		local item_name = state:itemName()

		-- Creating item counter if there isn't one for the item.
		itemCount[item_name] = itemCount[item_name] or 0
		-- Creating item states list if there isn't one for the item.
		itemStates[item_name] = itemStates[item_name] or dl_list()

		-- Adding item the item states list.
		itemStates[item_name]:push(state)
		-- Adding item amount to counter.
		if state:hasItem() then
			itemCount[item_name] = itemCount[item_name] + state:itemCount()
		else
			-- Each empty slot count +1 to the 'empty' counter.
			itemCount[item_name] = itemCount[item_name] + 1
		end
	end

	self._itemCount = itemCount
	self.itemStates = itemStates
end

function StandardInventory:_handleItemAdded(item_name, amount, previous_handlers)
	if amount == 0 then return end

	local state = previous_handlers[1]

	-- Updating item count.
	self._itemCount[item_name] = (self._itemCount[item_name] or 0) + amount

	-- If the amount if items in the state == the amount moved, then it was previously empty.
	if state:itemCount() == amount then
		-- So, we gotta remove it from the 'empty' count and list.
		self._itemCount['empty'] = self._itemCount['empty'] - 1
		self.itemStates['empty']:remove(state)

		-- Make sure the 'empty' list is removed if there's no states anymore.
		if self.itemStates['empty'].length == 0 then
			self.itemStates['empty'] = nil
		end

		-- and add it to the item's list.
		self.itemStates[item_name] = self.itemStates[item_name] or dl_list()
		self.itemStates[item_name]:push(state)
	end
end

function StandardInventory:_handleItemRemoved(item_name, amount, previous_handlers)
	if amount == 0 then return end

	-- Updating item count.
	self._itemCount[item_name] = self._itemCount[item_name] - amount

	-- If there's no item left delete the counter for that item.
	if self._itemCount[item_name] == 0 then
		self._itemCount[item_name] = nil
	end

	local state = previous_handlers[1]

	-- If all items were removed from the slot, we need add to the remove from the item's count/list, and add to the 'empty' item's count/list.
	if not state:hasItem() then
		-- Remove state from the item's list.
		self.itemStates[item_name]:remove(state)

		-- Make sure the item list is removed if there's no states anymore.
		if self.itemStates[item_name].length == 0 then
			self.itemStates[item_name] = nil
		end

		-- Add it to the 'empty' list.
		self.itemStates['empty'] = self.itemStates['empty'] or dl_list()
		self.itemStates['empty']:unshift(state)

		-- Add to counter
		self._itemCount['empty'] = (self._itemCount['empty'] or 0) + 1
	end
end

--------------------------------
-- Standard Storage Cluster

local StandardCluster = new_class(AbstractCluster)
function StandardCluster:new(args)
	local newCluster = AbstractCluster:new(args)

	newCluster._itemCount = {}

	setmetatable(newCluster, StandardCluster)
	return newCluster
end

-- TODO: CHANGE THIS
function StandardCluster:inputState(item_name)
	-- TODO: This for loop is O(n). Make this a linked list of inventories. Same as 'Inventory <-> States', make 'Cluster <-> Inventories'.
	for _,inv in reversed_ipairs(self.invs) do
		if inv:hasItem(item_name) then
			local input_state = inv:inputState(item_name, false)

			if input_state then
				return input_state
			else
				break
			end
		end
	end

	for _,inv in ipairs(self.invs) do
		local input_state = inv:inputState(item_name, true)

		if input_state then
			return input_state
		end
	end

	return nil
end

-- TODO: CHANGE THIS
function StandardCluster:outputState(item_name)
	for _,inv in reversed_ipairs(self.invs) do
		local output_state = inv:outputState(item_name)

		if output_state then return output_state end
	end

	return nil
end

function StandardCluster:_addInventoryContribution(inv)
	for item_name,item_count in pairs(inv._itemCount) do
		self._itemCount[item_name] = self._itemCount[item_name] or 0
		self._itemCount[item_name] = self._itemCount[item_name] + item_count
	end
end

function StandardCluster:_removeInventoryContribution(inv)
	for item_name,item_count in pairs(inv._itemCount) do
		self._itemCount[item_name] = self._itemCount[item_name] - item_count

		if self._itemCount[item_name] == 0 then
			self._itemCount[item_name] = nil
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
	self._itemCount = {}

	for _,inv in pairs(self.invs) do
		inv:catalog()
		self:_addInventoryContribution(inv)
	end
end

function StandardCluster:save_data()
	local inv_names = {}
	for _,inv in ipairs(self.invs) do
		inv_names[#inv_names+1] = inv.name
	end

	local data = {
		inv_names = inv_names,
	}

	return textutils.serialize(data)
end

function StandardCluster:load_data(data)
	data = textutils.unserialize(data)

	if data.inv_names then
		for _,inv_name in ipairs(data.inv_names) do
			self:registerInventory{inv_name = inv_name}
		end
	end

	return true
end

function StandardCluster:data_path()
	return "/logistics_data/"..self.name..".data"
end

function StandardCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self._itemCount, function(a,b) return a+b end) - (self._itemCount['empty'] or 0)
	end

	return self._itemCount[item_name] or 0
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
	for item_name, _ in pairs(self._itemCount) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function StandardCluster:_handleItemAdded(item_name, amount, _)
	if amount == 0 then return true end

	-- Updating item count.
	self._itemCount[item_name] = (self._itemCount[item_name] or 0) + amount
end

function StandardCluster:_handleItemRemoved(item_name, amount, _)
	if amount == 0 then return true end

	self._itemCount[item_name] = self._itemCount[item_name] - amount

	-- If there's no item left delete the counter for that item.
	if self._itemCount[item_name] == 0 then
		self._itemCount[item_name] = nil
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
