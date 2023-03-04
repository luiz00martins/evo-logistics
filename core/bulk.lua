---@diagnostic disable: need-check-nil
local utils = require('/logos-library.utils.utils')
local dl_list = require('/logos-library.utils.dl_list')
local abstract = require('/logos-library.core.abstract')
local standard = require('/logos-library.core.standard')

local table_reduce = utils.table_reduce
local array_map = utils.array_map
local new_class = utils.new_class

local StandardSlot = standard.StandardSlot
local AbstractInventory = abstract.AbstractInventory
local AbstractCluster = abstract.AbstractCluster

local BULK_COMPONENT_PRIOTITY = 1

local function _getPriority() return BULK_COMPONENT_PRIOTITY end

local function _barePushItems(_, output_components, input_components, limit)
	return peripheral.call(output_components.inventory.name, 'pushItems', input_components.inventory.name, output_components.slot.index, limit, input_components.slot.index), output_components.slot:itemName()
end

local function _barePullItems(_, output_components, input_components, limit)
	return peripheral.call(input_components.inventory.name, 'pullItems', output_components.inventory.name, output_components.slot.index, limit, input_components.slot.index), output_components.slot:itemName()
end


local BulkSlot = new_class(StandardSlot)

function BulkSlot:_itemAddedHandler(_, amount, _)
	self:refresh()
	if amount == 0 then
		self.full = true
	end
end

BulkSlot._getPriority = _getPriority

function BulkSlot:_itemRemovedHandler(_, _, _)
	self:refresh()
end

function BulkSlot:_getOutputComponents(item_name)
	if self:hasItem(item_name) then
		return {
			self = self,
			slot = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	else
		return nil
	end
end

function BulkSlot:_getInputComponents(item_name)
	if self:itemName() == 'empty' or (self:hasItem(item_name) and not self.full) then
		return {
			self = self,
			slot = self,
			inventory = self.parent,
			cluster = self.parent.parent,
		}
	else
		return nil
	end
end

---------------------------------------------------------
-- Bulk Storage Cluster

local BulkInvBase = new_class(AbstractInventory)

BulkInvBase._getPriority = _getPriority
BulkInvBase._barePushItems = _barePushItems
BulkInvBase._barePullItems = _barePullItems

local BulkInv = {
	NORMAL = new_class(BulkInvBase),
	IO_SLOTS = new_class(BulkInvBase),
}

function BulkInv:new(args)
	local newBulkInv = BulkInvBase:new(args)

	-- Could not find inventory.
	if not newBulkInv then
		return nil
	end

	if newBulkInv.size == 2 then
		setmetatable(newBulkInv, BulkInv.IO_SLOTS)

		newBulkInv.count = 0
		local items = peripheral.call(newBulkInv.name, "list")

		newBulkInv.in_slot = BulkSlot:new{
			parent = newBulkInv,
			index = 1,
			item = items[1],
			full = false,
		}
		newBulkInv.out_slot = BulkSlot:new{
			parent = newBulkInv,
			index = 2,
			item = items[2],
			full = false,
		}
	else
		setmetatable(newBulkInv, BulkInv.NORMAL)
	end

	return newBulkInv
end

function BulkInv.NORMAL:catalog()
	local items = peripheral.call(self.name, "list")

	-- Figuring out which item is in storage.
	if next(items) == nil then
		self.item_name = 'empty'
	else
		local _, item = next(items)
		self.item_name = item.name
	end

	self.count = 0
	self.item_slots = dl_list()
	self.empty_slots = dl_list()

	-- Building list of item slots.
	local slot
	for index=1,self.size do
		slot = BulkSlot:new{
			parent = self,
			index = index,
			item = items[index],
			full = false,
		}
		local item_name = slot:itemName()

		if item_name == 'empty' then
			self.empty_slots:push(slot)
		elseif item_name == self.item_name then
			self.item_slots:push(slot)
			self.count = self.count + slot:itemCount()
		else
			error("bulk inventory "..self.name.." contains two different items("..self.item_name.." and "..item_name..")")
		end
	end
end

function BulkInv.IO_SLOTS:catalog()
	self:refresh()
end

function BulkInv.NORMAL:_inputSlot()
	if self.item_slots.last and not self.item_slots.last.full then
		return self.item_slots.last
	elseif self.empty_slots.last then
		return self.empty_slots.last
	end

	-- In case the last slot was full, and there's no empty, we check the other ones to make *sure* that there's no spare space.
	for slot in self.item_slots:iterate() do
		if not slot.full then
			return slot
		end
	end

	-- No spare space was found.
	return nil
end

function BulkInv.IO_SLOTS:_inputSlot()
	if not self.in_slot.full then
		return self.in_slot
	else
		return nil
	end
end

function BulkInv.NORMAL:_outputSlot()
	if self.item_slots.last then
		return self.item_slot.last
	end

	-- No item in storage.
	return nil
end

function BulkInv.IO_SLOTS:_outputSlot()
	if self.out_slot:itemCount() > 0 then
		return self.out_slot
	else
		return nil
	end
end

function BulkInv.NORMAL:_getOutputComponents(item_name)
	local slot = self:_outputSlot()

	if slot and (not item_name or slot:itemName() == item_name) then
		return {
			self = self,
			slot = slot,
			inventory = self,
			cluster = self.parent,
		}
	else
		return nil
	end
end

BulkInv.IO_SLOTS._getOutputComponents = BulkInv.NORMAL._getOutputComponents

function BulkInv.NORMAL:_getInputComponents(item_name)
	local slot = self:_inputSlot()

	if slot and (not item_name or self.item_name == item_name) then
		return {
			self = self,
			slot = slot,
			inventory = self,
			cluster = self.parent,
		}
	else
		return nil
	end
end

BulkInv.IO_SLOTS._getInputComponents = BulkInv.NORMAL._getInputComponents

function BulkInv.NORMAL:hasItem()
	return self.count > 0
end

function BulkInv.IO_SLOTS:hasItem()
	return self.out_slot:itemCount() > 0
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
	return self.out_slot:itemCount() > 0
end

function BulkInv.NORMAL:_itemAddedHandler(item_name, amount, input_components)
end

local MAX_UPDATE_WAIT_TIME = 0.02
function BulkInv.IO_SLOTS:_itemAddedHandler(_, amount, _)
	self.count = self.count + amount
end

function BulkInv.NORMAL:_itemRemovedHandler(item_name, amount, output_components)
end

function BulkInv.IO_SLOTS:_itemRemovedHandler(_, amount, _)
	self.count = self.count - amount
end

function BulkInv.NORMAL:refresh()
	self:catalog()
end

function BulkInv.IO_SLOTS:refresh()
	os.sleep(MAX_UPDATE_WAIT_TIME)
	self.out_slot:refresh()
	self.in_slot:refresh()

	local item = self.out_slot:item()
	if item == nil then
		self.item_name = 'empty'
		self.count = 0
	else
		self.item_name = item.name
	end
end

function BulkInv.IO_SLOTS:registerItem(item_name)
	if not item_name or item_name == 'empty' then
		item_name = item_name or 'nil'
		error('Item name cannot be '..item_name)
	end

	if self:hasItem() then
		error('Bulk Inventory cannot register item '..item_name..', as it still has item '..self.item_name)
	end

	self.item_name = item_name
end

function BulkInv.NORMAL:registerItem(item_name)
	-- TODO:
	error('TODO')
end

function BulkInv.IO_SLOTS:unregisterItem(item_name)
	if item_name == 'empty' then
		error('Item name cannot be '..item_name)
	end

	item_name = item_name or self.item_name
	if item_name ~= self.item_name then
		error('Cannot unregister '..item_name..' from inventory registered for '..self.item_name)
	end
	self.item_name = 'empty'
end

function BulkInv.NORMAL:unregisterItem(item_name)
	-- TODO:
	error('TODO')
end

function BulkInv.NORMAL:recount(_)
	self:catalog()
end

-- Transfers every item to the target inventory, and returns the amount moved. It does not change the inventories internal models.
function BulkInv.IO_SLOTS:_bareTransferAll(target_inv)
	local MAX_ATTEMPTS = 3

	local fromSlot = self.out_slot
	local toSlot = target_inv.in_slot
	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	local failed_attempts = 0
	while fromSlot and toSlot and fromSlot:hasItem() do
		local oldItem = fromSlot:item()
		local just_moved = peripheral.call(self.name, 'pushItems', target_inv.name, fromSlot.index, 64, toSlot.index)
		moved = moved + just_moved

		if just_moved == 0 then
			failed_attempts = failed_attempts + 1

			os.sleep(MAX_UPDATE_WAIT_TIME / ((MAX_ATTEMPTS+1) - failed_attempts))

			if failed_attempts >= MAX_ATTEMPTS then
				break
			end
		else
			failed_attempts = 0
			-- ...possibly by putting this in the slot.
			fromSlot._item = {
				name = oldItem.name,
				count = 64
			}
			toSlot._item = nil
		end

		fromSlot = self.out_slot
		toSlot = target_inv:_inputSlot()
	end

	return moved
end
BulkInv.NORMAL._bareTransferAll = BulkInv.IO_SLOTS._bareTransferAll

function BulkInv.IO_SLOTS:recount(empty_invs)
	if not empty_invs then
		error('No empty storages provided')
	end

	local moved = 0

	-- Move all items to empty, counting the each transter in the process.
	self:refresh()
	for _,inv in pairs(empty_invs) do
		local just_moved = self:_bareTransferAll(inv)
		moved = moved + just_moved

		inv:refresh()

		if just_moved == 0 or not self:hasItem() then
			break
		end
	end
	self:refresh()

	-- The inventory has to be empty for the count to be valid.
	local emptied = not self:hasItem()
	--print(self.out_slot:itemCount())

	-- Undo all moves.
	for _,inv in pairs(empty_invs) do
		local just_moved = inv:_bareTransferAll(self)
		inv:refresh()
		if just_moved == 0 then
			break
		end
	end
	self:refresh()

	if not emptied then
		error("not enough empty space in bulk storage to count "..self.item_name)
	end

	self.count = moved - 1
end


local BulkCluster = new_class(AbstractCluster)
function BulkCluster:new (args)
	local newBulkCluster = AbstractCluster:new(args)

 	newBulkCluster.item_count = {}
	newBulkCluster.invs_with_item = {}

	setmetatable(newBulkCluster, self)
	return newBulkCluster
end

BulkCluster._getPriority = _getPriority
BulkCluster._barePushItems = _barePushItems
BulkCluster._barePullItems = _barePullItems

-- Catalogs the cluster (initial setup).
function BulkCluster:catalog()
	self.invs = {}
	self.invs_with_item = {}
	self.item_count = {}

	for _,invName in ipairs(self:invNames()) do
		local inv = BulkInv:new{
			parent = self,
			name = invName,
		}
		inv:catalog()

		local item_name = inv.item_name

		-- Creating stats for item if it doesn't exist.
		if not self.invs_with_item[item_name] then self.invs_with_item[item_name] = {} end
		if not self.item_count[item_name] then self.item_count[item_name] = 0 end

		table.insert(self.invs, inv)
		table.insert(self.invs_with_item[item_name], inv)

		if item_name == 'empty' then
			self.item_count['empty'] = self.item_count['empty'] + 1
		end
	end

	self:recount()
end

function BulkCluster:setItemInventory(inv_name, item_name)
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

function BulkCluster:_createInventory(args)
	return BulkInv:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function BulkCluster:registerInventory(args)
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
		self.item_count[item_name] = self.item_count[item_name] + inv.count
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

function BulkCluster:refresh()
	self.invs_with_item = {}
	self.item_count = {}

	for _,inv in ipairs(self.invs) do
		inv:refresh()
		local item_name = inv.item_name

		-- Creating stats for item if it doesn't exist.
		self.invs_with_item[item_name] = self.invs_with_item[item_name] or {}
		self.item_count[item_name] = self.item_count[item_name] or 0

		-- Updating invs_with_item.
		table.insert(self.invs_with_item[item_name], inv)
		-- Updating item count.
		if item_name == 'empty' then
			self.item_count['empty'] = self.item_count['empty'] + 1
		else
			self.item_count[item_name] = self.item_count[item_name] + inv.count
		end
	end
end

function BulkCluster:saveData()
	local inv_names = array_map(self.invs, function(inv) return inv.name end)
	local inv_items = array_map(self.invs, function(inv)
		return inv.item_name
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

function BulkCluster:loadData(data)
	data = textutils.unserialize(data)

	local inv_names = data.inv_names
	local inv_items = data.inv_items
	local inv_counts = data.inv_counts

	self.item_count = {}
	self.invs = {}

	for i,inv_name in ipairs(inv_names) do
		local item_name = inv_items[i]
		local item_count = inv_counts[i]

		if peripheral.isPresent(inv_name) then
			local inv = BulkInv:new{
				parent = self,
				name = inv_name,
			}
			inv.count = item_count
			inv:catalog()

			table.insert(self.invs, inv)
			self.item_count[item_name] = self.item_count[item_name] or 0

			self.item_count[item_name] = self.item_count[item_name] + item_count
		else
			utils.log("Inventory "..inv_name.." is no longer present")
		end
	end

	return true
end

function BulkCluster:dataPath()
	return "/logistics_data/"..self.name..".data"
end

function BulkCluster:invNames()
	return array_map(self.invs, function(inv) return inv.name end, {})
end

function BulkCluster:itemCount(item_name)
	if not item_name then
		return table_reduce(self.item_count, function(a,b) return a+b end) - (self.item_count['empty'] or 0)
	end

	return self.item_count[item_name] or 0
end

BulkCluster.availableItemCount = BulkCluster.itemCount

function BulkCluster:hasItem(item_name)
	if self.invs_with_item[item_name] then
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

function BulkCluster:itemNames()
	local item_names = {}
	for item_name, _ in pairs(self.item_count) do
		item_names[#item_names+1] = item_name
	end
	return item_names
end

function BulkCluster:_itemAddedHandler(item_name, amount, _)
	if not self.invs_with_item[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self.item_count[item_name] = self.item_count[item_name] + amount

	return true
end

function BulkCluster:_itemRemovedHandler(item_name, amount, _)
	if not self.invs_with_item[item_name] then
		error("no item '"..item_name.." in "..self.name)
	end

	self.item_count[item_name] = self.item_count[item_name] - amount

	return true
end

-- Returns a slot where `item_name` can be inserted to. Returns 'nil' if none are available.
function BulkCluster:_getInputComponents(item_name)
	if not item_name
			or item_name == 'empty'
			or not self.invs_with_item[item_name] then
		return nil
	end

	for _, inv in pairs(self.invs_with_item[item_name]) do
		local components = inv:_getInputComponents(item_name)

		if components then
			components.self = self
			return components
		end
	end

	return nil
end

-- Returns a slot from which `item_name` can be drawn from. Returns 'nil' if none are available.
function BulkCluster:_getOutputComponents(item_name)
	-- NOTE: Yes, the worst case of this is O(n). However, the average case is O(1).
	local function search_invs_item(invs_with_item)
		for _, inv in pairs(invs_with_item) do
			local components = inv:_getOutputComponents()

			if components then
				components.self = self
				return components
			end
		end

		return nil
	end

	if not item_name then
		for _, invs_item in pairs(self.invs_with_item) do
			local components = search_invs_item(invs_item)
			if components then return components end
		end
	else
		if not self.invs_with_item[item_name] then
			return nil
		end

		local components = search_invs_item(self.invs_with_item[item_name])
		if components then return components end
	end

	return nil
end

function BulkCluster:recountItem(item_name)
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

function BulkCluster:registerItem(item_name)
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

function BulkCluster:unregisterItem(item_name)
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

function BulkCluster:recount()
	for item_name,_ in pairs(self.invs_with_item) do
		if item_name ~= 'empty' then
			self:recountItem(item_name)
		end
	end
end

return {
	BulkCluster = BulkCluster,
}
