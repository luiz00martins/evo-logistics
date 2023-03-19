---@diagnostic disable: need-check-nil
local utils = require('/logos-library.utils.utils')
local abstract = require('/logos-library.core.abstract')

local new_class = require('/logos-library.utils.class').new_class
local table_contains = utils.table_contains

local AbstractInventory = abstract.AbstractInventory

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

local function _barePushItems(_, output_components, input_components, item_name, limit)
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

local function _barePullItems(_, output_components, input_components, item_name, limit)
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
		error('Inventory ' .. new_inventory.name .. ' is not a valid shapeless type.')
	end

	new_inventory.items = {}
	new_inventory.full = false

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

	self.items = {}
	for _,item in ipairs(items) do
		self.items[item.name] = item
	end
end

ShapelessInventory.refresh = ShapelessInventory.catalog

function ShapelessInventory:hasItem(item_name)
	if item_name then
		local item = self.items[item_name]
		return item and item.count > 0
	else
		for _, item in pairs(self.items) do
			if item.count > 0 then
				return true
			end
		end
	end

	return false
end

-- WARNING: In the current version of CC:Restitched shapeless inventories usually return '1', even when there are many more items in the inventory. Do not trust the value returned by this.
function ShapelessInventory:itemCount()
	local count = 0

	for _, item in pairs(self.items) do
		count = count + item.count
	end

	return count
end

ShapelessInventory.itemIsAvailable = ShapelessInventory.hasItem

function ShapelessInventory:_itemAddedHandler(item_name, amount)
	if amount == 0 then
		self.full = true
	elseif not self.items[item_name] then
		self.items[item_name] = {
			name = item_name,
			count = amount,
		}
	else
		self.items[item_name].count = self.items[item_name].count + amount
	end
end

function ShapelessInventory:_itemRemovedHandler(item_name, amount)
	if self.items[item_name] then
		self.items[item_name].count = self.items[item_name].count - amount

		if self.items[item_name].count <= 0 then
			self.items[item_name] = nil
		end
	else
		error(item_name.." was removed from "..self.name.." but it was not in the inventory")
	end

	self.full = false
end

function ShapelessInventory:_getInputComponents(_)
	if not self.full then
		return {
			self = self,
			inventory = self,
			cluster = self.parent,
		}
	else
		return nil
	end
end

function ShapelessInventory:_getOutputComponents(item_name)
	if self:hasItem(item_name) then
		return {
			self = self,
			inventory = self,
			cluster = self.parent,
		}
	else
		return nil
	end
end



return {
	ShapelessInventory = ShapelessInventory,
}

