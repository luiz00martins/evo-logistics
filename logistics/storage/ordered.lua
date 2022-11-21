local utils = require('/logos.utils')
local dl_list = require('/logos.logistics.utils.dl_list')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

local table_reduce = utils.table_reduce
local get_order = utils.get_order
local reversed_ipairs = utils.reversed_ipairs
local new_class = utils.new_class

local StandardState = standard.StandardState
local StandardInventory = standard.StandardInventory
local StandardCluster = standard.StandardCluster
local transfer = core.transfer

--------------------------------
-- Ordered State Class.

local OrderedState = new_class(StandardState)

function OrderedState:new(args)
	local newState = StandardState:new(args)

	setmetatable(newState, OrderedState)
	return newState
end

function OrderedState:invPos()
	return self.parent.pos
end

function OrderedState:isBefore(other)
    return (self:invPos() < other:invPos() or (self:invPos() == other:invPos() and self.slot < other.slot))
end

function OrderedState:isAfter(other)
    return (self:invPos() > other:invPos() or (self:invPos() == other:invPos() and self.slot > other.slot))
end

function OrderedState:isAt(other)
    return (self:invPos() == other:invPos() and self.slot == other.slot)
end

--------------------------------
-- Ordered Storage Inventory

local OrderedInventory = new_class(StandardInventory)

function OrderedInventory:new(args)
	local newInventory = StandardInventory:new(args)

	-- Could not find inventory.
	if not newInventory then
		return nil
	end

	if args.pos == nil then error("missing parameter `pos`") end

	newInventory.pos = args.pos

	setmetatable(newInventory, self)
	return newInventory
end

function OrderedInventory:_repopulate()
	local items = peripheral.call(self.name, "list")
	local states = {}

	for slot=1,self.size do
		local state = OrderedState:new{
			parent = self,
			slot = slot,
			_item = items[slot],
		}

		states[#states+1] = state
	end

	self.states = states
end

OrderedInventory.refresh = OrderedInventory.catalog

--------------------------------
-- Ordered Storage Cluster

local OrderedCluster = new_class(StandardCluster)
function OrderedCluster:new(args)
	local newCluster = StandardCluster:new(args)
	
	setmetatable(newCluster, OrderedCluster)
	return newCluster
end

-- Adds a new inventory to the cluster. Data for the inventory may be build.
function OrderedCluster:registerInventory(inv_name)
	local inv = OrderedInventory:new{
		parent = self,
		name = inv_name,
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

-- Swaps the item in `fromState` with the item in `toState`.
function OrderedCluster:swap(fromState, toCluster, toState)
	if fromState == toState then
		return
	elseif not fromState:hasItem() then
		--toCluster:move(toState, self, fromState)
		transfer(toState, fromState, toCluster, self)
	elseif not toState:hasItem() then
		--self:move(fromState, toCluster, toState)
		transfer(fromState, toState, self, toCluster)
	else
		local swapState = self:inputState('empty')

		if not swapState then
			error("no empty space for swap")
		end

		--self:move(fromState, self, swapState)
		transfer(fromState, swapState, self, self)
		--toCluster:move(toState, self, fromState)
		transfer(toState, fromState, toCluster, self)
		--self:move(swapState, toCluster, toState)
		transfer(swapState, toState, self, toCluster)
	end
end

-- Sorts the storage.
function OrderedCluster:sort()
	if not self._itemCount['empty'] == 0 then
		error("there's no space for swapping")
	end

	-- Current position on the states list.
	local pos = 1
	local cmp = function(a, b) return a > b end

	for _,itemName in ipairs(get_order(self._itemCount, cmp)) do
		if itemName ~= 'empty' then
			local all_states = {}
			local item_states = {}

			for _,inv in ipairs(self.invs) do
				for _,state in ipairs(inv.states) do
					all_states[#all_states+1] = state
				end

				if inv.itemStates[itemName] then
					for state in inv.itemStates[itemName]:iterate() do
						item_states[#item_states+1] = state
					end
				end
			end

			for _,state in ipairs(item_states) do
				if state:isAfter(all_states[pos]) then
					self:swap(state, self, all_states[pos])
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
	local item_states = {}
	for _, inv in ipairs(self.invs) do
		if inv:hasItem(item_name) then
			for state in inv.itemStates[item_name]:iterate() do
				item_states[#item_states+1] = state
			end
		end
	end

	local head = 1
	local tail = #item_states

	while head ~= tail do
		--local moved = self:move(item_states[tail], self, item_states[head])
		local moved = transfer(item_states[tail], item_states[head], self, self)

		if moved == 0 then
			head = head + 1
		else
			if not item_states[tail]:hasItem() then
				tail = tail - 1
			end
		end
	end
end

function OrderedCluster:pack()
	for itemName,itemCount in pairs(self._itemCount) do
		if itemName ~= 'empty' and itemCount > 0 then
			self:packItem(itemName)
		end
	end
end

return {
	OrderedState = OrderedState,
	OrderedInventory = OrderedInventory,
	OrderedCluster = OrderedCluster,
}
