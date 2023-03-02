local utils = require('/logos-library.utils.utils')
local new_class = utils.new_class

local function _executeTransactionOperation(args)
	-- Validating arguments.
	if not args then error('missing args')
	elseif not args.source then error('missing argument source')
	elseif not args.target then error('missing argument target')
	elseif not args.operation then error('missing argument operation') end

	if args.limit then
		if args.limit and args.limit < 1 then error('argument limit must be greater than 0')
		elseif args.limit and args.limit > args.source:itemCount(args.item_name) then error('limit must be less than or equal to the amount of items in the cluster ('..utils.tostring(args.limit)..'/'..utils.tostring(args.source:itemCount(args.item_name))..')')
		end
	end

	local source = args.source
	local target = args.target
	local operation = args.operation
	local item_name = args.item_name
	local limit = args.limit or source:itemCount(item_name)

	-- Moving items.
	local execute_operation
	if operation == 'push' then
		execute_operation = function(output_components, input_components, _limit)
			return source:_barePushItems(output_components, input_components, _limit)
		end
	elseif operation == 'pull' then
		execute_operation = function(output_components, input_components, _limit)
			return target:_barePullItems(output_components, input_components, _limit)
		end
	else
		error('invalid operation '..utils.tostring(operation))
	end

	local moved = 0
	local max_tries = 3
	local current_try = 0
	while moved < limit do
		local output_components = source:_getOutputComponents(item_name)
		local input_components = target:_getInputComponents(item_name)

		if not output_components or not input_components then
			if not output_components then
				utils.log('no output components for '..utils.tostring(item_name))
			else
				utils.log('no input components for '..utils.tostring(item_name))
			end

			break
		end

		local just_moved, item_moved = execute_operation(output_components, input_components, limit - moved)

		moved = moved + just_moved
		
		if just_moved == 0 then
			current_try = current_try + 1
		else
			current_try = 0
		end

		if current_try >= max_tries then
			utils.log('stuck in a loop, aborting')
			break
		end

		-- NOTE: We do this because the components table contains a 'self' component, which is repeated. If we don't strip it, we will run the handler twice.
		for _,component in pairs{state = output_components.state, inventory = output_components.inventory, cluster = output_components.cluster} do
			component:_itemRemovedHandler(item_moved, just_moved, output_components)
		end

		for _,component in pairs{state = input_components.state, inventory = input_components.inventory, cluster = input_components.cluster} do
			component:_itemAddedHandler(item_moved, just_moved, input_components)
		end
	end

	return moved
end

local function pullItems(self, args)
	return _executeTransactionOperation {
		source = args.source,
		target = self,
		operation = 'pull',
		item_name = args.item_name,
		limit = args.limit
	}
end

local function pushItems(self, args)
	return _executeTransactionOperation {
		source = self,
		target = args.target,
		operation = 'push',
		item_name = args.item_name,
		limit = args.limit
	}
end

-- This function has the responsibility of checking priorities and delegating which internal functions should be called to execute the transfer of items.
local function transfer(output, input, item_name, limit)
	if output:_getPriority() >= input:_getPriority() then
		return output:pushItems {
			target = input,
			item_name = item_name,
			limit = limit,
		}
	else
		return input:pullItems {
			source = output,
			item_name = item_name,
			limit = limit,
		}
	end
end

--------------------------------
-- Inventory slot state.

local AbstractState = new_class()

function AbstractState:new(args)
	-- These arguments must be passed.
	if args.slot == nil then error('parameter missing `slot`') end
	if args.parent == nil then error('parameter missing `parent`') end

	local newState =  {
		parent = args.parent,
		_item = args.item,
		slot = args.slot,
		component_type = 'state',
	}

	setmetatable(newState, self)
	return newState
end

function AbstractState:invName()
	return self.parent.name
end

function AbstractState:item()
	return self._item
end

function AbstractState:itemName()
	local item = self:item()
	if item then
		return item.name
	else
		return 'empty'
	end
end

function AbstractState:itemCount()
	local item = self:item()
	if item then
		return item.count
	else
		return 0
	end
end

-- Returns whether the state has the item `item_name` (may be `nil` for any item).
function AbstractState:hasItem(item_name)
	if item_name then return self:itemName() == item_name end

	return self._item ~= nil
end

-- Returns whether `item_name` is available (for output) in the state. `item_name` may be `nil` for any item.
AbstractState.itemIsAvailable = AbstractState.hasItem

---@diagnostic disable-next-line: unused-local
function AbstractState:_moveItem(target_state, limit)
	error('abstract method "_moveItem" not implemented')
end

-- Executes when an item is removed to the state.
---@diagnostic disable-next-line: unused-local
function AbstractState:_handleItemAdded(item_name, amount, previous_handlers)
	error('abstract method "_handleItemAdded" not implemented')
end

-- Executes when an item is added to the state.
---@diagnostic disable-next-line: unused-local
function AbstractState:_handleItemRemoved(item_name, amount, previous_handlers)
	error('abstract method "_handleItemRemoved" not implemented')
end

AbstractState.pushItems = pushItems
AbstractState.pullItems = pullItems

local AbstractInventory = new_class()
function AbstractInventory:new(args)
	if not args then error("missing args") end

	local size
	-- Barrel-type inventories do not have the 'size' property, so we have to check for it.
	if utils.table_contains(peripheral.getMethods(args.name), 'size') then
		size = peripheral.call(args.name, "size")
	end

	if args.name == nil then error("missing parameter `name`") end

	local newInventory = {
		name = args.name,
		parent = args.parent,
		size = size,
		states = {},
		component_type = 'inventory',
	}

	setmetatable(newInventory, self)
	return newInventory
end

-- Returns whether `item_name` is available (for output) in the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:itemIsAvailable(item_name)
	error('abstract method "itemIsAvailable" not implemented')
end

-- Executes when an item is added to the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:_handleItemAdded(item_name, amount)
	error('abstract method "_handleItemAdded" not implemented')
end

-- Executes when an item is removed from the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:_handleItemRemoved(item_name, amount)
	error('abstract method "_handleItemRemoved" not implemented')
end

AbstractInventory.pushItems = pushItems
AbstractInventory.pullItems = pullItems

local AbstractCluster = new_class()
function AbstractCluster:new(args)
	local newCluster = {
			name = args.name or '',
			invs = args.invs or {},
			component_type = 'cluster',
		}

	setmetatable(newCluster, self)
	return newCluster
end

-- Abstract methods (should be added by specific cluster):
-- Catalogs the cluster (initial setup, can be heavy weight).
function AbstractCluster:catalog()
	error('abstract method "catalog" not implemented')
end

-- Refreshes data that is not normally saved and loaded (should be reasonably lightweight).
function AbstractCluster:refresh()
	error('abstract method "refresh" not implemented')
end

-- Returns the (serialized) cluster's data to be saved.
function AbstractCluster:saveData()
	error('abstract method "saveData" not implemented')
end

-- Loads the cluster's data (in the same format as the 'saveData' function).
---@diagnostic disable-next-line: unused-local
function AbstractCluster:loadData(data)
	error('abstract method "loadData" not implemented')
end

-- Returns the path to the cluster's data file.
function AbstractCluster:dataPath()
	error('abstract method "dataPath" not implemented')
end

-- Returns whether `itemName` exists in the cluster.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:hasItem(item_name)
	error('abstract method "hasItem" not implemented')
end

-- Returns whether `item_name` is available (for output) in the cluster.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:itemIsAvailable(item_name)
	error('abstract method "itemIsAvailable" not implemented')
end

-- Returns all items available in the cluster.
function AbstractCluster:itemNames()
	error('abstract method "itemNames" not implemented')
end

-- Adds a new inventory to the cluster. Data for the inventory may be build.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:registerInventory(inv_name)
	error('abstract method "registerInventory" not implemented')
end

-- Removes an inventory from the cluster. Data from the inventory may be deleted.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:unregisterInventory(inv_name)
	error('abstract method "unregisterInventory" not implemented')
end

-- Executes when an item is added to the cluster.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:_itemAddedHandler(item_name, amount)
	error('abstract method "_handleItemAdded" not implemented')
end

-- Executes when an item is removed from the cluster.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:_itemRemovedHandler(item_name, amount)
	error('abstract method "_handleItemRemoved" not implemented')
end

-- Returns whether the inventory is part of the cluster.
function AbstractCluster:hasInventory(inv_name)
	for _,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			return true
		end
	end

	return false
end

AbstractCluster.pushItems = pushItems
AbstractCluster.pullItems = pullItems
AbstractCluster.transfer = transfer

function AbstractCluster:save()
	local data = self:saveData()
	local path = self:dataPath()

	local file = fs.open(path, 'w')
	file.write(data)
	file.close()
end

-- Loads the cluster's data from its data path.
function AbstractCluster:load()
	local path = self:dataPath()
	local file = fs.open(path, "r")

	if not file then
		return false
	else
		local contents = file.readAll()
		file.close()

		self:loadData(contents)
		return true
	end
end

-- Returning classes.
return {
	AbstractState = AbstractState,
	AbstractInventory = AbstractInventory,
	AbstractCluster = AbstractCluster,
	transfer = transfer,
}
