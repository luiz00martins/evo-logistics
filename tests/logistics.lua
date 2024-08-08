local Ut = require("cc-ut")
local utils = require('/logos-library.utils.utils')
local core = require('/logos-library.core.abstract')
local bulk = require('/logos-library.core.bulk')
local standard = require('/logos-library.core.standard')
local crafting = require('/logos-library.core.crafting')
local interface = require('/logos-library.core.interface')

local ut = Ut()
local test = ut.test
local describe = ut.describe

local array_contains = utils.array_contains
local array_map = utils.array_map

local transfer = core.transfer

local BulkCluster = bulk.BulkCluster
local StandardCluster = standard.StandardCluster
local CraftingCluster = crafting.CraftingCluster
local InterfaceCluster = interface.InterfaceCluster
local CraftingProfile = crafting.CraftingProfile

local function test_module()
	local original_peripheral = peripheral
	peripheral = require('/logos-library.tests.mocks.peripheral')

	local main_cluster
	local bulk_cluster
	local io_cluster
	local crafting_cluster
	local interface_cluster

	local log = require('/logos-library.utils.log').file('/tests.log')

	local function reset()
		main_cluster = StandardCluster:new{
			name = 'Main Cluster',
			log = log,
		}
		bulk_cluster = BulkCluster:new{
			name = 'Bulk Cluster',
			log = log,
		}
		io_cluster = StandardCluster:new{
			name = 'IO Cluster',
			log = log,
		}
		interface_cluster = InterfaceCluster:new{
			name = 'Interface Cluster',
			storage_clusters = {bulk_cluster, main_cluster},
			log = log,
		}
		crafting_cluster = CraftingCluster:new{
			name = 'Crafting Cluster',
			storage_clusters = {bulk_cluster, main_cluster, interface_cluster},
			log = log,
		}

		peripheral.custom.reset('inventories')
		peripheral.custom.add_inventory('minecraft:barrel_0')
		peripheral.custom.add_inventory('minecraft:chest_0')
		peripheral.custom.add_inventory('techreborn:storage_unit_0')
		peripheral.custom.add_inventory('techreborn:auto_crafting_table_0')
		peripheral.custom.add_inventory('techreborn:assembly_machine_0')
		peripheral.custom.add_inventory('minecraft:chest_1')

		main_cluster:registerInventory{name = 'minecraft:barrel_0'}
		io_cluster:registerInventory{name = 'minecraft:chest_0'}
		bulk_cluster:registerInventory{name = 'techreborn:storage_unit_0'}
		crafting_cluster:registerInventory{name = 'techreborn:auto_crafting_table_0'}
		crafting_cluster:registerInventory{name = 'techreborn:assembly_machine_0'}
		interface_cluster:registerInventory{name = 'minecraft:chest_1'}

		local act_profile = CraftingProfile:new{
			name = 'Auto Crafting Table',
			inv_type = 'techreborn:auto_crafting_table',
		}
		act_profile:addRecipe{
			name = 'Wooden Planks',
			is_shaped = true,
			slots = {
				{
					index = 1,
					type = 'input',
					item_name = 'minecraft:oak_log',
					amount = 1,
				},
				{
					index = 10,
					type = 'output',
					item_name = 'minecraft:oak_planks',
					amount = 4,
				},
			},
		}
		local am_profile = CraftingProfile:new{
			name = 'Assembly Machine',
			inv_type = 'techreborn:assembly_machine',
		}
		am_profile:addRecipe{
			name = 'Advanced Circuit',
			is_shaped = true,
			slots = {
				{
					index = 1,
					type = 'input',
					item_name = 'techreborn:silicon_plate',
					amount = 1,
				},
				{
					index = 2,
					type = 'input',
					item_name = 'techreborn:electrum_plate',
					amount = 2,
				},
				{
					index = 3,
					type = 'output',
					item_name = 'techreborn:advanced_circuit',
					amount = 1,
				},
			},
		}
		crafting_cluster:addProfile(act_profile)
		crafting_cluster:addProfile(am_profile)
	end

	test('refreshing', function(expect)
		reset()
		peripheral.custom.produce_item('minecraft:barrel_0', 1, 'minecraft:coal', 64)
		peripheral.custom.produce_item('minecraft:barrel_0', 2, 'minecraft:coal', 32)
		peripheral.custom.produce_item('minecraft:barrel_0', 3, 'minecraft:coal', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 4, 'minecraft:ender_pearl', 16)
		peripheral.custom.produce_item('minecraft:barrel_0', 5, 'minecraft:ender_pearl', 10)
		peripheral.custom.produce_item('minecraft:barrel_0', 6, 'minecraft:wooden_sword', 1)
		main_cluster:catalog()

		expect(main_cluster:hasItem('minecraft:wooden_sword')).toEqual(true)
		expect(main_cluster:itemCount('minecraft:coal')).toEqual(112)
		expect(main_cluster:itemCount('minecraft:ender_pearl')).toEqual(26)
	end)

	describe('moving items', function(test)
		test('moving from IO to main storage', function(expect)
			reset()
			peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:coal', 40)
			io_cluster:refresh()
			expect(io_cluster:hasItem('minecraft:coal')).toEqual(true)
			expect(io_cluster:itemCount('minecraft:coal')).toEqual(40)
			expect(transfer(io_cluster, main_cluster)).toEqual(40)
			expect(io_cluster:itemCount('minecraft:coal')).toEqual(0)
			expect(main_cluster:itemCount('minecraft:coal')).toEqual(40)
			peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:iron_ingot', 30)
			peripheral.custom.produce_item('minecraft:chest_0', 2, 'minecraft:coal', 20)
			io_cluster:refresh()
			expect(transfer(io_cluster, main_cluster)).toEqual(50)
			expect(main_cluster:itemCount('minecraft:iron_ingot')).toEqual(30)
		end)

		test('inputting to all clusters', function(expect)
			reset()
			bulk_cluster:registerItem('minecraft:coal')
			-- Generating dummy output cluster.
			peripheral.custom.add_inventory('minecraft:barrel_1')
			local output_cluster = StandardCluster:new{name = 'Dummy Cluster'}
			output_cluster:registerInventory{name = 'minecraft:barrel_1'}
			-- Inputting to all clusters.
			for _,cluster in ipairs({main_cluster, bulk_cluster, io_cluster}) do
				peripheral.custom.produce_item('minecraft:barrel_1', 1, 'minecraft:coal', 10)
				output_cluster:refresh()
				expect(transfer(output_cluster, cluster)).toEqual(10)
				expect(cluster:itemCount('minecraft:coal')).toEqual(10)
			end
		end)

		test('outputting from all clusters', function(expect)
			reset()
			-- Generating dummy input cluster.
			peripheral.custom.add_inventory('minecraft:barrel_1')
			local input_cluster = StandardCluster:new{name = 'Dummy Cluster'}
			input_cluster:registerInventory{name = 'minecraft:barrel_1'}
			-- Inputting from all clusters.
			for i,cluster in ipairs({main_cluster, bulk_cluster, io_cluster}) do
				peripheral.custom.produce_item(cluster.invs[1].name, 1, 'minecraft:coal', 10)
				peripheral.custom.tick_inventory(cluster.invs[1].name)
				cluster:refresh()
				expect(transfer(cluster, input_cluster)).toEqual(10)
				expect(input_cluster:itemCount('minecraft:coal')).toEqual(10*i)
			end
		end)

		test('storing to bulk storage', function(expect)
			reset()
			-- TODO: This transfers twice rn, because the chest is too small. Change this test to use a big barrel from extendedstorage.
			bulk_cluster:setItemInventory('techreborn:storage_unit_0', 'minecraft:iron_ingot')
			for slot=1,20 do
				peripheral.custom.produce_item('minecraft:chest_0', slot, 'minecraft:iron_ingot', 60)
			end
			io_cluster:refresh()
			expect(transfer(io_cluster, bulk_cluster, 'minecraft:iron_ingot')).toEqual(1200)
			for slot=1,20 do
				peripheral.custom.produce_item('minecraft:chest_0', slot, 'minecraft:iron_ingot', 60)
			end
			io_cluster:refresh()
			expect(transfer(io_cluster, bulk_cluster, 'minecraft:iron_ingot')).toEqual(976)
			peripheral.custom.clear_inventory('minecraft:chest_0')
			peripheral.custom.clear_inventory('minecraft:barrel_0')
			io_cluster:refresh()
			main_cluster:refresh()
		end)

		test('moving from IO to bulk storage', function(expect)
			reset()
			peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:oak_log', 64)
			io_cluster:refresh()
			bulk_cluster:registerItem('minecraft:oak_log')
			expect(transfer(io_cluster, bulk_cluster)).toEqual(64)
		end)
	end)

	describe('crafting', function(test)
		test('normal', function(expect)
			reset()
			local missing_items = crafting_cluster:calculateMissingItems('techreborn:advanced_circuit', 1)
			local missing_item_names = array_map(missing_items, function(item) return item.name end)
			expect(array_contains(missing_item_names, 'techreborn:silicon_plate')).toEqual(true)
			expect(array_contains(missing_item_names, 'techreborn:electrum_plate')).toEqual(true)
			peripheral.custom.produce_item('minecraft:chest_0', 1, 'techreborn:silicon_plate', 4)
			peripheral.custom.produce_item('minecraft:chest_0', 2, 'techreborn:electrum_plate', 8)
			io_cluster:refresh()
			expect(transfer(io_cluster, main_cluster)).toEqual(12)
			crafting_cluster:executeCraftingTree(
				crafting_cluster:createCraftingTree('techreborn:advanced_circuit', 4)
			)
			expect(main_cluster:itemCount('techreborn:advanced_circuit')).toEqual(4)
		end)

		test('multiple crafting stations', function(expect)
			reset()
			peripheral.custom.tick_freeze(true)
			peripheral.custom.add_inventory('techreborn:assembly_machine_1')
			crafting_cluster:registerInventory{name = 'techreborn:assembly_machine_1'}
			peripheral.custom.produce_item('minecraft:barrel_0', 1, 'techreborn:silicon_plate', 4)
			peripheral.custom.produce_item('minecraft:barrel_0', 2, 'techreborn:electrum_plate', 8)
			main_cluster:refresh()
			local found_all = false
			parallel.waitForAny(
				function()
					crafting_cluster:executeCraftingTree(
						crafting_cluster:createCraftingTree('techreborn:advanced_circuit', 2)
					)
				end,
				function()
					while #peripheral.call('techreborn:assembly_machine_0', 'list') == 0 do
						os.sleep(0)
					end
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[1].name).toEqual('techreborn:silicon_plate')
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[1].count).toEqual(1)
					expect(peripheral.call('techreborn:assembly_machine_1', 'list')[1].name).toEqual('techreborn:silicon_plate')
					expect(peripheral.call('techreborn:assembly_machine_1', 'list')[1].count).toEqual(1)
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[2].name).toEqual('techreborn:electrum_plate')
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[2].count).toEqual(2)
					expect(peripheral.call('techreborn:assembly_machine_1', 'list')[2].name).toEqual('techreborn:electrum_plate')
					expect(peripheral.call('techreborn:assembly_machine_1', 'list')[2].count).toEqual(2)
					found_all = true
				end,
				function()
					os.sleep(0.01)
				end
			)
			expect(found_all).toBeTruthy()
		end)

		test('multiple crafting recipes', function(expect)
			reset()
			peripheral.custom.tick_freeze(true)
			peripheral.custom.produce_item('minecraft:barrel_0', 1, 'techreborn:silicon_plate', 1)
			peripheral.custom.produce_item('minecraft:barrel_0', 2, 'techreborn:electrum_plate', 2)
			peripheral.custom.produce_item('minecraft:barrel_0', 3, 'minecraft:oak_log', 1)
			main_cluster:refresh()
			local found_all = false
			parallel.waitForAny(
				function()
					crafting_cluster:executeCraftingTree(
						crafting_cluster:createCraftingTree('techreborn:advanced_circuit', 1)
					)
				end,
				function()
					crafting_cluster:executeCraftingTree(
						crafting_cluster:createCraftingTree('minecraft:oak_planks', 1)
					)
				end,
				function()
					while #peripheral.call('techreborn:assembly_machine_0', 'list') == 0
							or #peripheral.call('techreborn:auto_crafting_table_0', 'list') == 0 do
						os.sleep(0)
					end
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[1].name).toEqual('techreborn:silicon_plate')
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[1].count).toEqual(1)
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[2].name).toEqual('techreborn:electrum_plate')
					expect(peripheral.call('techreborn:assembly_machine_0', 'list')[2].count).toEqual(2)
					expect(peripheral.call('techreborn:auto_crafting_table_0', 'list')[1].name).toEqual('minecraft:oak_log')
					expect(peripheral.call('techreborn:auto_crafting_table_0', 'list')[1].count).toEqual(1)
					found_all = true
				end,
				function()
					os.sleep(0.01)
				end
			)
			expect(found_all).toBeTruthy()
		end)
	end)

	describe('corner cases', function(test)
		test('stacking', function(expect)
			-- The items are added one by one...
			reset()
			for _=1,20 do
				peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:stick')
				io_cluster:refresh()
				transfer(io_cluster, main_cluster)
			end
			-- ...but they should stack inside the inventory.
			expect(peripheral.call('minecraft:barrel_0', 'list')[1].count).toEqual(20)
		end)
	end)


	-- test_utils.set_title('Testing interface active import')
	-- reset()
	--
	-- peripheral.custom.produce_item(main_cluster.invs[1].name, 1, 'minecraft:coal', 60)
	-- main_cluster:refresh()
	--
	-- interface_cluster:registerConfig{
	-- 	type = 'active_import',
	-- 	inv_name = interface_cluster.invs[1].name,
	-- 	slot = 1,
	-- 	item_name = 'minecraft:coal',
	-- 	count = 20,
	-- }
	-- interface_cluster:execute()
	-- interface_cluster:refresh()
	-- assert_equals(interface_cluster:itemCount('minecraft:coal'), 20)
	-- peripheral.custom.clear_inventory(interface_cluster.invs[1].name)
	-- interface_cluster:refresh()
	-- assert_equals(interface_cluster:itemCount('minecraft:coal'), 0)
	-- interface_cluster:execute()
	-- interface_cluster:refresh()
	-- assert_equals(interface_cluster:itemCount('minecraft:coal'), 20)
	--
	-- test_utils.set_title('Testing interface passive export')
	-- interface_cluster:registerConfig{
	-- 	type = 'passive_export',
	-- 	inv_name = interface_cluster.invs[1].name,
	-- 	item_name = 'minecraft:oak_log',
	-- }
	-- peripheral.custom.produce_item(interface_cluster.invs[1].name, 2, 'minecraft:oak_log', 60)
	-- interface_cluster:refresh()
	-- crafting_cluster:executeCraftingTree(
	-- 	crafting_cluster:createCraftingTree('minecraft:oak_planks', 4)
	-- )

	peripheral = original_peripheral
end



return {
	test_module = test_module,
}
