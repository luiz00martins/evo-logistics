---@diagnostic disable: need-check-nil
local utils = require('/logos-library.utils.utils')
local abstract = require('/logos-library.core.abstract')

local table_reduce = utils.table_reduce
local table_contains = utils.table_contains
local array_map = utils.array_map
local new_class = utils.new_class

local AbstractInventory = abstract.AbstractInventory
local AbstractCluster = abstract.AbstractCluster

local SHAPELESS_COMPONENT_PRIORITY = 2

local function _getPriority(_) return SHAPELESS_COMPONENT_PRIORITY end

local _memoized_get_item_detail_data = {}
local function memoized_get_item_detail(item_name, inv_name)
	if _memoized_get_item_detail_data[item_name] then
		return _memoized_get_item_detail_data[item_name]
	end

	local item_detail = peripheral.call(inv_name, 'items')[1]

	-- We only save the consistent data.
	_memoized_get_item_detail_data[item_name] = {
		maxCount = item_detail.maxCount,
		displayName = item_detail.displayName,
	}

	return _memoized_get_item_detail_data[item_name]
end

local function _barePushItems(_, output_components, input_components, limit)
	local item_name = output_components.inventory:itemName()

	local origin = input_components.self
	if origin.component_type == 'slot' then
		limit = origin:_inputLimit(item_name, memoized_get_item_detail(item_name, output_components.inventory.name).maxCount)
	end

	local moved = peripheral.call(output_components.inventory.name, 'pushItem', input_components.inventory.name, item_name, limit)

	if origin.component_type == 'slot' and moved > 0 then
		origin.parent:_relocatePushedItem(origin, item_name, moved)
	end

	return moved, item_name
end

local function _barePullItems(_, output_components, input_components, limit)
	local item_name = input_components.inventory:itemName()

	local origin = output_components.self
	if origin.component_type == 'slot' then
		limit = origin:_outputLimit(item_name)
	end

	local moved = peripheral.call(input_components.inventory.name, 'pullItem', output_components.inventory.name, item_name, limit)

	if origin.component_type == 'slot' and moved > 0 then
		origin.parent:_relocatePulledItem(origin, item_name, moved)
	end

	return moved, item_name
end

local ShapelessInventory = new_class(AbstractInventory)

function ShapelessInventory:new(args)
	local new_inventory = AbstractInventory:new(args)

	-- Could not find inventory.
	if not new_inventory then
		return nil
	end

	if not table_contains(peripheral.getMethods(new_inventory.name), 'items') then
		error('Inventory ' .. new_inventory.name .. ' is not a valid barrel type.')
	end

	new_inventory.count = args.count or 0
	new_inventory.item_name = args.item_name or 'empty'

	setmetatable(new_inventory, ShapelessInventory)

	new_inventory:refresh()

	return new_inventory
end

ShapelessInventory._getPriority = _getPriority
ShapelessInventory._barePushItems = _barePushItems
ShapelessInventory._barePullItems = _barePullItems

function ShapelessInventory:isShapeless()
	return true
end

function ShapelessInventory:catalog()
	local items = peripheral.call(self.name, "items")

	local _, item = next(items)
	self.item_name = item and item.name or 'empty'

	local count = 0
	for _, _item in pairs(items) do
		count = count + _item.count
	end

	self.count = count
	self.full = false
end

function ShapelessInventory:refresh()
	local items = peripheral.call(self.name, "items")

	local _, item = next(items)
	self.item_name = item and item.name or 'empty'

	-- NOTE: We do not update the amount of items here, as we would need to recount them, which is expensive.
end

function ShapelessInventory:hasItem()
	return self:itemCount() > 0
end

function ShapelessInventory:itemCount()
	return self.count
end

function ShapelessInventory:itemName()
	return self.item_name
end

ShapelessInventory.itemIsAvailable = ShapelessInventory.hasItem

function ShapelessInventory:_itemAddedHandler(item_name, amount)
	self.count = self.count + amount

	if amount == 0 then
		self.full = true
	end

	if self.item_name == 'empty' then
		self.item_name = item_name
	end
end

function ShapelessInventory:_itemRemovedHandler(_, amount)
	self.count = self.count - amount

	self.full = false

	if self.count == 0 then
		self.item_name = 'empty'
	end
end

function ShapelessInventory:_getInputComponents(item_name)
	if not self:hasItem() or ((item_name or self.item_name == item_name) and not self.full) then
		return {
			self = self,
			inventory = self,
			cluster = self.parent,
		}
	end

	return nil
end

function ShapelessInventory:_getOutputComponents(item_name)
	if self:hasItem() and (not item_name or self.item_name == item_name) then
		return {
			self = self,
			inventory = self,
			cluster = self.parent,
		}
	end

	return nil
end

function ShapelessInventory:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		error('Item name cannot be '..utils.tostring(item_name))
	end

	if self:hasItem() then
		error('Bulk Inventory cannot register item '..utils.tostring(item_name)..', as it still has item '..self.item_name)
	end

	self.item_name = item_name
end

function ShapelessInventory:unregisterItem(item_name)
	if item_name == 'empty' then
		error('Item name cannot be '..item_name)
	end

	item_name = item_name or self.item_name
	if item_name ~= self.item_name then
		error('Cannot unregister '..utils.tostring(item_name)..' from inventory registered for '..self.item_name)
	end

	if self:hasItem() then
		error('Cannot unregister '..item_name..' from inventory with '..self.count..' items')
	end

	self.item_name = 'empty'
end

-- Transfers every item to the target inventory, and returns the amount moved. It does not change the inventories internal models.
function ShapelessInventory:_bareTransferAll(target_inv)
	local moved = 0
	local just_moved = 1
	while just_moved > 0 do
		just_moved = peripheral.call(self.name, 'pushItem', target_inv.name)
		moved = moved + just_moved
	end

	return moved
end

function ShapelessInventory:recount(empty_invs)
	if not empty_invs then
		error('No empty storages provided')
	end

	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	for _,inv in pairs(empty_invs) do
		local just_moved = self:_bareTransferAll(inv)
		moved = moved + just_moved

		if just_moved == 0 then
			break
		end
	end

	-- The inventory has to be empty for the count to be valid.
	local emptied = (#peripheral.call(self.name, 'items') == 0)

	-- Undo all moves.
	for _,inv in pairs(empty_invs) do
		local just_moved = inv:_bareTransferAll(self)
		if just_moved == 0 then
			break
		end
	end

	if not emptied then
		error("not enough empty space in bulk storage to count "..self.item_name)
	end

	self.count = moved - 1
end


local ShapelessCluster = new_class(AbstractCluster)
function ShapelessCluster:new (args)
	local new_cluster = AbstractCluster:new(args)

 	new_cluster.item_count = {}
	new_cluster.invs_with_item = {}

	setmetatable(new_cluster, self)
	return new_cluster
end

ShapelessCluster._getPriority = _getPriority
ShapelessCluster._barePushItems = _barePushItems
ShapelessCluster._barePullItems = _barePullItems

function ShapelessCluster:setItemInventory(inv_name, item_name)
	for _,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			if inv:hasItem() and inv.item_name ~= item_name then
				error('Trying to set inventory '..inv_name..' to item '..item_name..', but i\'s already with item '..inv.item_name)
			end

			if inv.item_name then
				-- Removing from previous.
				for i,invv in ipairs(self.invs_with_item[inv.item_name]) do
					if inv == invv then
						table.remove(self.invs_with_item[inv.item_name], i)
						if #self.invs_with_item[inv.item_name] == 0 then
							self.invs_with_item[inv.item_name] = nil
						end
						inv.item_name = nil
						break
					end
				end
			end

			-- Adding new one.
			self.invs_with_item[item_name] = self.invs_with_item[item_name] or {}
			self.item_count[item_name] = self.item_count[item_name] or 0
			inv.item_name = item_name
			table.insert(self.invs_with_item[item_name], inv)

			return
		end
	end

	error('Inventory '..inv_name..' not present in cluster '..self.name)
end

function ShapelessCluster:_createInventory(args)
	return ShapelessInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function ShapelessCluster:registerInventory(args)
	local inv = self:_createInventory(args)
	inv:catalog()

	local item_name = inv.item_name

	-- Creating stats for item if it doesn't exist.
	if not self.invs_with_item[item_name] then self.invs_with_item[item_name] = {} end
	if not self.item_count[item_name] then self.item_count[item_name] = 0 end

	table.insert(self.invs, inv)
	table.insert(self.invs_with_item[item_name], inv)

	if item_name == 'empty' then
		self.item_count['empty'] = self.item_count['empty'] + 1
	else
		inv:recount(self.invs_with_item['empty'])
		self.item_count[item_name] = self.item_count[item_name] + inv:itemCount()
	end
end

function ShapelessCluster:unregisterInventory(inv_name)
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

	for p,i in ipairs(self.invs_with_item[inv.item_name]) do
		if i == inv then
			pos = p
			break
		end
	end
	table.remove(self.invs_with_item[inv.item_name], pos)

	-- HACK: This is a hack to attend for the name bug inside ´BulkInv:new´. You can probably fix this.
	if inv.item_name == 'empty' or not self.item_count[inv.item_name] or self.item_count[inv.item_name] == 0 then
		self.item_count['empty'] = self.item_count['empty'] - 1
	else
		self.item_count[inv.item_name] = self.item_count[inv.item_name] - inv.count
	end
end

-- Catalogs the cluster (initial setup).
function ShapelessCluster:catalog()
	for _,inv in ipairs(self.invs) do
		inv:catalog()
	end
end

function ShapelessCluster:refresh()
	for _,inv in ipairs(self.invs) do
		inv:refresh()
	end
end

function ShapelessCluster:saveData()
	local inv_names = array_map(self.invs, function(inv) return inv.name end)
	local inv_items = array_map(self.invs, function(inv)
		return inv.item_name
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

function ShapelessCluster:loadData(data)
	data = textutils.unserialize(data)

	local inv_names = data.inv_names
	local inv_items = data.inv_items
	local inv_counts = data.inv_counts

	self.item_count = {}
	self.invs = {}
	self.invs_with_item = {}

	for i,inv_name in ipairs(inv_names) do
		local item_name = inv_items[i]
		local item_count = inv_counts[i]

		if peripheral.isPresent(inv_name) then
			local inv = ShapelessInventory:new{
				parent = self,
				name = inv_name,
				item_name = item_name,
				count = item_count,
			}

			table.insert(self.invs, inv)
			self.item_count[item_name] = self.item_count[item_name] or 0
			self.item_count[item_name] = self.item_count[item_name] + item_count
			self.invs_with_item[item_name] = self.invs_with_item[item_name] or {}
			table.insert(self.invs_with_item[item_name], inv)
		else
			utils.log("Inventory "..inv_name.." is no longer present")
		end
	end

	return true
end

function ShapelessCluster:dataPath()
	return "/logistics_data/"..self.name..".data"
end

function ShapelessCluster:invNames()
	return array_map(self.invs, function(inv) return inv.name end, {})
end

function ShapelessCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self.item_count, function(a,b) return a+b end) - (self.item_count['empty'] or 0)
	end

	return self.item_count[item_name] or 0
end

ShapelessCluster.availableItemCount = ShapelessCluster.itemCount

function ShapelessCluster:hasItem(item_name)
	if self.invs_with_item[item_name] then
		return true
	else
		return false
	end
end

function ShapelessCluster:itemIsAvailable(item_name)
	local function search_invs_item(invs_item)
		for _,inv in pairs(invs_item) do
			if inv:itemIsAvailable() then
				return true
			end
		end

		return false
	end

	if not item_name then
		for _item_name,invs_item in pairs(self.invs_with_item) do
			if _item_name ~= 'empty' and search_invs_item(invs_item) then
				return true
			end
		end
	else
		if not self.invs_with_item[item_name] then
			return false
		end

		return search_invs_item(self.invs_with_item[item_name])
	end

	return false
end

function ShapelessCluster:itemNames()
	local item_names = {}
	for item_name, _ in pairs(self.item_count) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function ShapelessCluster:_itemAddedHandler(item_name, count)
	if not self.invs_with_item[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self.item_count[item_name] = self.item_count[item_name] + count

	return true
end

function ShapelessCluster:_itemRemovedHandler(item_name, count)
	if not self.invs_with_item[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self.item_count[item_name] = self.item_count[item_name] - count

	return true
end

function ShapelessCluster:recountItem(item_name)
	if item_name == 'empty' then
		error("can't recount empty item")
	end
	if not self.invs_with_item[item_name] then
		error("item '"..item_name.."' does not exist in bulk storage")
	end

	self.item_count[item_name] = 0
	for _,inv in pairs(self.invs_with_item[item_name]) do
		inv:recount(self.invs_with_item['empty'])
		self.item_count[item_name] = self.item_count[item_name] + inv.count
	end
end

function ShapelessCluster:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	local empty_invs = self.invs_with_item['empty']
	if not empty_invs or #empty_invs == 0 then
		error('No empty inventories found')
	end

	local inv = empty_invs[#empty_invs]

	-- Removing inv from the 'empty' list.
	empty_invs[#empty_invs] = nil
	-- Making sure to clean up if there's nothing in the list.
	if #self.invs_with_item['empty'] == 0 then
		self.invs_with_item['empty'] = nil
	end

	-- Making sure the item's list exists.
	self.invs_with_item[item_name] = self.invs_with_item[item_name] or {}
	self.item_count[item_name] = self.item_count[item_name] or 0
	-- Adding inv to the item's list.
	table.insert(self.invs_with_item[item_name], inv)

	inv:registerItem(item_name)
end

function ShapelessCluster:unregisterItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	local item_invs = self.invs_with_item[item_name]
	local empty_invs = self.invs_with_item['empty']

	for _,inv in ipairs(item_invs) do
		if inv:hasItem() then
			error('Cannot unregister '..item_name..' from '..inv.name..', as there are still items inside.')
		end
	end

	for _,inv in ipairs(item_invs) do
		inv:unregisterItem(item_name)
		table.insert(empty_invs, inv)
	end

	self.invs_with_item[item_name] = nil
	self.item_count[item_name] = nil
end

function ShapelessCluster:recount()
	for item_name,_ in pairs(self.invs_with_item) do
		if item_name ~= 'empty' then
			self:recountItem(item_name)
		end
	end
end

function ShapelessCluster:_getOutputComponents(item_name)
	if not item_name then
		-- Searching for a random item.
		for _item_name,_ in pairs(self.invs_with_item) do
			if _item_name ~= 'empty' then
				item_name = _item_name
				break
			end
		end
	end

	if not item_name then return nil end

	local invs_with_item = self.invs_with_item[item_name]
	if not invs_with_item then return nil end

	local inv = invs_with_item[#invs_with_item]
	if not inv then return nil end

	if inv:itemCount(item_name) <= 0 then return nil end

	return {
		self = self,
		inventory = inv,
		cluster = self,
	}
end

function ShapelessCluster:_getInputComponents(item_name)
	if item_name then
		local invs_with_item = self.invs_with_item[item_name]
		if not invs_with_item then return nil end

		local inv = invs_with_item[#invs_with_item]
		if not inv then return nil end

		if inv.full then return nil end

		return {
			self = self,
			inventory = inv,
			cluster = self,
		}
	else
		local invs_with_item = self.invs_with_item[item_name]
		if not invs_with_item then return nil end

		local inv = invs_with_item[#invs_with_item]
		if not inv then return nil end

		return {
			inventory = inv,
			cluster = self,
		}
	end
end


return {
	ShapelessInventory = ShapelessInventory,
	ShapelessCluster = ShapelessCluster,
}

