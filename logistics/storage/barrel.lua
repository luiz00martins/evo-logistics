local utils = require('/logos.utils')
local dl_list = require('/logos.logistics.utils.dl_list')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

local get_connected_inventories = utils.get_connected_inventories
local table_reduce = utils.table_reduce
local table_contains = utils.table_contains
local array_map = utils.array_map
local new_class = utils.new_class

local StandardState = standard.StandardState
local AbstractInventory = core.AbstractInventory
local AbstractCluster = core.AbstractCluster

local BarrelState = new_class(StandardState)

function BarrelState:_moveItem(targetState, limit)
	-- If the states are the same, there's no need to move an item.
	if self == targetState then return 0 end

	-- If no limit (or negative limit) was given, then we assume every item is to be moved.
	if not limit or limit < 0 then
		limit = self.itemCount()
	end

	return peripheral.call(self:invName(), 'pushItem', targetState:invName(), self:itemName(), limit)
end

-- NOTE: These handle the fact that update makes 'state.full = false'. Which means that the call for 'inputState()' inside 'transfer' will result in an infinite loop, because it checks for 'state.full'. If that check disappears, these can go.
function BarrelState:_handleItemAdded(item_name, amount, previous_handlers)
	self._item.count = self._item.count + amount

	if amount == 0 then
		self.full = true
	end
end

function BarrelState:_handleItemRemoved(item_name, amount, previous_handlers)
	self._item.count = self._item.count - amount

	if amount ~= 0 then
		self.full = false
	end
end


local BarrelInventory = new_class(AbstractInventory)

function BarrelInventory:new(args)
	local newInventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not newInventory then
		return nil
	end

	if not table_contains(peripheral.getMethods(newInventory.name), 'items') then
		error('Inventory ' .. newInventory.name .. ' is not a valid barrel type.')
	end

	newInventory.state = BarrelState:new{
		parent = newInventory,
		slot = 1,
		item = args.item or nil,
		count = args.item and args.item.count or 0,
		full = false,
	}

	setmetatable(newInventory, BarrelInventory)

	return newInventory
end

function BarrelInventory:catalog()
	local items = peripheral.call(self.name, "items")

	local _, item = next(items)
	if item == nil then
		self.itemName = 'empty'
	else
		self.itemName = item.name
	end

	local count = 0
	for _, _item in pairs(items) do
		count = count + _item.count
	end

	self.state = BarrelState:new{
		parent = self,
		slot = 1,
		item = item,
		count = count,
		full = false,
	}
end

function BarrelInventory:refresh()
	local items = peripheral.call(self.name, "items")

	local _, item = next(items)
	if item == nil then
		self.itemName = 'empty'
	else
		self.itemName = item.name
	end

	-- NOTE: We do not update the amount of items here, as we would need to recount them, which is expensive.
end

function BarrelInventory:inputState()
	if self.state.full then
		return nil
	else
		return self.state
	end
end

function BarrelInventory:outputState()
	if self.state:itemCount() == 0 then
		return nil
	else
		return self.state
	end
end

function BarrelInventory:hasItem()
	return self.state:itemCount() > 0
end

function BarrelInventory:itemCount()
	return self.state:itemCount()
end

BarrelInventory.itemIsAvailable = BarrelInventory.hasItem

function BarrelInventory:_handleItemAdded(item_name, amount, previous_handlers)
end

function BarrelInventory:_handleItemRemoved(item_name, amount, previous_handlers)
end

function BarrelInventory:update()
	-- pass
end

function BarrelInventory:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		error('Item name cannot be '..utils.tostring(item_name))
	end

	if self:hasItem() then
		error('Bulk Inventory cannot register item '..utils.tostring(item_name)..', as it still has item '..self.itemName)
	end

	self.itemName = item_name
end

function BarrelInventory:unregisterItem(item_name)
	if item_name == 'empty' then
		error('Item name cannot be '..item_name)
	end

	item_name = item_name or self.itemName
	if item_name ~= self.itemName then
		error('Cannot unregister '..utils.tostring(item_name)..' from inventory registered for '..self.itemName)
	end

	if self:hasItem() then
		error('Cannot unregister '..item_name..' from inventory with '..self.count..' items')
	end

	self.itemName = 'empty'
end

-- Transfers every item to the target inventory, and returns the amount moved. It does not change the inventories internal models.
function BarrelInventory:_bareTransferAll(targetInv)
	local moved = peripheral.call(self.name, 'pushItem', targetInv.name)

	return moved
end

function BarrelInventory:recount(emptyInvs)
	if not emptyInvs then
		error('No empty storages provided')
	end

	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	self:update()
	for _,inv in pairs(emptyInvs) do
		local justMoved = self:_bareTransferAll(inv)
		moved = moved + justMoved

		if justMoved == 0 then
			break
		end
	end
	self:update()

	-- The inventory has to be empty for the count to be valid.
	local emptied = (#peripheral.call(self.name, 'items') == 0)

	-- Undo all moves.
	for _,inv in pairs(emptyInvs) do
		local justMoved = inv:_bareTransferAll(self)
		if justMoved == 0 then
			break
		end
	end

	if not emptied then
		error("not enough empty space in bulk storage to count "..self.itemName)
	end

	self.state._item.count = moved - 1
end


local BarrelCluster = new_class(AbstractCluster)
function BarrelCluster:new (args)
	local newCluster = AbstractCluster:new(args)

 	newCluster._itemCount = {}
	newCluster.invsWithItem = {}

	setmetatable(newCluster, self)
	return newCluster
end

-- Catalogs the cluster (initial setup).
function BarrelCluster:catalog()
end

function BarrelCluster:setItemInventory(inv_name, item_name)
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

function BarrelCluster:_createInventory(args)
	return BarrelInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function BarrelCluster:registerInventory(args)
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
		self._itemCount[item_name] = self._itemCount[item_name] + inv:itemCount()
	end
end

function BarrelCluster:unregisterInventory(inv_name)
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

function BarrelCluster:refresh()
	for _,inv in ipairs(self.invs) do
		inv:refresh()
	end
end

function BarrelCluster:save_data(path)
	local inv_names = array_map(self.invs, function(inv) return inv.name end)
	local inv_items = array_map(self.invs, function(inv)
		return inv.itemName
	end)
	local inv_counts = array_map(self.invs, function(inv)
		return inv:itemCount()
	end)

	local data = {
		inv_names = inv_names,
		inv_items = inv_items,
		inv_counts = inv_counts,
	}

	return textutils.serialize(data)
end

function BarrelCluster:load_data(data)
	data = textutils.unserialize(data)

	local inv_names = data.inv_names
	local inv_items = data.inv_items
	local inv_counts = data.inv_counts
	local connected_inventories_names = get_connected_inventories()

	self._itemCount = {}
	self.invs = {}
	self.invsWithItem = {}

	for i,inv_name in ipairs(inv_names) do
		local item_name = inv_items[i]
		local item_count = inv_counts[i]

		if table_contains(connected_inventories_names, inv_name) then
			local inv = BarrelInventory:new{
				parent = self,
				name = inv_name,
				item = {name = item_name, count = item_count}
			}

			table.insert(self.invs, inv)
			self._itemCount[item_name] = self._itemCount[item_name] or 0
			self._itemCount[item_name] = self._itemCount[item_name] + item_count
			self.invsWithItem[item_name] = self.invsWithItem[item_name] or {}
			table.insert(self.invsWithItem[item_name], inv)
		else
			-- Inventory not found.
		end
	end

	return true
end

function BarrelCluster:data_path()
	return "/logistics_data/"..self.name..".data"
end

function BarrelCluster:invNames()
	return array_map(self.invs, function(inv) return inv.name end, {})
end

function BarrelCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self._itemCount, function(a,b) return a+b end) - (self._itemCount['empty'] or 0)
	end

	return self._itemCount[item_name] or 0
end

BarrelCluster.availableItemCount = BarrelCluster.itemCount

function BarrelCluster:hasItem(itemName)
	if self.invsWithItem[itemName] then
		return true
	else
		return false
	end
end

function BarrelCluster:itemIsAvailable(item_name)
	local function search_invs_item(invs_item)
		for _,inv in pairs(invs_item) do
			if inv:itemIsAvailable() then
				return true
			end
		end

		return false
	end

	if not item_name then
		for item_name,invs_item in pairs(self.invsWithItem) do
			if item_name ~= 'empty' and search_invs_item(invs_item) then
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

function BarrelCluster:itemNames()
	local item_names = {}
	for item_name, _ in pairs(self._itemCount) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function BarrelCluster:_handleItemAdded(item_name, count)
	if not self.invsWithItem[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self._itemCount[item_name] = self._itemCount[item_name] + count

	return true
end

function BarrelCluster:_handleItemRemoved(item_name, count)
	if not self.invsWithItem[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self._itemCount[item_name] = self._itemCount[item_name] - count

	return true
end
-- Returns a state where `itemName` can be inserted to. Returns 'nil' if none are available.
function BarrelCluster:inputState(item_name)
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
function BarrelCluster:outputState(item_name)
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
		for item_name, invs_item in pairs(self.invsWithItem) do
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

function BarrelCluster:recountItem(itemName)
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

function BarrelCluster:registerItem(item_name)
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

function BarrelCluster:unregisterItem(item_name)
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

function BarrelCluster:recount()
	for itemName,_ in pairs(self.invsWithItem) do
		if itemName ~= 'empty' then
			self:recountItem(itemName)
		end
	end
end

return {
	BarrelCluster = BarrelCluster,
}
