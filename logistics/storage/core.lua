local utils = require('/logos.utils')
local new_class = utils.new_class


local function _is_parent(first, final)
	if not first then error('"first" argument not provided') end
	if not final or first == final then return true end

	local current = first.parent
	-- WARNING: This _will_ infinite loop on a cycle. However, there should not be any parenting cycles, so if that happens, it's an error on the caller.
	while current do
		if current == final then return true end
		current = current.parent
	end

	return false
end

local function _execute_handlers(output, input, output_handler, input_handler, item_name, amount)
	local previous_handlers = {}
	local successful = true
	while true do
		if output:_handleItemRemoved(item_name, amount, previous_handlers) == false then
			successful = false
		end
		table.insert(previous_handlers, output)

		output = output.parent
		if not output then
			break
		elseif output == output_handler then
			output:_handleItemRemoved(item_name, amount, previous_handlers)
			break
		end
	end

	local previous_handlers = {}
	while true do
		if input:_handleItemAdded(item_name, amount, previous_handlers) == false then
			successful = false
		end
		table.insert(previous_handlers, input)

		input = input.parent
		if not input then
			break
		elseif input == input_handler then
			input:_handleItemAdded(item_name, amount, previous_handlers)
			break
		end
	end

	return successful
end

-- 'handler' and 'target_handler' are the _highest_ handlers specified. This function will execute the handlers from the lowest level (State) to the highest specifies.
-- For example, if you specify 'self' self as a State and 'handler' as its Cluster, the order of execution will be (State -> Inventory -> Cluster). If you specify the 'handler' as its Inventory, the order of execution will be (State -> Inventory). If you specify the 'handler' as itself, it'll only update itself (State).
local function transfer(output, input, output_handler, input_handler, item_name, limit)
	-- NOTE: This is a very important line, and should not be removed.
	-- This line guarantees that _no_ attempt will ever be made to move 0 items. This means that, if the amount of items moved is 0, then a move failed.
	-- Therefore, it allows the handlers to detect failed moved attempts (such as filled slots).
	if limit and limit <= 0 then return 0 end

	output_handler = output_handler or output
	input_handler = input_handler or input

	if not _is_parent(output, output_handler) then
		error((output_handler.name or 'nil')..' is not a parent of '..(output.name or 'nil'))
	end
	if not _is_parent(input, input_handler) then
		error((input_handler.name or '<no name>')..' is not a parent of '..(input.name or '<no name>'))
	end

	local output_state = output:outputState(item_name)
	local input_state
	if output_state then
		input_state = input:inputState(output_state:itemName())
	else
		return 0
	end
	local moved = 0

	local upper_bound
	if limit then
		upper_bound = function() return limit-moved end
	else
		upper_bound = function() return nil end
	end

	while output:itemIsAvailable(item_name) and input_state and output_state and (not limit or moved < limit) do
		repeat
			-- Moving item
			local moved_item_name = output_state:itemName()
			-- TODO: This should be a raw 'peripheral' operation.
			local just_moved = output_state:_moveItem(input_state, upper_bound())
			moved = moved + just_moved

			local successful = _execute_handlers(output_state, input_state, output_handler, input_handler, moved_item_name, just_moved)
		until successful

		output_state = output:outputState(item_name)
		if output_state then
			input_state = input:inputState(output_state:itemName())
		end
	end

	return moved
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

function AbstractState:_moveItem(targetState, limit)
	local item = self:item()

	-- If there`s no item to move, return 0.
	if not item then return 0 end
	-- If the states are the same, there's no need to move an item.
	if self == targetState then return 0 end

	-- If no limit (or negative limit) was given, then we assume every item is to be moved.
	if not limit or limit < 0 then
		limit = item.count
	end

	-- Moving item
	local moved = peripheral.call(
			self:invName(), "pushItems",
			targetState:invName(), self.slot, limit, targetState.slot
		)

	-- Updating internal states.
	--self:_removeItem(moved)
	--targetState:_addItem(item.name, moved)

	return moved
end

-- Executes when an item is removed to the state.
function AbstractState:_handleItemAdded(item_name, amount, previous_handlers)
	error('abstract method "_handleItemAdded" not implemented')
end

-- Executes when an item is added to the state.
function AbstractState:_handleItemRemoved(item_name, amount, previous_handlers)
	error('abstract method "_handleItemRemoved" not implemented')
end

-- [Maybe] TODO: Put this and 'inputState's implementation in `StandardState` (I mean, it literally references 'self.full' ffs).
function AbstractState:outputState(item_name)
	if not item_name then
		if self:itemIsAvailable() then
			return self
		else
			return nil
		end
	elseif item_name == self:itemName() then
		return self
	else
		return nil
	end
end

function AbstractState:inputState(item_name)
	if not item_name then
		if self:hasItem() then
			return nil
		else
			return self
		end
	else
		local self_item_name = self:itemName()
		if self_item_name == 'empty' or item_name == self_item_name and not self.full then
			return self
		end

		return nil
	end
end


local AbstractInventory = new_class()
function AbstractInventory:new(args)
	if not args then error("missing args") end

	if args.name == nil then error("missing parameter `name`") end

	local newInventory = {
			name = args.name,
			parent = args.parent,
			size = peripheral.call(args.name, "size"),
			states = {},
		}

	-- This is the case in which the inventory was not found in the network.
	if not newInventory.size then
		return nil
	end

	setmetatable(newInventory, self)
	return newInventory
end

-- Returns whether `item_name` is available (for output) in the inventory.
function AbstractInventory:itemIsAvailable(item_name)
	error('abstract method "itemIsAvailable" not implemented')
end

-- Executes when an item is added to the inventory.
function AbstractInventory:_handleItemAdded(item_name, amount)
	error('abstract method "_handleItemAdded" not implemented')
end

-- Executes when an item is removed from the inventory.
function AbstractInventory:_handleItemRemoved(item_name, amount)
	error('abstract method "_handleItemRemoved" not implemented')
end

local AbstractCluster = new_class()
function AbstractCluster:new(args)
	local newCluster = {
			name = args.name or '',
			invs = args.invs or {},
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
function AbstractCluster:save_data()
	error('abstract method "save_data" not implemented')
end
-- Loads the cluster's data (in the same format as the 'save_data' function).
function AbstractCluster:load_data(data)
	error('abstract method "load_data" not implemented')
end
-- Returns whether `itemName` exists in the cluster.
function AbstractCluster:hasItem(itemName)
	error('abstract method "hasItem" not implemented')
end
-- Returns whether `item_name` is available (for output) in the cluster.
function AbstractCluster:itemIsAvailable(item_name)
	error('abstract method "itemIsAvailable" not implemented')
end
-- Returns all items available in the cluster.
function AbstractCluster:itemNames()
	error('abstract method "itemNames" not implemented')
end
-- Is called when the cluster is the target of a moved item. This should be used for bookeeping, such as updating the amount of items in storage and internal data structures.
function AbstractCluster:_addedTo(state, itemName, count)
	error('abstract method "_addedTo" not implemented')
end
-- Is called when the cluster is the origin of a moved item. This should be used for bookeeping, such as updating the amount of items in storage and internal data structures.
function AbstractCluster:_removedFrom(state, itemName, count)
	error('abstract method "_removedFrom" not implemented')
end
-- Returns a state where `itemName` can be inserted to. Returns 'nil' if none are available.
function AbstractCluster:inputState(itemName)
	error('abstract method "inputState" not implemented')
end
-- Returns a state from which `itemName` can be drawn from. Returns 'nil' if none are available.
function AbstractCluster:outputState(itemName)
	error('abstract method "outputState" not implemented')
end
-- Adds a new inventory to the cluster. Data for the inventory may be build.
function AbstractCluster:registerInventory(inv_name)
	error('abstract method "registerInventory" not implemented')
end
-- Removes an inventory from the cluster. Data from the inventory may be deleted.
function AbstractCluster:unregisterInventory(inv_name)
	error('abstract method "unregisterInventory" not implemented')
end
-- Executes when an item is added to the cluster.
function AbstractCluster:_handleItemAdded(item_name, amount)
	error('abstract method "_handleItemAdded" not implemented')
end
-- Executes when an item is removed from the cluster.
function AbstractCluster:_handleItemRemoved(item_name, amount)
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

-- Returning classes.
return {
	AbstractState = AbstractState,
	AbstractInventory = AbstractInventory,
	AbstractCluster = AbstractCluster,
	transfer = transfer,
}
