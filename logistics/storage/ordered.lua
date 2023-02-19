local utils = require('/logos.utils')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

local get_order = utils.get_order
local new_class = utils.new_class

local StandardState = standard.StandardState
local StandardInventory = standard.StandardInventory
local StandardCluster = standard.StandardCluster
local transfer = core.transfer

--------------------------------
-- Ordered State Class.

local OrderedState = new_class(StandardState)

function OrderedState:new(args)
	local newOrderedState = StandardState:new(args)

	setmetatable(newOrderedState, OrderedState)
	return newOrderedState
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
	local newOrderedCluster = StandardCluster:new(args)

	setmetatable(newOrderedCluster, OrderedCluster)
	return newOrderedCluster
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
function OrderedCluster:swap(from_state, to_cluster, to_state)
	if from_state == to_state then
		return
	elseif not from_state:hasItem() then
		--toCluster:move(toState, self, fromState)
		transfer(to_state, from_state, to_cluster, self)
	elseif not to_state:hasItem() then
		--self:move(fromState, toCluster, toState)
		transfer(from_state, to_state, self, to_cluster)
	else
		local swapState = self:inputState('empty')

		if not swapState then
			error("no empty space for swap")
		end

		--self:move(fromState, self, swapState)
		transfer(from_state, swapState, self, self)
		--toCluster:move(toState, self, fromState)
		transfer(to_state, from_state, to_cluster, self)
		--self:move(swapState, toCluster, toState)
		transfer(swapState, to_state, self, to_cluster)
	end
end

-- Sorts the storage.
function OrderedCluster:sort()
	if not self.item_count['empty'] == 0 then
		error("there's no space for swapping")
	end

	-- Current position on the states list.
	local pos = 1
	local cmp = function(a, b) return a > b end

	for _,itemName in ipairs(get_order(self.item_count, cmp)) do
		if itemName ~= 'empty' then
			local all_states = {}
			local item_states = {}

			for _,inv in ipairs(self.invs) do
				for _,state in ipairs(inv.states) do
					all_states[#all_states+1] = state
				end

				if inv.item_states[itemName] then
					for state in inv.item_states[itemName]:iterate() do
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
			for state in inv.item_states[item_name]:iterate() do
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
	for item_name,item_name in pairs(self.item_count) do
		if item_name ~= 'empty' and item_name > 0 then
			self:packItem(item_name)
		end
	end
end

return {
	OrderedState = OrderedState,
	OrderedInventory = OrderedInventory,
	OrderedCluster = OrderedCluster,
}
