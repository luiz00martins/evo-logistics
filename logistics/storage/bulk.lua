---@diagnostic disable: need-check-nil
local utils = require('/logos.utils')
local dl_list = require('/logos.logistics.utils.dl_list')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

local get_connected_inventories = utils.get_connected_inventories
local table_reduce = utils.table_reduce
local array_map = utils.array_map
local new_class = utils.new_class

local StandardState = standard.StandardState
local AbstractInventory = core.AbstractInventory
local AbstractCluster = core.AbstractCluster

local BulkState = new_class(StandardState)

-- NOTE: These handle the fact that update makes 'state.full = false'. Which means that the call for 'inputState()' inside 'transfer' will result in an infinite loop, because it checks for 'state.full'. If that check disappears, these can go.
function BulkState:_handleItemAdded(_, amount, _)
	self:update()
	if amount == 0 then
		self.full = true
	end
	--StandardState._handleItemAdded(self, item_name, amount, previous_handlers)
end

function BulkState:_handleItemRemoved(_, _, _)
	self:update()
	--StandardState._handleItemRemoved(self, item_name, amount, previous_handlers)
end

---------------------------------------------------------
-- Bulk Storage Cluster

local BulkInv = {
	NORMAL = new_class(AbstractInventory),
	IO_SLOTS = new_class(AbstractInventory),
}

function BulkInv:new(args)
	local newInventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not newInventory then
		return nil
	end

	-- TODO: This shouldn't be autodetect, you should put it manually (with the option to autodetect).
	if newInventory.size == 2 then
		setmetatable(newInventory, BulkInv.IO_SLOTS)
	else
		setmetatable(newInventory, BulkInv.NORMAL)
	end

	return newInventory
end

function BulkInv.NORMAL:catalog()
	local items = peripheral.call(self.name, "list")

	-- Figuring out which item is in storage.
	if next(items) == nil then
		self.itemName = 'empty'
	else
		local _, item = next(items)
		self.itemName = item.name
	end

	self.count = 0
	self.itemStates = dl_list()
	self.emptyStates = dl_list()

	-- Building list of item states.
	local state
	for slot=1,self.size do
		state = BulkState:new{
			parent = self,
			slot = slot,
			item = items[slot],
			full = false,
		}
		local item_name = state:itemName()

		if item_name == 'empty' then
			self.emptyStates:push(state)
		elseif item_name == self.itemName then
			self.itemStates:push(state)
			self.count = self.count + state:itemCount()
		else
			error("bulk inventory "..self.name.." contains two different items("..self.itemName.." and "..item_name..")")
		end
	end
end

function BulkInv.IO_SLOTS:catalog()
	local items = peripheral.call(self.name, "list")

	self.count = 0

	-- BUG: Even if the cluster has no clue about this item, and thinks there are 0 of this item in inventory, the inv's item is set to the item's name.
	-- Figuring out which item is in storage.
	local _, item = next(items)
	if item == nil then
		self.itemName = 'empty'
	else
		self.itemName = item.name
	end

	-- We assume that the first slot is input, and the second is output.
	self.inState = BulkState:new{
		parent = self,
		slot = 1,
		item = items[1],
		full = false,
	}
	self.outState = BulkState:new{
		parent = self,
		slot = 2,
		item = items[2],
		full = false,
	}
end

function BulkInv.NORMAL:inputState()
	if self.itemStates.last and not self.itemStates.last.full then
		return self.itemStates.last
	elseif self.emptyStates.last then
		return self.emptyStates.last
	end

	-- In case the last slot was full, and there's no empty, we check the other ones to make *sure* that there's no spare space.
	for state in self.itemStates:iterate() do
		if not state.full then
			return state
		end
	end

	-- No spare space was found.
	return nil
end

function BulkInv.IO_SLOTS:inputState()
	if not self.inState.full then
		return self.inState
	else
		return nil
	end
end

function BulkInv.NORMAL:outputState()
	if self.itemStates.last then
		return self.itemState.last
	end

	-- No item in storage.
	return nil
end

function BulkInv.IO_SLOTS:outputState()
	if self.outState:itemCount() > 0 then
		return self.outState
	else
		return nil
	end
end

function BulkInv.NORMAL:hasItem()
	return self.count > 0
end

function BulkInv.IO_SLOTS:hasItem()
	return self.outState:itemCount() > 0
end

function BulkInv.NORMAL:hasItem()
	return self.count > 1
end

function BulkInv.IO_SLOTS:itemCount()
	return self.count
end

function BulkInv.NORMAL:itemCount()
	return self.count
end

function BulkInv.IO_SLOTS:itemIsAvailable()
	return self.outState:itemCount() > 0
end

function BulkInv.NORMAL:_handleItemAdded(item_name, amount, previous_handlers)
end

local MAX_UPDATE_WAIT_TIME = 0.02
function BulkInv.IO_SLOTS:_handleItemAdded(_, amount, _)
	self.count = self.count + amount
end

function BulkInv.NORMAL:_handleItemRemoved(item_name, amount, previous_handlers)
end

function BulkInv.IO_SLOTS:_handleItemRemoved(_, amount, _)
	self.count = self.count - amount
end

function BulkInv.NORMAL:update()
	self:catalog()
end

function BulkInv.IO_SLOTS:update()
	os.sleep(MAX_UPDATE_WAIT_TIME)
	self.outState:update()
	self.inState:update()
end

function BulkInv.IO_SLOTS:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	if self:hasItem() then
		error('Bulk Inventory cannot register item '..item_name..', as it still has item '..self.itemName)
	end

	self.itemName = item_name
end

function BulkInv.NORMAL:registerItem(item_name)
	-- TODO:
	error('TODO')
end

function BulkInv.IO_SLOTS:unregisterItem(item_name)
	if item_name == 'empty' then
		error('Item name cannot be '..item_name)
	end

	item_name = item_name or self.itemName
	if item_name ~= self.itemName then
		error('Cannot unregister '..item_name..' from inventory registered for '..self.itemName)
	end
	self.itemName = 'empty'
end

function BulkInv.NORMAL:unregisterItem(item_name)
	-- TODO:
	error('TODO')
end

function BulkInv.NORMAL:recount(_)
	self:catalog()
end

-- Transfers every item to the target inventory, and returns the amount moved. It does not change the inventories internal models.
function BulkInv.IO_SLOTS:_bareTransferAll(targetInv)
	local MAX_ATTEMPTS = 3

	local fromState = self.outState
	local toState = targetInv.inState
	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	local failed_attempts = 0
	while fromState and toState and fromState:hasItem() do
		local oldItem = fromState:item()
		local justMoved = fromState:bareMoveItem(toState)
		moved = moved + justMoved

		-- TODO: Switch this out to specific state code inside the state...
		if justMoved == 0 then
			failed_attempts = failed_attempts + 1

			os.sleep(MAX_UPDATE_WAIT_TIME / ((MAX_ATTEMPTS+1) - failed_attempts))

			if failed_attempts >= MAX_ATTEMPTS then
				break
			end
		else
			failed_attempts = 0
			-- ...possibly by putting this in the state.
			fromState._item = {
				name = oldItem.name,
				count = 64
			}
			toState._item = nil
		end

		fromState = self.outState
		toState = targetInv:inputState()
	end

	return moved
end
BulkInv.NORMAL._bareTransferAll = BulkInv.IO_SLOTS._bareTransferAll

function BulkInv.IO_SLOTS:recount(emptyInvs)
	if not emptyInvs then
		error('No empty storages provided')
	end

	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	self:update()
	for _,inv in pairs(emptyInvs) do
		local justMoved = self:_bareTransferAll(inv)
		moved = moved + justMoved

		inv:update()

		if justMoved == 0 or not self:hasItem() then
			break
		end
	end
	self:update()

	-- The inventory has to be empty for the count to be valid.
	local emptied = not self:hasItem()
	--print(self.outState:itemCount())

	-- Undo all moves.
	for _,inv in pairs(emptyInvs) do
		local justMoved = inv:_bareTransferAll(self)
		inv:update()
		if justMoved == 0 then
			break
		end
	end
	self:update()

	if not emptied then
		error("not enough empty space in bulk storage to count "..self.itemName)
	end

	self.count = moved - 1
end


local BulkCluster = new_class(AbstractCluster)
function BulkCluster:new (args)
	local newCluster = AbstractCluster:new(args)

 	newCluster._itemCount = {}
	newCluster.invsWithItem = {}

	setmetatable(newCluster, self)
	return newCluster
end

-- Catalogs the cluster (initial setup).
function BulkCluster:catalog()
	self.invs = {}
	self.invsWithItem = {}
	self._itemCount = {}

	for _,invName in ipairs(self:invNames()) do
		local inv = BulkInv:new{
			parent = self,
			name = invName,
		}
		inv:catalog()

		local item_name = inv.itemName

		-- Creating stats for item if it doesn't exist.
		if not self.invsWithItem[item_name] then self.invsWithItem[item_name] = {} end
		if not self._itemCount[item_name] then self._itemCount[item_name] = 0 end

		table.insert(self.invs, inv)
		table.insert(self.invsWithItem[item_name], inv)

		if item_name == 'empty' then
			self._itemCount['empty'] = self._itemCount['empty'] + 1
		end
	end

	self:recount()
end

function BulkCluster:setItemInventory(inv_name, item_name)
	for _,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			if inv:hasItem() and inv.itemName ~= item_name then
				error('Trying to set inventory '..inv_name..' to item '..item_name..', but i\'s already with item '..inv.itemName)
			end

			if inv.itemName then
				-- Removing from previous.
				for i,invv in ipairs(self.invsWithItem[inv.itemName]) do
					if inv == invv then
						table.remove(self.invsWithItem[inv.itemName], i)
						if #self.invsWithItem[inv.itemName] == 0 then
							self.invsWithItem[inv.itemName] = nil
						end
						inv.itemName = nil
						break
					end
				end
			end

			-- Adding new one.
			self.invsWithItem[item_name] = self.invsWithItem[item_name] or {}
			self._itemCount[item_name] = self._itemCount[item_name] or 0
			inv.itemName = item_name
			table.insert(self.invsWithItem[item_name], inv)

			return
		end
	end

	error('Inventory '..inv_name..' not present in cluster '..self.name)
end

function BulkCluster:_createInventory(args)
	return BulkInv:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function BulkCluster:registerInventory(args)
	local inv = self:_createInventory(args)
	inv:catalog()

	local item_name = inv.itemName

	-- Creating stats for item if it doesn't exist.
	if not self.invsWithItem[item_name] then self.invsWithItem[item_name] = {} end
	if not self._itemCount[item_name] then self._itemCount[item_name] = 0 end

	table.insert(self.invs, inv)
	table.insert(self.invsWithItem[item_name], inv)

	if item_name == 'empty' then
		self._itemCount['empty'] = self._itemCount['empty'] + 1
	else
		inv:recount(self.invsWithItem['empty'])
		self._itemCount[item_name] = self._itemCount[item_name] + inv.count
	end
end

function BulkCluster:unregisterInventory(inv_name)
	local pos,inv
	for p,i in ipairs(self.invs) do
		if i.name == inv_name then
			pos = p
			inv = i
			break
		end
	end

	if not inv then
		error('Inventory '..inv_name..' not found in cluster '..self.name)
	end

	table.remove(self.invs, pos)

	for p,i in ipairs(self.invsWithItem[inv.itemName]) do
		if i == inv then
			pos = p
			break
		end
	end
	table.remove(self.invsWithItem[inv.itemName], pos)

	-- HACK: This is a hack to attend for the name bug inside ´BulkInv:new´.
	if inv.itemName == 'empty' or not self._itemCount[inv.itemName] or self._itemCount[inv.itemName] == 0 then
		self._itemCount['empty'] = self._itemCount['empty'] - 1
	else
		self._itemCount[inv.itemName] = self._itemCount[inv.itemName] - inv.count
	end
end

function BulkCluster:refresh()
	local inv_names = self:invNames()

	self.invsWithItem = {}
	self.invs = {}

	for _,invName in ipairs(inv_names) do
		local inv = BulkInv:new{
			parent = self,
			name = invName,
		}
		inv:catalog()
		local item_name = inv.itemName

		-- Creating stats for item if it doesn't exist.
		self.invsWithItem[item_name] = self.invsWithItem[item_name] or {}
		self._itemCount[item_name] = self._itemCount[item_name] or 0

		-- Updating invs.
		self.invs[#self.invs+1] = inv
		-- Updating invsWithItem.
		table.insert(self.invsWithItem[item_name], inv)
		-- Updating item count.
		if item_name == 'empty' then
			self._itemCount['empty'] = self._itemCount['empty'] + 1
		end
	end
end

function BulkCluster:save_data()
	local inv_names = array_map(self.invs, function(inv) return inv.name end)
	local inv_items = array_map(self.invs, function(inv)
		return inv.itemName
	end)
	local inv_counts = array_map(self.invs, function(inv)
		return inv.count
	end)

	local data = {
		inv_names = inv_names,
		inv_items = inv_items,
		inv_counts = inv_counts,
	}

	return textutils.serialize(data)
end

function BulkCluster:load_data(data)
	data = textutils.unserialize(data)

	local inv_names = data.inv_names
	local inv_items = data.inv_items
	local inv_counts = data.inv_counts
	local connected_inventories_names = get_connected_inventories()

	self._itemCount = {}
	self.invs = {}

	for i,inv_name in ipairs(inv_names) do
		local item_name = inv_items[i]
		local item_count = inv_counts[i]

		if table.contains(connected_inventories_names, inv_name) then
			local inv = BulkInv:new{
				parent = self,
				name = inv_name,
			}
			inv.count = item_count

			table.insert(self.invs, inv)
			self._itemCount[item_name] = self._itemCount[item_name] or 0

			self._itemCount[item_name] = self._itemCount[item_name] + item_count
		else
			-- Inventory not found.
		end
	end

	return true
end

function BulkCluster:data_path()
	return "/logistics_data/"..self.name..".data"
end

function BulkCluster:invNames()
	return array_map(self.invs, function(inv) return inv.name end, {})
end

function BulkCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self._itemCount, function(a,b) return a+b end) - (self._itemCount['empty'] or 0)
	end

	return self._itemCount[item_name] or 0
end

BulkCluster.availableItemCount = BulkCluster.itemCount

function BulkCluster:hasItem(itemName)
	if self.invsWithItem[itemName] then
		return true
	else
		return false
	end
end

function BulkCluster:itemIsAvailable(item_name)
	local function search_invs_item(invs_item)
		for _,inv in pairs(invs_item) do
			if inv:itemIsAvailable() then
				return true
			end
		end

		return false
	end

	if not item_name then
		for _item_name,invs_item in pairs(self.invsWithItem) do
			if _item_name ~= 'empty' and search_invs_item(invs_item) then
				return true
			end
		end
	else
		if not self.invsWithItem[item_name] then
			return false
		end

		return search_invs_item(self.invsWithItem[item_name])
	end

	return false
end

function BulkCluster:itemNames()
	local item_names = {}
	for item_name, _ in pairs(self._itemCount) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function BulkCluster:_handleItemAdded(item_name, count)
	if not self.invsWithItem[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self._itemCount[item_name] = self._itemCount[item_name] + count

	return true
end

function BulkCluster:_handleItemRemoved(item_name, count)
	if not self.invsWithItem[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self._itemCount[item_name] = self._itemCount[item_name] - count

	return true
end
-- Returns a state where `itemName` can be inserted to. Returns 'nil' if none are available.
function BulkCluster:inputState(item_name)
	if not item_name or item_name == 'empty' then error('Item name required ("'..(item_name or 'nil')..'" provided)') end
	if not self.invsWithItem[item_name] then
		return nil
	end

	local state
	for _, inv in pairs(self.invsWithItem[item_name]) do
		state = inv:inputState()

		if state then
			return state
		end
	end

	return nil
end
-- Returns a state from which `itemName` can be drawn from. Returns 'nil' if none are available.
function BulkCluster:outputState(item_name)
	-- NOTE: Yes, the worst case of this is O(n). However, the average case is O(1).
	local function search_invs_item(invs_item)
		for _, inv in pairs(invs_item) do
			local state = inv:outputState()

			if state then
				return state
			end
		end

		return nil
	end

	if not item_name then
		for _, invs_item in pairs(self.invsWithItem) do
			local state = search_invs_item(invs_item)
			if state then return state end
		end
	else
		if not self.invsWithItem[item_name] then
			return nil
		end

		local state = search_invs_item(self.invsWithItem[item_name])
		if state then return state end
	end

	return nil
end

function BulkCluster:recountItem(itemName)
	if itemName == 'empty' then
		error("can't recount empty item")
	end
	if not self.invsWithItem[itemName] then
		error("item '"..itemName.."' does not exist in bulk storage")
	end

	self._itemCount[itemName] = 0
	for _,inv in pairs(self.invsWithItem[itemName]) do
		inv:recount(self.invsWithItem['empty'])
		self._itemCount[itemName] = self._itemCount[itemName] + inv.count
	end
end

function BulkCluster:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	local empty_invs = self.invsWithItem['empty']
	if not empty_invs or #empty_invs == 0 then
		error('No empty inventories found')
	end

	local inv = empty_invs[#empty_invs]

	-- Removing inv from the 'empty' list.
	empty_invs[#empty_invs] = nil
	-- Making sure to clean up if there's nothing in the list.
	if #self.invsWithItem['empty'] == 0 then
		self.invsWithItem['empty'] = nil
	end

	-- Making sure the item's list exists.
	self.invsWithItem[item_name] = self.invsWithItem[item_name] or {}
	self._itemCount[item_name] = self._itemCount[item_name] or 0
	-- Adding inv to the item's list.
	table.insert(self.invsWithItem[item_name], inv)

	inv:registerItem(item_name)
end

function BulkCluster:unregisterItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	local item_invs = self.invsWithItem[item_name]
	local empty_invs = self.invsWithItem['empty']

	for _,inv in ipairs(item_invs) do
		if inv:hasItem() then
			error('Cannot unregister '..item_name..' from '..inv.name..', as there are still items inside.')
		end
	end

	for _,inv in ipairs(item_invs) do
		inv:unregisterItem(item_name)
		table.insert(empty_invs, inv)
	end

	self.invsWithItem[item_name] = nil
	self._itemCount[item_name] = nil
end

function BulkCluster:recount()
	for itemName,_ in pairs(self.invsWithItem) do
		if itemName ~= 'empty' then
			self:recountItem(itemName)
		end
	end
end

return {
	BulkCluster = BulkCluster,
}
