local _M = {}

local utils = require('/evo-logistics/utils/utils')

local string_split = utils.string_split
local array_filter = utils.array_filter
local array_contains = utils.array_contains

local Memoized = require('/evo-logistics/utils/memoized').Memoized

local function get_modem_side(is_wireless)
	if is_wireless == nil then
		error('wirelessness should be specified')
	end

	for _, side in pairs(redstone.getSides()) do
		if peripheral.isPresent(side)
				and peripheral.getType(side) == "modem"
				and (is_wireless == nil or peripheral.call(side, "isWireless") == is_wireless) then
			return side
		end
	end

	return nil
end
_M.get_modem_side = get_modem_side

local function rednet_open(is_wireless)
	local modem_side = get_modem_side(is_wireless)

	if not modem_side then
		return false
	else
		rednet.open(modem_side)
		return true
	end
end
_M.rednet_open = rednet_open

local function inventory_type(inv_name)
	local stripped = string_split(inv_name, '_')
	stripped[#stripped] = nil
	return table.concat(stripped, '_')
end
_M.inventory_type = inventory_type

local function get_connected_inventories()
	local blacklist = {'computer'}

	local modem_side = get_modem_side(false)

	if not modem_side then
		error('no modem found')
	end

	local names = peripheral.call(modem_side, "getNamesRemote")

	names = array_filter(names, function(inv_name)
		return not array_contains(blacklist, inventory_type(inv_name))
	end)

	return names
end
_M.get_connected_inventories = get_connected_inventories

local function get_connected_inventory_types()
	local invs = get_connected_inventories()

	local types = {}
	for _, inv_name in ipairs(invs) do
		local inv_type = inventory_type(inv_name)
		if not array_contains(types, inv_type) then
			table.insert(types, inv_type)
		end
	end

	return types
end
_M.get_connected_inventory_types = get_connected_inventory_types

_M.is_shaped = Memoized:new {
	name = 'is_shaped',
	auto_save = true,
	fn = function(inv_type)
		if not inv_type then error('inv_type is nil') end

		local invs = get_connected_inventories()

		for _, inv_name in ipairs(invs) do
			if inventory_type(inv_name) == inv_type then
				local methods = peripheral.getMethods(inv_name)

				if methods == nil then
					error('inventory has no methods: '..inv_name)
				elseif array_contains(methods, 'pullItems') then
					return true
				elseif array_contains(methods, 'pullItem') then
					return false
				else
					error('invalid inventory: '..inv_name)
				end
			end
		end

		error('no inventory of type: '..inv_type)
	end,
}

_M.inventory_size = Memoized:new {
	name = 'inventory_size',
	auto_save = true,
	fn = function(inv_type)
		local invs = get_connected_inventories()

		for _, inv_name in ipairs(invs) do
			if inventory_type(inv_name) == inv_type then
				local methods = peripheral.getMethods(inv_name)

				if methods == nil then
					error('inventory has no methods: '..inv_name)
				elseif array_contains(methods, 'size') then
					return peripheral.call(inv_name, 'size')
				else
					return nil
				end
			end
		end

		error('no inventory of type: '..inv_type)
	end,
}

local function shorten_item_names(item_names)
	local shortened_item_names = {}
	-- Tracks shortened item names for clashing.
	local tracker = {}

	for i,item_name in ipairs(item_names) do
		local shortened = string_split(item_name, ':')[2]

		if not tracker[shortened] then
			tracker[shortened] = i
			shortened_item_names[i] = shortened
		else
			-- A clash happened. Set both of them to their original names.
			local other_i = tracker[shortened]
			local other_item_name = item_names[other_i]

			shortened_item_names[i] = item_name
			shortened_item_names[other_i] = other_item_name
		end
	end

	return shortened_item_names
end
_M.shorten_item_names = shorten_item_names

return _M
