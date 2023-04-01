local utils = require('/logos-library.utils.utils')
local new_class = require('/logos-library.utils.class').new_class

local DEFAULT_LOG = require('/logos-library.utils.log').empty()

local function _executeTransactionOperation(args)
	-- Validating arguments.
	if not args then error('missing args')
	elseif not args.source then error('missing argument source')
	elseif not args.target then error('missing argument target')
	elseif not args.operation then error('missing argument operation') end

	if args.limit then
		if args.limit and args.limit < 1 then error('argument limit must be greater than 0')
		end
	end

	local source = args.source
	local target = args.target
	local operation = args.operation
	local item_name = args.item_name
	local limit = args.limit or source:itemCount(item_name)
	local log = args.log or DEFAULT_LOG

	-- Moving items.
	local execute_operation
	if operation == 'push' then
		execute_operation = function(output_components, input_components, _item_name, _limit)
			return source:_barePushItems(output_components, input_components, _item_name, _limit)
		end
	elseif operation == 'pull' then
		execute_operation = function(output_components, input_components, _item_name, _limit)
			return target:_barePullItems(output_components, input_components, _item_name, _limit)
		end
	else
		error('invalid operation '..utils.tostring(operation))
	end

	local moved = 0
	local max_tries = 3
	local current_try = 0
	while moved < limit do
		local output_components = source:_getOutputComponents(item_name)
		if not output_components then break end

		-- This exists (instead of reusing the item name) because we want the input to know which item we are putting in even when the original 'item_name' is empty, so the target has the opportunity to return a partially filled slot with that item. Otherwise, the original 'item_name' count be 'nil', and the target wound only return empty states.
		-- HACK: This seems like it knows too much about the descendents. I feel like this discering should not be the responsibility of this function.
		local output_item_name
		if output_components.slot then
			output_item_name = output_components.slot:itemName()
		elseif output_components.inventory then
			if output_components.inventory.itemName then
				output_item_name = output_components.inventory:itemName()
			elseif output_components.inventory.itemNames then
				if item_name then
					output_item_name = item_name
				else
					local item_names = output_components.inventory:itemNames()
					output_item_name = item_names[1]
				end
			end
		end

		local input_components = target:_getInputComponents(output_item_name)
		if not input_components then break end

		local just_moved, item_moved = execute_operation(output_components, input_components, item_name, limit - moved)

		moved = moved + just_moved

		if just_moved == 0 then
			-- HACK: We use 'max_tries' and 'current_try' because sometimes the components don't know they are full until they get a 'amount == 0'. That's their signaling that the move failed.
			-- It would be better to sent the 'intended amount' and the 'moved amount' so they could make the decision on one go. This would allow us to remove the need to retry multiple times.
			current_try = current_try + 1
		else
			current_try = 0
		end

		if current_try >= max_tries then
			log.warning('could not move items, aborting')
			break
		end

		-- NOTE: The order of these calls is important. It's guaranteed to go bottom up.
		for _,part in ipairs{'slot', 'inventory', 'cluster'} do
			if output_components[part] then
				output_components[part]:_itemRemovedHandler(item_moved, just_moved, output_components)
			end
		end

		for _,part in ipairs{'slot', 'inventory', 'cluster'} do
			if input_components[part] then
				input_components[part]:_itemAddedHandler(item_moved, just_moved, input_components)
			end
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
-- Inventory slot.

local AbstractSlot = new_class()

function AbstractSlot:new(args)
	-- These arguments must be passed.
	if args.index == nil then error('parameter missing `index`') end
	if args.parent == nil then error('parameter missing `parent`') end

	local new_slot =  {
		parent = args.parent,
		_item = args.item,
		index = args.index,
		component_type = 'slot',
		log = args.log or args.parent.log or DEFAULT_LOG,
	}

	setmetatable(new_slot, self)
	return new_slot
end

function AbstractSlot:invName()
	return self.parent.name
end

function AbstractSlot:item()
	return self._item
end

function AbstractSlot:itemName()
	local item = self:item()
	if item then
		return item.name
	else
		return 'empty'
	end
end

function AbstractSlot:itemCount()
	local item = self:item()
	if item then
		return item.count
	else
		return 0
	end
end

-- Returns whether the slot has the item `item_name` (may be `nil` for any item).
function AbstractSlot:hasItem(item_name)
	if item_name then return self:itemName() == item_name end

	return self._item ~= nil
end

-- Returns whether `item_name` is available (for output) in the slot. `item_name` may be `nil` for any item.
AbstractSlot.itemIsAvailable = AbstractSlot.hasItem

---@diagnostic disable-next-line: unused-local
function AbstractSlot:_moveItem(target_slot, limit)
	error('abstract method "_moveItem" not implemented')
end

-- Executes when an item is removed to the slot.
---@diagnostic disable-next-line: unused-local
function AbstractSlot:_itemAddedHandler(item_name, amount, components)
	error('abstract method "_itemAddedHandler" not implemented')
end

-- Executes when an item is added to the slot.
---@diagnostic disable-next-line: unused-local
function AbstractSlot:_itemRemovedHandler(item_name, amount, components)
	error('abstract method "_itemRemovedHandler" not implemented')
end

AbstractSlot.pushItems = pushItems
AbstractSlot.pullItems = pullItems

local AbstractInventory = new_class()
function AbstractInventory:new(args)
	if not args then error("missing args") end

	if args.name == nil then error("missing parameter `name`") end
	if args.parent == nil then error("missing parameter `parent`") end

	local new_inventory = {
		name = args.name,
		parent = args.parent,
		slots = {},
		component_type = 'inventory',
		log = args.log or args.parent.log or DEFAULT_LOG,
	}

	setmetatable(new_inventory, self)
	return new_inventory
end

-- Returns whether `item_name` is available (for output) in the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:itemIsAvailable(item_name)
	error('abstract method "itemIsAvailable" not implemented')
end

-- Executes when an item is added to the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:_itemAddedHandler(item_name, amount, components)
	error('abstract method "_itemAddedHandler" not implemented')
end

-- Executes when an item is removed from the inventory.
---@diagnostic disable-next-line: unused-local
function AbstractInventory:_itemRemovedHandler(item_name, amount, components)
	error('abstract method "_itemRemovedHandler" not implemented')
end

AbstractInventory.pushItems = pushItems
AbstractInventory.pullItems = pullItems

local AbstractCluster = new_class()
function AbstractCluster:new(args)
	local new_cluster = {
			name = args.name or '',
			invs = args.invs or {},
			component_type = 'cluster',
			log = args.log or DEFAULT_LOG,
		}

	setmetatable(new_cluster, self)
	return new_cluster
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
	error('abstract method "_itemAddedHandler" not implemented')
end

-- Executes when an item is removed from the cluster.
---@diagnostic disable-next-line: unused-local
function AbstractCluster:_itemRemovedHandler(item_name, amount, components)
	error('abstract method "_itemRemovedHandler" not implemented')
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
	AbstractSlot = AbstractSlot,
	AbstractInventory = AbstractInventory,
	AbstractCluster = AbstractCluster,
	transfer = transfer,
}
