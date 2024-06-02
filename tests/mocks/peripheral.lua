local ut = require("cc-ut")

local utils = require('/logos-library.utils.utils')
local inv_utils = require('/logos-library.utils.inventories')

local describe = ut.describe

local table_deepcopy = utils.table_deepcopy
local table_keys = utils.table_keys
local table_values = utils.table_values
local table_contains = utils.table_contains
local inventory_type = inv_utils.inventory_type

local original_peripheral = peripheral
local peripheral = {
	custom = {},
	_inventories = {},
}
local inventories = peripheral._inventories
local modem = {
	side = 'bottom'
}
local items_data = {
	['minecraft:coal'] = {
		maxCount = 64,
		displayName = 'Coal'
	},
	['minecraft:iron_ingot'] = {
		maxCount = 64,
		displayName = 'Coal'
	},
	['minecraft:oak_log'] = {
		maxCount = 64,
		displayName = 'Oak Log'
	},
	['minecraft:oak_planks'] = {
		maxCount = 64,
		displayName = 'Oak Planks'
	},
	['minecraft:stick'] = {
		maxCount = 64,
		displayName = 'Stick'
	},
	['minecraft:ender_pearl'] = {
		maxCount = 16,
		displayName = 'Ender Pearl'
	},
	['minecraft:wooden_sword'] = {
		maxCount = 1,
		displayName = 'Wooden Sword',
		maxDamage = 59,
	},
	['techreborn:electrum_plate'] = {
		maxCount = 64,
		displayName = 'Electrum Plate'
	},
	['techreborn:silicon_plate'] = {
		maxCount = 64,
		displayName = 'Silicon Plate'
	},
	['techreborn:advanced_circuit'] = {
		maxCount = 64,
		displayName = 'Advanced Circuit'
	},
}

local inventory_api_functions = {}

inventory_api_functions.pushItems = function(output_inv_name, input_inv_name, output_slot, limit, input_slot)
	local output_inv = inventories[output_inv_name]
	local input_inv = inventories[input_inv_name]

	if not output_inv then
		error('output_inv does not exist')
	elseif not input_inv then
		error('input_inv does not exist')
	elseif not output_inv.methods.pushItems then
		error('output_inv does not support pushItems')
	elseif not input_inv.methods.pushItems then
		error('input_inv does not support pushItems')
	end

	if output_slot > output_inv.size then
		return 0
	elseif input_slot > input_inv.size then
		return 0
	end

	if limit == 0 then
		return 0
	end

	local output_item = output_inv.list[output_slot]
	local input_item = input_inv.list[input_slot]

	if not output_item then
		return 0
	elseif not input_item then
		input_item = {
			name = output_item.name,
			count = 0,
		}
		input_inv.list[input_slot] = input_item
	elseif output_item.name ~= input_item.name then
		return 0
	end

	-- Actually moving item.
	local max_count = items_data[output_item.name].maxCount
	local moved_amount = math.min(input_item.count + output_item.count, max_count) - input_item.count
	if limit then
		moved_amount = math.min(moved_amount, limit)
	end

	input_item.count = input_item.count + moved_amount
	output_item.count = output_item.count - moved_amount

	if output_item.count == 0 then
		output_inv.list[output_slot] = nil
	end

	-- Updating inventories.
	output_inv:update()
	input_inv:update()

	return moved_amount
end

inventory_api_functions.pullItems = function(input_inv_name, output_inv_name, output_slot, limit, input_slot)
	return inventory_api_functions.pushItems(output_inv_name, input_inv_name, output_slot, limit, input_slot)
end

inventory_api_functions.size = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return inv.size
end

inventory_api_functions.list = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return table_deepcopy(inv.list)
end

inventory_api_functions.getItemDetail = function(inv_name, inv_slot)
	local inv = inventories[inv_name] or error('Inventory '..inv_name..' not found')
	local item = inv.list[inv_slot]

	if not item then return nil end

	local item_data = table_deepcopy(items_data[item.name])

	item_data.name = item.name
	item_data.count = item.count
	return item_data
end

inventory_api_functions.items = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return table_values(inv.items)
end

local function _total_item_count(inv, item_name)
	local count = 0

	if inv.list then
		for slot, item in pairs(inv.list) do
			if item.name == item_name then
				count = count + item.count
			end
		end

		return count
	elseif inv.items then
		local item = inv.items[item_name]

		if item then
			return item.count
		end
	end

	return count
end

local function _add_item(inv, item_name, amount)
	if not inv then
		error('Inventory '..inv.name..' not found')
	elseif amount == 0 then
		return 0
	end

	local moved = 0

	if inv.list then
		for i=1, inv.size do
			local item = inv.list[i]
			if not item or (item and item.name == item_name) then
				if not item then
					inv.list[i] = {name = item_name, count = 0}
					item = inv.list[i]
				end

				local max_count = items_data[item_name].maxCount
				local moved_amount = math.min(item.count + amount, max_count) - item.count
				if moved_amount > 0 then
					inv.list[i].count = item.count + moved_amount
					moved = moved + moved_amount
					amount = amount - moved_amount
				end

				if amount == 0 then
					return moved
				end
			end
		end
	else
		local max_amount = inv.data.max_count
		inv.items[item_name] = inv.items[item_name] or {item_name = item_name, count = 0}
		local item = inv.items[item_name]

		local moved_amount = math.min(item.count + amount, max_amount) - item.count
		if moved_amount > 0 then
			item.count = item.count + moved_amount
			moved = moved + moved_amount
			amount = amount - moved_amount
		end

		return moved
	end

	return moved
end

local function _remove_item(inv, item_name, amount)
	if not inv then
		error('Inventory '..inv.name..' not found')
	end

	local moved = 0

	if inv.list then
		for i=1, inv.size do
			local item = inv.list[i]
			if item and item.name == item_name then
				local moved_amount = math.min(item.count, amount)
				if moved_amount > 0 then
					inv.list[i].count = item.count - moved_amount
					moved = moved + moved_amount
					amount = amount - moved_amount
				end

				if amount == 0 then
					return moved
				end
			end
		end
	else
		local item = inv.items[item_name]

		if item then
			local moved_amount = math.min(item.count, amount)
			if moved_amount > 0 then
				item.count = item.count - moved_amount
				moved = moved + moved_amount
				amount = amount - moved_amount
			end

			if item.count == 0 then
				inv.items[item_name] = nil
			end

			return moved
		end
	end

	return 0
end

inventory_api_functions.pushItem = function(output_inv_name, input_inv_name, item_name, limit)
	local output_inv = inventories[output_inv_name]
	local input_inv = inventories[input_inv_name]

	if not output_inv then
		error('output_inv does not exist')
	elseif not input_inv then
		error('input_inv does not exist')
	end

	if limit == 0 then
		return 0
	end

	if not item_name then
		-- TODO: Continue
		-- This will fail on 'pullItem', as the order is reversed. You have to extract the logic of deciding the item and the item amount (for loop for normal, and 'items' for the barrel)
		local item
		if output_inv.items and next(output_inv.items) then
			_, item = next(output_inv.items)
		elseif input_inv.items and next(input_inv.items) then
			_, item = next(input_inv.items)
		else
			return 0
		end

		if not item then
			return 0
		end

		item_name = item.name
	end

	local item_amount = _total_item_count(output_inv, item_name)
	local add_amount = math.min(
		item_amount,
		limit or item_amount,
		output_inv.data.max_move or item_amount,
		input_inv.data.max_move or item_amount
	)
	local moved = _add_item(input_inv, item_name, add_amount)
	_remove_item(output_inv, item_name, moved)

	-- Updating inventories.
	output_inv:update()
	input_inv:update()

	return moved
end

inventory_api_functions.pullItem = function(input_inv_name, output_inv_name, item_name, limit)
	return inventory_api_functions.pushItem(output_inv_name, input_inv_name, item_name, limit)
end


local function move_item(output_item, input_item, limit, maxCount)
	if not output_item then
		return 0, output_item, input_item
	elseif not input_item then
		input_item = {
			name = output_item.name,
			count = 0,
		}
	elseif output_item.name ~= input_item.name then
		return 0, output_item, input_item
	end

	-- Actually moving item.
	local max_count = maxCount or items_data[output_item.name].maxCount
	local moved_amount = math.min(input_item.count + output_item.count, max_count) - input_item.count
	if limit then
		moved_amount = math.min(moved_amount, limit)
	end

	output_item.count = output_item.count - moved_amount
	input_item.count = input_item.count + moved_amount

	if output_item.count == 0 then
		output_item = nil
	end

	return moved_amount, output_item, input_item
end

local function default_print(self, print_fn)
	for i,item in pairs(self.list) do
		print_fn('Slot '..tostring(i)..': '..item.count..' '..item.name)
	end
end

local function run_recipes(self)
	local inv_name = self.name

	local function verify_recipe(recipe)
		local list = self.list
		for slot,input in pairs(recipe.inputs) do
			if not list[slot] or input.name ~= list[slot].name then
				return false
			end
		end

		for slot,output in pairs(recipe.outputs) do
			if list[slot] and (output.name ~= list[slot].name
					or (list[slot].count + output.count) > items_data[list[slot].name].maxCount) then
					return false
			end
		end

		return true
	end

	local function execute_recipe(recipe)
		for slot,input in pairs(recipe.inputs) do
			peripheral.custom.consume_item(inv_name, slot, input.count)
		end
		for slot,output in pairs(recipe.outputs) do
			local produced = peripheral.custom.produce_item(inv_name, slot, output.name, output.count)
			if produced ~= output.count then
				error('Could not produce '..tostring(output.count)..' '..output.name..' in crafting')
			end
		end
	end

	for _,recipe in ipairs(self.recipes) do
		while verify_recipe(recipe) do
			execute_recipe(recipe)
		end
	end
end

local shaped_inventory_methods = {
	pushItems = inventory_api_functions.pushItems,
	pullItems = inventory_api_functions.pullItems,
	getItemDetail = inventory_api_functions.getItemDetail,
	list = inventory_api_functions.list,
	size = inventory_api_functions.size,
}
local shapeless_inventory_methods = {
	pushItem = inventory_api_functions.pushItem,
	pullItem = inventory_api_functions.pullItem,
	items = inventory_api_functions.items,
}

peripheral.custom.add_inventory = function(inv_name)
	if inventories[inv_name] then
		error('Inventory '..inv_name..' already exists')
	end

	local inv_type = inventory_type(inv_name)
	local inv

	if inv_type == 'minecraft:chest'
		or inv_type == 'minecraft:barrel' then
		inv = {
			size = 27,
			data = {},
			update = function(self) end,
			print = default_print,
			clear = function(self) self.list = {} end,
			methods = shaped_inventory_methods,
			list = {},
		}
	elseif inv_type == 'techreborn:storage_unit' then
		inv = {
			size = 2,
			methods = shaped_inventory_methods,
			data = {
				locked = false,
				max_count = 2048,
				item = nil,
			},
			update = function(self)
				local function move_out()
					local output_item = self.data.item
					local input_item = self.list[2]
					local amount_moved

					if not output_item then
						return 0
					end

					amount_moved, output_item, input_item = move_item(output_item, input_item)

					self.data.item = output_item
					self.list[2] = input_item

					return amount_moved
				end

				local function move_in()
					local output_item = self.list[1]
					local input_item = self.data.item
					local amount_moved

					amount_moved, output_item, input_item = move_item(output_item, input_item, nil, self.data.max_count)

					self.list[1] = output_item
					self.data.item = input_item

					return amount_moved
				end

				move_out()
				move_in()
				move_out()
				move_in()
			end,
			print = function(self, print_fn)
				local input_item = self.list[1]
				local output_item = self.list[2]

				if input_item	then
					print_fn('Input item: '..input_item.count..' '..input_item.name)
				else
					print_fn('Input item: nothing')
				end
				if output_item	then
					print_fn('Output item: '..output_item.count..' '..output_item.name)
				else
					print_fn('Output item: nothing')
				end
				if self.data.item then
					print_fn('Internal buffer: '..self.data.item.count..' '..self.data.item.name)
				else
					print_fn('Internal buffer: nothing')
				end
			end,
			clear = function(self)
				self.list = {}
				self.data.item = nil
			end,
			list = {}
		}
	elseif inv_type == 'techreborn:auto_crafting_table' then
		inv = {
			size = 11,
			methods = shaped_inventory_methods,
			data = {},
			print = default_print,
			recipes = {
				{
					inputs = {
						[1] = {name = 'minecraft:oak_log', count = 1},
					},
					outputs = {
						[10] = {name = 'minecraft:oak_planks', count = 4},
					},
				},
			},
			update = run_recipes,
			list = {},
		}
	elseif inv_type == 'techreborn:assembly_machine' then
		inv = {
			size = 3,
			methods = shaped_inventory_methods,
			data = {},
			print = default_print,
			recipes = {
					{
						inputs = {
							[1] = {name = 'techreborn:silicon_plate', count = 1},
							[2] = {name = 'techreborn:electrum_plate', count = 2},
						},
						outputs = {
							[3] = {name = 'techreborn:advanced_circuit', count = 1},
						},
					}
				},
			update = run_recipes,
			list = {},
		}
	elseif inv_type == 'modern_industrialization:bronze_barrel' then
		inv = {
			size = 1,
			data = {
				max_count = 2048,
				max_move = 128,
			},
			methods = shapeless_inventory_methods,
			print = default_print, -- FIXME: Probably won't work.
			update = function() end,
			items = {},
		}
	elseif inv_type == 'modern_industrialization:steel_barrel' then
		inv = {
			size = 1,
			data = {
				max_count = 8192,
				max_move = 128,
			},
			methods = shapeless_inventory_methods,
			print = default_print, -- FIXME: Probably won't work.
			update = function() end,
			items = {},
		}
	else
		error('Inventory type "'..inv_type..'" not recognized')
	end

	inv.name = inv_name
	inventories[inv_name] = inv

	return inv
end

peripheral.custom.reset = function(option)
	if option == 'inventories' then
		inventories = {}
		peripheral._inventories = inventories
	else
		error('Option '..option..' not recognized.')
	end
end

peripheral.custom.produce_item = function(inv_name, inv_slot, item_name, item_count)
	if not items_data[item_name] then
		error('Item "'..item_name..'" not recognized')
	end
	item_count = item_count or 1

	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	elseif inv.list and inv_slot > inv.size then
		error('Slot '..tostring(inv_slot)..' outside of range for '..inv_name)
	end

	if item_count == 0 then return 0 end

	local ethereal_item = {
		name = item_name,
		count = item_count,
	}

	if inv.list then
		local input_item = inv.list[inv_slot]
		local amount_added

		amount_added, ethereal_item, input_item = move_item(ethereal_item, input_item)

		inv.list[inv_slot] = input_item

		return amount_added
	else
		local input_item = inv.items[item_name]
		local max_count = inv.data.max_count
		local amount_added

		if inv_slot then
			error('Inventory '..inv_name..' does not support slots')
		elseif not inv.items[item_name] and next(inv.items) then
			error('Inventory '..inv_name..' already contains an item ('..next(inv.items)..')')
		elseif inv.items[item_name] and inv.items[item_name].count + item_count > max_count then
			error('Inventory '..inv_name..' does not have enough space for '..item_count..' '..item_name)
		end

		amount_added, ethereal_item, input_item = move_item(ethereal_item, input_item, nil, max_count)

		inv.items[item_name] = input_item

		return amount_added
	end
end

peripheral.custom.consume_item = function(inv_name, inv_slot, item_count)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	elseif inv_slot > inv.size then
		error('Slot '..tostring(inv_slot)..' outside of range for '..inv_name)
	end

	local item = inv.list[inv_slot]

	if item_count == 0 then return 0 end
	if not item then return 0 end
	if item.count < item_count then
		item_count = item.count
	end

	item.count = item.count - item_count

	if item.count == 0 then
		inv.list[inv_slot] = nil
	end
end

peripheral.custom.tick_inventory = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return inv:update()
end

peripheral.custom.print = function(inv_name, print_fn)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	print_fn = print_fn or print
	inv:print(print_fn)
end

peripheral.custom.clear_inventory = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	inv:clear()
end

peripheral.isPresent = function(side)
	if modem.side == side then
		return true
	else
		return false
	end
end

peripheral.getType = function(side)
	if modem.side == side then
		return 'modem'
	else
		return nil
	end
end

peripheral.isWireless = function(side)
	if modem.side == side then
		return false
	else
		error('Side '..side..' does not contain a modem')
	end
end

peripheral.getNamesRemote = function(modem_side)
	if modem_side ~= modem.side then
		error('Side '..modem_side..' does not contain a modem')
	end

	local inv_names = {}
	for inv_name,_ in pairs(inventories) do
		table.insert(inv_names, inv_name)
	end

	return inv_names
end

peripheral.call = function(target, func_name, ...)
	-- This deals with things that are not inventories.
	if table_contains({'isWireless', 'isPresent', 'getType', 'getNamesRemote'}, func_name) then
		return peripheral[func_name](target, ...)
	end

	local inv = inventories[target]
	if not inv then error('Inventory '..target..' not found') end

	local fn = inv.methods[func_name]
	if not fn then error('Inventory function "'..func_name..'" not found for '..target) end

	if fn then
		return fn(target, ...)
	else
		error('peripheral function "'..func_name..'" not found')
	end

end

peripheral.getSides = original_peripheral.getSides

peripheral.getMethods = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return table_keys(inv.methods)
end

peripheral.test_module = function()
	local vanilla_barrel, vanilla_chest, techreborn_storage_unit, auto_crafting_table, assembly_machine, bronze_barrel, steel_barrel

	local function reset()
		peripheral.custom.reset('inventories')

		vanilla_barrel = peripheral.custom.add_inventory('minecraft:barrel_0')
		vanilla_chest = peripheral.custom.add_inventory('minecraft:chest_0')
		techreborn_storage_unit = peripheral.custom.add_inventory('techreborn:storage_unit_0')
		auto_crafting_table = peripheral.custom.add_inventory('techreborn:auto_crafting_table_0')
		assembly_machine = peripheral.custom.add_inventory('techreborn:assembly_machine_0')
		bronze_barrel = peripheral.custom.add_inventory('modern_industrialization:bronze_barrel_0')
		steel_barrel = peripheral.custom.add_inventory('modern_industrialization:steel_barrel_0')

		peripheral.custom.produce_item('minecraft:barrel_0', 1, 'minecraft:coal', 64)
		peripheral.custom.produce_item('minecraft:barrel_0', 2, 'minecraft:coal', 32)
		peripheral.custom.produce_item('minecraft:barrel_0', 3, 'minecraft:coal', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 4, 'minecraft:ender_pearl', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 5, 'minecraft:ender_pearl', 10)
		peripheral.custom.produce_item('minecraft:barrel_0', 6, 'minecraft:wooden_sword', 1)
	end

	local function test_initial_state(expect)
		expect(vanilla_barrel.list[1].name).toEqual('minecraft:coal')
		expect(vanilla_barrel.list[1].count).toEqual(64)
		expect(vanilla_chest.list[1]).toEqual(nil)
		expect(bronze_barrel.items[1]).toEqual(nil)
		expect(steel_barrel.items[1]).toEqual(nil)
	end

	reset()

	describe('Basic functionality', function(test)
		test('Testing full push item', function(expect)
			test_initial_state(expect)
			expect(peripheral.call('minecraft:barrel_0', 'pushItems', 'minecraft:chest_0', 1, nil, 1)).toEqual(64)
			expect(vanilla_barrel.list[1]).toEqual(nil)
			expect(vanilla_chest.list[1].name).toEqual('minecraft:coal')
			expect(vanilla_chest.list[1].count).toEqual(64)
		end)

		test('Testing reset', function(expect)
			reset()
			test_initial_state(expect)
		end)
	end)

	describe('Edge cases', function(test)
		test('Testing limit', function(expect)
			test_initial_state(expect)
			expect(peripheral.call('minecraft:barrel_0', 'pushItems', 'minecraft:barrel_0', 1, 20, 10)).toEqual(20)
			expect(vanilla_barrel.list[1].name).toEqual('minecraft:coal')
			expect(vanilla_barrel.list[1].count).toEqual(44)
			expect(vanilla_barrel.list[10].name).toEqual('minecraft:coal')
			expect(vanilla_barrel.list[10].count).toEqual(20)
		end)

		test('Testing moving to a slot with a different item', function(expect)
			expect(vanilla_barrel.list[1].name).toEqual('minecraft:coal')
			expect(vanilla_barrel.list[4].name).toEqual('minecraft:ender_pearl')
			expect(peripheral.call('minecraft:barrel_0', 'pushItems', 'minecraft:barrel_0', 1, nil, 4)).toEqual(0)
			expect(vanilla_barrel.list[1].name).toEqual('minecraft:coal')
			expect(vanilla_barrel.list[4].name).toEqual('minecraft:ender_pearl')
		end)

		test('Testing moving to a partially filled inventory', function(expect)
			-- Also testing moving an item with a custom 'maxCount'.
			expect(vanilla_barrel.list[4].name).toEqual('minecraft:ender_pearl')
			expect(vanilla_barrel.list[5].name).toEqual('minecraft:ender_pearl')
			expect(vanilla_barrel.list[4].count).toEqual(16)
			expect(vanilla_barrel.list[5].count).toEqual(10)
			expect(peripheral.call('minecraft:barrel_0', 'pushItems', 'minecraft:barrel_0', 4, nil, 5)).toEqual(6)
			expect(vanilla_barrel.list[4].count).toEqual(10)
			expect(vanilla_barrel.list[5].count).toEqual(16)
		end)

		test('Testing moving item outside of range.', function(expect)
			expect(peripheral.call('minecraft:barrel_0', 'pushItems', 'minecraft:barrel_0', 1, nil, 60)).toEqual(0)
		end)
	end)

	describe('Information functions', function(test)
		test('Testing size call', function(expect)
			expect(peripheral.call('minecraft:chest_0', 'size')).toEqual(27)
		end)

		test('Testing \'getNamesRemote\' call', function(expect)
			local inv_names = peripheral.getNamesRemote('bottom')
			expect(inv_names).toContain('minecraft:barrel_0')
			expect(inv_names).toContain('minecraft:chest_0')
			expect(inv_names).toContain('techreborn:storage_unit_0')
		end)
	end)

	describe('Compatibility with TechReborn', function(test)
		test('Testing techreborn\'s storage unit item handling', function(expect)
			peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 40)
			peripheral.custom.tick_inventory('techreborn:storage_unit_0')
			expect(techreborn_storage_unit.data.item).toEqual(nil)
			expect(techreborn_storage_unit.list[2].count).toEqual(40)
			peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 40)
			peripheral.custom.tick_inventory('techreborn:storage_unit_0')
			expect(techreborn_storage_unit.data.item.name).toEqual('minecraft:iron_ingot')
			expect(techreborn_storage_unit.data.item.count).toEqual(16)
			expect(techreborn_storage_unit.list[2].count).toEqual(64)
			peripheral.custom.consume_item('techreborn:storage_unit_0', 2, 20)
			peripheral.custom.tick_inventory('techreborn:storage_unit_0')
			expect(techreborn_storage_unit.data.item).toEqual(nil)
			expect(techreborn_storage_unit.list[2].count).toEqual(60)
			peripheral.custom.consume_item('techreborn:storage_unit_0', 2, 60)
			expect(techreborn_storage_unit.list[2]).toEqual(nil)
		end)

		test('Testing storage unit max item storage', function(expect)
			-- Adding 2120 items to inventory.
			for i=1,106 do
				peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 20)
				peripheral.custom.tick_inventory('techreborn:storage_unit_0')
			end
			expect(techreborn_storage_unit.data.item.count).toEqual(2048)
			expect(techreborn_storage_unit.list[1].count).toEqual(8)
			expect(techreborn_storage_unit.list[2].count).toEqual(64)
		end)

		test('Testing tech reborn autocrafting', function(expect)
			peripheral.custom.produce_item('techreborn:auto_crafting_table_0', 1, 'minecraft:oak_log')
			peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
			expect(auto_crafting_table.list[10].name).toEqual('minecraft:oak_planks')
			expect(auto_crafting_table.list[10].count).toEqual(4)
			peripheral.custom.consume_item('techreborn:auto_crafting_table_0', 10, 4)
			peripheral.custom.produce_item('techreborn:auto_crafting_table_0', 1, 'minecraft:oak_log', 32)
			peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
			expect(auto_crafting_table.list[10].name).toEqual('minecraft:oak_planks')
			expect(auto_crafting_table.list[10].count).toEqual(64)
			expect(auto_crafting_table.list[1].count).toEqual(16)
			peripheral.custom.consume_item('techreborn:auto_crafting_table_0', 10, 64)
			peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
			expect(auto_crafting_table.list[10].count).toEqual(64)
			expect(auto_crafting_table.list[1]).toEqual(nil)
		end)

		test('Testing tech reborn assembly_machine', function(expect)
			peripheral.custom.produce_item('techreborn:assembly_machine_0', 1, 'techreborn:silicon_plate', 3)
			peripheral.custom.produce_item('techreborn:assembly_machine_0', 2, 'techreborn:electrum_plate', 7)
			peripheral.custom.tick_inventory('techreborn:assembly_machine_0')
			expect(assembly_machine.list[3].name).toEqual('techreborn:advanced_circuit')
			expect(assembly_machine.list[3].count).toEqual(3)
			expect(assembly_machine.list[2].name).toEqual('techreborn:electrum_plate')
			expect(assembly_machine.list[2].count).toEqual(1)
		end)
	end)

	describe('Compatibility with Modern Industrialization', function(test)
		test('Testing producing items to MI barrel', function(expect)
			reset()
			peripheral.custom.produce_item('modern_industrialization:bronze_barrel_0', nil, 'minecraft:oak_planks', 10)
			expect(bronze_barrel.items['minecraft:oak_planks'].name).toEqual('minecraft:oak_planks')
			expect(bronze_barrel.items['minecraft:oak_planks'].count).toEqual(10)
			for i=1,19 do
				peripheral.custom.produce_item('modern_industrialization:bronze_barrel_0', nil, 'minecraft:oak_planks', 10)
			end
			expect(bronze_barrel.items['minecraft:oak_planks'].count).toEqual(200)
			peripheral.custom.produce_item('modern_industrialization:bronze_barrel_0', nil, 'minecraft:oak_planks', 300)
			expect(bronze_barrel.items['minecraft:oak_planks'].count).toEqual(500)
			local ok = pcall(peripheral.custom.produce_item, 'modern_industrialization:bronze_barrel_0', 1, 'minecraft:oak_planks', 10)
			if ok then error('Should not be able to specify slot when producing item on modern industrialization barrel') end
			local ok = pcall(peripheral.custom.produce_item, 'modern_industrialization:bronze_barrel_0', nil, 'minecraft:ender_pearl', 10)
			if ok then error('Should not be able to produce an item that is different from the item currently in the barrel') end
			local ok = pcall(peripheral.custom.produce_item, 'modern_industrialization:bronze_barrel_0', nil, 'minecraft:oak_planks', 5000)
			if ok then error('modern_industrialization:bronze_barrel should not be able to store more than 2048 items') end
		end)

		test('Testing moving item from/to MI barrel', function(expect)
			local ok = pcall(peripheral.call, 'minecraft:barrel_0', 'pushItems', 'modern_industrialization:bronze_barrel_0', 1, nil, 1)
			if ok then error('Should not be able to use pushItems to a modern industrialization barrel') end
			-- The modern idustrialization barrel moves exactly 128 items if not specified.
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pushItem', 'minecraft:chest_0')).toEqual(128)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).name).toEqual('minecraft:oak_planks')
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).count).toEqual(64)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 2).count).toEqual(64)
		end)

		test('Testing moving a specific amount of items...', function(expect) -- from/to MI barrel
			reset()
			peripheral.custom.produce_item('modern_industrialization:bronze_barrel_0', nil, 'minecraft:oak_planks', 1000)
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pushItem', 'minecraft:chest_0', nil, 30)).toEqual(30)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).count).toEqual(30)
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pushItem', 'minecraft:chest_0', nil, 30)).toEqual(30)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).count).toEqual(60)
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pushItem', 'minecraft:chest_0', nil, 30)).toEqual(30)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).count).toEqual(64)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 2).count).toEqual(26)

			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pullItem', 'minecraft:chest_0', nil, 30)).toEqual(30)
			expect(peripheral.call('minecraft:chest_0', 'getItemDetail', 1).count).toEqual(34)
		end)

		test('Testing moving items to barrel until full', function(expect)
			reset()
			peripheral.custom.produce_item('modern_industrialization:steel_barrel_0', nil, 'minecraft:oak_planks', 8000)
			-- MI barrels only move 128 at a time, so we use a for loop.
			for _ = 0,20 do
				peripheral.call('modern_industrialization:steel_barrel_0', 'pushItem', 'modern_industrialization:bronze_barrel_0')
			end
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'pushItem', 'modern_industrialization:steel_barrel_0')).toEqual(0)
			expect(peripheral.call('modern_industrialization:bronze_barrel_0', 'items')[1].count).toEqual(2048)
			expect(peripheral.call('modern_industrialization:steel_barrel_0', 'items')[1].count).toEqual(5952)
		end)
	end)
end

peripheral.custom.reset('inventories')

return peripheral
