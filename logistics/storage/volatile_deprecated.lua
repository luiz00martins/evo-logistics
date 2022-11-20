local utils = require('/logos.utils')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

table.contains = utils.table_contains
local get_connected_inventories = utils.get_connected_inventories
local new_class = utils.new_class

local StandardState = standard.StandardState
local AbstractInventory = core.AbstractInventory
local AbstractCluster = core.AbstractCluster

------ Volatile Cluster ------

-- Volatile Cluster never assumes stability in the inventory, and _expects_ items to be removed, added, and moved around, even _during_ operations. Therefore, it's useful for import, export, and IO storage containers.
-- The rule of thumb for volatile storage is: It acts as a normal storage, until something unexpected happens (that may be derivative of a storage change) 

-- Volatile Inventory class
local VolatileInventory = new_class(AbstractInventory)

function VolatileInventory:new(args)
	local newInventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not newInventory then
		return nil
	end

	local items = peripheral.call(newInventory.name, "list")

	newInventory.states = {}
	for i=1,newInventory.size do
		newInventory.states[i] = StandardState:new{
			parent = newInventory,
			slot = i,
			full = false,
			item = items[i],
		}
	end

	setmetatable(newInventory, self)
	return newInventory
end

function VolatileInventory:catalog()
	local items = peripheral.call(self.name, "list")

	for i=1,#self.states do
		self.states[i]._item = items[i]
	end
end

VolatileInventory.refresh = VolatileInventory.catalog

function VolatileInventory:inputState(item_name)
	for _,state in ipairs(self.states) do
		if not state:hasItem() or (state:itemName() == item_name and not state.full) then
			return state
		end
	end

	return nil
end

function VolatileInventory:outputState(item_name)
	if not item_name then
		for _,state in ipairs(self.states) do
			if state:hasItem() then
				return state
			end
		end
	end

	for _,state in ipairs(self.states) do
		if state:itemName() == item_name then
			return state
		end
	end

	return nil
end
function VolatileInventory:_handleItemAdded(item_name, count)
end
function VolatileInventory:_handleItemRemoved(item_name, count)
end

-- Volatile Cluster class
local VolatileCluster = new_class(AbstractCluster)

function VolatileCluster:new (args)
	local newCluster = AbstractCluster:new(args)

	setmetatable(newCluster, self)
	return newCluster
end

function VolatileCluster:catalog()
	for i,inv in pairs(self.invs) do
		inv:catalog()
	end
end

VolatileCluster.refresh = VolatileCluster.catalog

function VolatileCluster:itemNames()
	error('Method "itemNames" is not supported by volatile cluster')
end

function VolatileCluster:save(path)
	local inv_names = {}

	-- TODO: Change stuff like this to use a 'table.imap' and 'table.map' to simulate more functional like iterators.
	for i,inv in ipairs(self.invs) do
		inv_names[i] = inv.name
	end

	-- TODO: Change this to 'inv_names' (instead of 'invNames').
	local contents = {
		invNames = inv_names,
	}

	local file = fs.open(path, "w")
	file.write(textutils.serialize(contents))
	file.close()
end

function VolatileCluster:load(path)
	local file = fs.open(path, "r")
	if not file then
		return false
	end

	local contents = textutils.unserialize(file.readAll())
	file.close()

	local connected_inventories_names = get_connected_inventories()
	local inv_names = contents.invNames

	self.invs = {}
	for i,inv_name in ipairs(inv_names) do
		if table.contains(connected_inventories_names, inv_name) then
			self.invs[i] = VolatileInventory:new{
				parent = self,
				name = inv_name,
			}
		else
			-- Inventory not found.
		end
	end

	return true
end
-- Returns whether `itemName` exists in the cluster.
function VolatileCluster:hasItem(item_name)
	return self:outputState(item_name) ~= nil
end
-- Returns whether `itemName` is available (for output) in the cluster.
VolatileCluster.itemIsAvailable = VolatileCluster.hasItem

function VolatileCluster:_handleItemAdded(item_name, count)
	if count ~= 0 then
		self.was_last_successful = true
		return true
	elseif self.was_last_successful then
		self:refresh()

		self.was_last_successful = false
		return false
	else
		self.was_last_successful = true
		return true
	end
end

function VolatileCluster:_handleItemRemoved(item_name, count)
	if count ~= 0 then
		self.was_last_successful = true
		return true
	elseif self.was_last_successful then
		self:refresh()

		self.was_last_successful = false
		return false
	else
		self.was_last_successful = true
		return true
	end
end
-- Returns a state where `itemName` can be inserted to. Returns 'nil' if none are available.
-- TODO: I think this can be optimized for all applications by creating a 'inputStates' and 'outputStates' which returns all possible input states.
function VolatileCluster:inputState(item_name)
	for _,inv in ipairs(self.invs) do
		local state = inv:inputState(item_name)

		if state then
			return state
		end
	end

	return nil
end
-- Returns a state from which `itemName` can be drawn from. Returns 'nil' if none are available.
function VolatileCluster:outputState(item_name)
	for _,inv in ipairs(self.invs) do
		local state = inv:outputState(item_name)

		if state then
			return state
		end
	end

	return nil
end

function VolatileCluster:registerInventory(inv_name)
	self.invs[#self.invs+1] = VolatileInventory:new{
		parent = self,
		name = inv_name,
	}
end

function VolatileCluster:unregisterInventory(inv_name)
	for i,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			table.remove(self.invs, i)
			return
		end
	end

	error('Inventory '..inv_name..' not found in cluster '..self.name)
end

return {
	VolatileInventory = VolatileInventory,
	VolatileCluster = VolatileCluster,
}
