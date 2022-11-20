local utils = require('/logos.utils')
local test_utils = require('/logos.tests.utils')

local table_deepcopy = utils.table_deepcopy
local array_contains = utils.array_contains
local inventory_type = utils.inventory_type
local custom_assert = test_utils.custom_assert
local assert_equals = test_utils.assert_equals
local getSides = peripheral.getSides

local peripheral = {
	custom = {},
}
local inventories = {}

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
	for i,item in pairs(self.items) do
		print_fn('Slot '..tostring(i)..': '..item.count..' '..item.name)
	end
end

local function run_recipes(self)
	local inv_name = self.name

	local function verify_recipe(recipe)
		local items = self.items
		for slot,input in pairs(recipe.inputs) do
			if not items[slot] or input.name ~= items[slot].name then
				return false
			end
		end

		for slot,output in pairs(recipe.outputs) do
			if items[slot] and (output.name ~= items[slot].name
					or (items[slot].count + output.count) > items_data[items[slot].name].maxCount) then
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
			update = function(self) end,
			print = default_print,
			clear = function(self) self.items = {} end,
			items = {},
		}
	elseif inv_type == 'techreborn:storage_unit' then
		inv = {
			size = 2,
			data = {
				locked = false,
				max_count = 2048,
				item = nil,
			},
			update = function(self)
				local function move_out()
					local output_item = self.data.item
					local input_item = self.items[2]
					local amount_moved

					if not output_item then
						return 0
					end

					amount_moved, output_item, input_item = move_item(output_item, input_item)

					self.data.item = output_item
					self.items[2] = input_item

					return amount_moved
				end

				local function move_in()
					local output_item = self.items[1]
					local input_item = self.data.item
					local amount_moved

					amount_moved, output_item, input_item = move_item(output_item, input_item, nil, self.data.max_count)

					self.items[1] = output_item
					self.data.item = input_item

					return amount_moved
				end

				move_out()
				move_in()
				move_out()
				move_in()
			end,
			print = function(self, print_fn)
				local input_item = self.items[1]
				local output_item = self.items[2]

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
				self.items = {}
				self.data.item = nil
			end,
			items = {}
		}
	elseif inv_type == 'techreborn:auto_crafting_table' then
		inv = {
			size = 11,
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
			items = {},
		}
	elseif inv_type == 'techreborn:assembly_machine' then
		inv = {
			size = 3,
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
			items = {},
		}
	else
		error('Inventory type "'..inv_type..'" not recognized')
	end

	inv.name = inv_name
	inventories[inv_name] = inv
end

peripheral.custom.reset = function(option)
	if option == 'inventories' then
		inventories = {}
		peripheral.inventories = inventories
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
	elseif inv_slot > inv.size then
		error('Slot '..tostring(inv_slot)..' outside of range for '..inv_name)
	end

	if item_count == 0 then return 0 end

	local ethereal_item = {
		name = item_name,
		count = item_count,
	}
	local input_item = inv.items[inv_slot]
	local amount_added

	amount_added, ethereal_item, input_item = move_item(ethereal_item, input_item)

	inv.items[inv_slot] = input_item

	return amount_added
end

peripheral.custom.consume_item = function(inv_name, inv_slot, item_count)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	elseif inv_slot > inv.size then
		error('Slot '..tostring(inv_slot)..' outside of range for '..inv_name)
	end

	local item = inv.items[inv_slot]

	if item_count == 0 then return 0 end
	if not item then return 0 end
	if item.count < item_count then
		item_count = item.count
	end

	item.count = item.count - item_count

	if item.count == 0 then
		inv.items[inv_slot] = nil
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

peripheral.call = function(target, func_name, ...)
	local fn = peripheral[func_name]

	if fn then
		return peripheral[func_name](target, ...)
	else
		error('peripheral function "'..func_name..'" not found')
	end

end

peripheral.pushItems = function(output_inv_name, input_inv_name, output_slot, limit, input_slot)
	local output_inv = inventories[output_inv_name]
	local input_inv = inventories[input_inv_name]

	if not output_inv then
		error('output_inv does not exist')
		return
	elseif not input_inv then
		error('input_inv does not exist')
		return
	end

	if output_slot > output_inv.size then
		return 0
	elseif input_slot > input_inv.size then
		return 0
	end

	if limit == 0 then
		return 0
	end

	local output_item = output_inv.items[output_slot]
	local input_item = input_inv.items[input_slot]

	if not output_item then
		return 0
	elseif not input_item then
		input_item = {
			name = output_item.name,
			count = 0,
		}
		input_inv.items[input_slot] = input_item
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
		output_inv.items[output_slot] = nil
	end

	-- Updating inventories.
	output_inv:update()
	input_inv:update()

	return moved_amount
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

peripheral.size = function(inv_name)
	local inv = inventories[inv_name]

	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return inv.size
end

peripheral.list = function(inv_name)
	local inv = inventories[inv_name]
	
	if not inv then
		error('Inventory '..inv_name..' not found')
	end

	return table_deepcopy(inv.items)
end

peripheral.getSides = getSides

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

peripheral.getItemDetail = function(inv_name, inv_slot)
	local inv = inventories[inv_name] or error('Inventory '..inv_name..' not found')
	local item = inv.items[inv_slot]

	if not item then return nil end

	local item_data = table_deepcopy(items_data[item.name])

	item_data.name = item.name
	item_data.count = item.count
	return item_data
end

peripheral.test_module = function()
	print('Testing mock: peripheral')

	local vanilla_barrel
	local vanilla_chest
	local techreborn_storage_unit
	local auto_crafting_table
	local assembly_machine

	local function reset()
		peripheral.custom.reset('inventories')

		peripheral.custom.add_inventory('minecraft:barrel_0')
		peripheral.custom.produce_item('minecraft:barrel_0', 1, 'minecraft:coal', 64)
		peripheral.custom.produce_item('minecraft:barrel_0', 2, 'minecraft:coal', 32)
		peripheral.custom.produce_item('minecraft:barrel_0', 3, 'minecraft:coal', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 4, 'minecraft:ender_pearl', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 5, 'minecraft:ender_pearl', 10)
		peripheral.custom.produce_item('minecraft:barrel_0', 6, 'minecraft:wooden_sword', 1)
		peripheral.custom.add_inventory('minecraft:chest_0')
		peripheral.custom.add_inventory('techreborn:storage_unit_0')
		peripheral.custom.add_inventory('techreborn:auto_crafting_table_0')
		peripheral.custom.add_inventory('techreborn:assembly_machine_0')

		vanilla_barrel = inventories['minecraft:barrel_0']
		vanilla_chest = inventories['minecraft:chest_0']
		techreborn_storage_unit = inventories['techreborn:storage_unit_0']
		auto_crafting_table = inventories['techreborn:auto_crafting_table_0']
		assembly_machine = inventories['techreborn:assembly_machine_0']
	end

	local function test_initial_state()
		assert_equals(inventories['minecraft:barrel_0'].items[1].name, 'minecraft:coal')
		assert_equals(inventories['minecraft:barrel_0'].items[1].count, 64)
		assert_equals(inventories['minecraft:chest_0'].items[1], nil)
	end

	reset()

	test_utils.set_title('Testing full push item')
	test_initial_state()
	assert_equals(peripheral.pushItems('minecraft:barrel_0', 'minecraft:chest_0', 1, nil, 1), 64)
	assert_equals(vanilla_barrel.items[1], nil)
	assert_equals(vanilla_chest.items[1].name, 'minecraft:coal')
	assert_equals(vanilla_chest.items[1].count, 64)

	test_utils.set_title('Testing reset')
	reset()
	test_initial_state()

	test_utils.set_title('Testing limit')
	assert_equals(peripheral.pushItems('minecraft:barrel_0', 'minecraft:barrel_0', 1, 20, 10), 20)
	assert_equals(vanilla_barrel.items[1].name, 'minecraft:coal')
	assert_equals(vanilla_barrel.items[1].count, 44)
	assert_equals(vanilla_barrel.items[10].name, 'minecraft:coal')
	assert_equals(vanilla_barrel.items[10].count, 20)

	test_utils.set_title('Testing moving to a partially filled inventory')
	-- Also testing moving an item with a custom 'maxCount'.
	assert_equals(vanilla_barrel.items[4].name, 'minecraft:ender_pearl')
	assert_equals(vanilla_barrel.items[5].name, 'minecraft:ender_pearl')
	assert_equals(vanilla_barrel.items[4].count, 16)
	assert_equals(vanilla_barrel.items[5].count, 10)
	assert_equals(peripheral.pushItems('minecraft:barrel_0', 'minecraft:barrel_0', 4, nil, 5), 6)
	assert_equals(vanilla_barrel.items[4].count, 10)
	assert_equals(vanilla_barrel.items[5].count, 16)

	test_utils.set_title('Testing moving to a slot with a different item')
	assert_equals(vanilla_barrel.items[1].name, 'minecraft:coal')
	assert_equals(vanilla_barrel.items[4].name, 'minecraft:ender_pearl')
	assert_equals(peripheral.pushItems('minecraft:barrel_0', 'minecraft:barrel_0', 1, nil, 4), 0)
	assert_equals(vanilla_barrel.items[1].name, 'minecraft:coal')
	assert_equals(vanilla_barrel.items[4].name, 'minecraft:ender_pearl')

	test_utils.set_title('Testing size call')
	assert_equals(peripheral.size('minecraft:chest_0'), 27)
	test_utils.set_title('Testing equivalent \'call\' call.')
	assert_equals(peripheral.call('minecraft:chest_0', 'size'), 27)
	test_utils.set_title('Testing moving item outside of range.')
	assert_equals(peripheral.pushItems('minecraft:barrel_0', 'minecraft:barrel_0', 1, nil, 60), 0)

	test_utils.set_title('Testing \'getNamesRemote\' call')
	local inv_names = peripheral.getNamesRemote('bottom')
	custom_assert(array_contains(inv_names, 'minecraft:barrel_0'))
	custom_assert(array_contains(inv_names, 'minecraft:chest_0'))
	custom_assert(array_contains(inv_names, 'techreborn:storage_unit_0'))

	test_utils.set_title('Testing techreborn\'s storage unit item handling')
	peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 40)
	peripheral.custom.tick_inventory('techreborn:storage_unit_0')
	assert_equals(techreborn_storage_unit.data.item, nil)
	assert_equals(techreborn_storage_unit.items[2].count, 40)
	peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 40)
	peripheral.custom.tick_inventory('techreborn:storage_unit_0')
	assert_equals(techreborn_storage_unit.data.item.name, 'minecraft:iron_ingot')
	assert_equals(techreborn_storage_unit.data.item.count, 16)
	assert_equals(techreborn_storage_unit.items[2].count, 64)
	peripheral.custom.consume_item('techreborn:storage_unit_0', 2, 20)
	peripheral.custom.tick_inventory('techreborn:storage_unit_0')
	assert_equals(techreborn_storage_unit.data.item, nil)
	assert_equals(techreborn_storage_unit.items[2].count, 60)
	peripheral.custom.consume_item('techreborn:storage_unit_0', 2, 60)
	assert_equals(techreborn_storage_unit.items[2], nil)

	test_utils.set_title('Testing storage unit max item storage')
	-- Adding 2120 items to inventory.
	for i=1,106 do
		peripheral.custom.produce_item('techreborn:storage_unit_0', 1, 'minecraft:iron_ingot', 20)
		peripheral.custom.tick_inventory('techreborn:storage_unit_0')
	end
	assert_equals(techreborn_storage_unit.data.item.count, 2048)
	assert_equals(techreborn_storage_unit.items[1].count, 8)
	assert_equals(techreborn_storage_unit.items[2].count, 64)

	test_utils.set_title('Testing tech reborn autocrafting')
	peripheral.custom.produce_item('techreborn:auto_crafting_table_0', 1, 'minecraft:oak_log')
	peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
	assert_equals(auto_crafting_table.items[10].name, 'minecraft:oak_planks')
	assert_equals(auto_crafting_table.items[10].count, 4)
	peripheral.custom.consume_item('techreborn:auto_crafting_table_0', 10, 4)
	peripheral.custom.produce_item('techreborn:auto_crafting_table_0', 1, 'minecraft:oak_log', 32)
	peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
	assert_equals(auto_crafting_table.items[10].name, 'minecraft:oak_planks')
	assert_equals(auto_crafting_table.items[10].count, 64)
	assert_equals(auto_crafting_table.items[1].count, 16)
	peripheral.custom.consume_item('techreborn:auto_crafting_table_0', 10, 64)
	peripheral.custom.tick_inventory('techreborn:auto_crafting_table_0')
	assert_equals(auto_crafting_table.items[10].count, 64)
	assert_equals(auto_crafting_table.items[1], nil)

	test_utils.set_title('Testing tech reborn assembly_machine')
	peripheral.custom.produce_item('techreborn:assembly_machine_0', 1, 'techreborn:silicon_plate', 3)
	peripheral.custom.produce_item('techreborn:assembly_machine_0', 2, 'techreborn:electrum_plate', 7)
	peripheral.custom.tick_inventory('techreborn:assembly_machine_0')
	assert_equals(assembly_machine.items[3].name, 'techreborn:advanced_circuit')
	assert_equals(assembly_machine.items[3].count, 3)
	assert_equals(assembly_machine.items[2].name, 'techreborn:electrum_plate')
	assert_equals(assembly_machine.items[2].count, 1)

	test_utils.finish()
end

peripheral.custom.reset('inventories')

return peripheral
