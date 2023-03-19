local utils = require('/logos-library.utils.utils')
local core = require('/logos-library.core.abstract')
local bulk = require('/logos-library.core.bulk')
local standard = require('/logos-library.core.standard')
local crafting = require('/logos-library.core.crafting')
local interface = require('/logos-library.core.interface')
local test_utils = require('/logos-library.tests.utils')

local array_contains = utils.array_contains
local array_map = utils.array_map
local custom_assert = test_utils.custom_assert
local assert_equals = test_utils.assert_equals

local transfer = core.transfer

local BulkCluster = bulk.BulkCluster
local StandardCluster = standard.StandardCluster
local CraftingCluster = crafting.CraftingCluster
local InterfaceCluster = interface.InterfaceCluster
local CraftingProfile = crafting.CraftingProfile

local function test_module()
	print('Testing module: storage')

	local original_peripheral = peripheral
	peripheral = require('/logos-library.tests.mocks.peripheral')

	local main_cluster
	local bulk_cluster
	local io_cluster
	local crafting_cluster
	local interface_cluster

	local clusters = {main_cluster, bulk_cluster, io_cluster, crafting_cluster}

	local function reset()
		main_cluster = StandardCluster:new{name = 'Main Cluster'}
		bulk_cluster = BulkCluster:new{name = 'Bulk Cluster'}
		io_cluster = StandardCluster:new{name = 'IO Cluster'}
		interface_cluster = InterfaceCluster:new{
			name = 'Interface Cluster',
			storage_clusters = {bulk_cluster, main_cluster},
		}
		crafting_cluster = CraftingCluster:new{
			name = 'Crafting Cluster',
			storage_clusters = {bulk_cluster, main_cluster, interface_cluster},
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
				[1] = {
					type = 'input',
					item_name = 'minecraft:oak_log',
					amount = 1,
				},
				[10] = {
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
				[1] = {
					type = 'input',
					item_name = 'techreborn:silicon_plate',
					amount = 1,
				},
				[2] = {
					type = 'input',
					item_name = 'techreborn:electrum_plate',
					amount = 2,
				},
				[3] = {
					type = 'output',
					item_name = 'techreborn:advanced_circuit',
					amount = 1,
				},
			},
		}
		crafting_cluster:addProfile(act_profile)
		crafting_cluster:addProfile(am_profile)
	end

	reset()

	test_utils.set_title('Testing refreshing')
	peripheral.custom.produce_item('minecraft:barrel_0', 1, 'minecraft:coal', 64)
	peripheral.custom.produce_item('minecraft:barrel_0', 2, 'minecraft:coal', 32)
	peripheral.custom.produce_item('minecraft:barrel_0', 3, 'minecraft:coal', 16)
	peripheral.custom.produce_item('minecraft:barrel_0', 4, 'minecraft:ender_pearl', 16)
	peripheral.custom.produce_item('minecraft:barrel_0', 5, 'minecraft:ender_pearl', 10)
	peripheral.custom.produce_item('minecraft:barrel_0', 6, 'minecraft:wooden_sword', 1)
	main_cluster:catalog()
	custom_assert(main_cluster:hasItem('minecraft:wooden_sword'))
	assert_equals(main_cluster:itemCount('minecraft:coal'), 112)
	assert_equals(main_cluster:itemCount('minecraft:ender_pearl'), 26)

	test_utils.set_title('Testing clusters input and output')
	for _,cluster in ipairs(clusters) do
		local inv_name = cluster.invs[1].name
		peripheral.custom.produce_item(inv_name, 1, 'minecraft:coal', 40)
		cluster:refresh()
		test_utils.set_title('Testing clusters input and output ('..cluster.name..')')
		custom_assert(cluster:inputState())
		custom_assert(cluster:outputState())
		assert_equals(cluster:outputState():itemName(), 'minecraft:coal')
	end

	test_utils.set_title('Testing moving from IO to main storage')
	peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:coal', 40)
	io_cluster:refresh()
	custom_assert(io_cluster:hasItem('minecraft:coal'))
	assert_equals(io_cluster:itemCount('minecraft:coal'), 40)
	assert_equals(transfer(io_cluster, main_cluster), 40)
	assert_equals(main_cluster:itemCount('minecraft:coal'), 152)
	peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:iron_ingot', 30)
	peripheral.custom.produce_item('minecraft:chest_0', 2, 'minecraft:coal', 20)
	io_cluster:refresh()
	assert_equals(transfer(io_cluster, main_cluster), 50)
	assert_equals(main_cluster:itemCount('minecraft:iron_ingot'), 30)

	test_utils.set_title('Storing to bulk storage')
	-- TODO: This transfers twice rn, because the chest is too small. Change this test to use a big barrel from extendedstorage.
	bulk_cluster:setItemInventory('techreborn:storage_unit_0', 'minecraft:iron_ingot')
	for slot=1,20 do
		peripheral.custom.produce_item('minecraft:chest_0', slot, 'minecraft:iron_ingot', 60)
	end
	io_cluster:refresh()
	assert_equals(transfer(io_cluster, bulk_cluster, 'minecraft:iron_ingot'), 1200)
	for slot=1,20 do
		peripheral.custom.produce_item('minecraft:chest_0', slot, 'minecraft:iron_ingot', 60)
	end
	io_cluster:refresh()
	assert_equals(transfer(io_cluster, bulk_cluster, 'minecraft:iron_ingot'), 976)
	peripheral.custom.clear_inventory('minecraft:chest_0')
	peripheral.custom.clear_inventory('minecraft:barrel_0')
	io_cluster:refresh()
	main_cluster:refresh()

	test_utils.set_title('Testing crafting')

	local missing_items = crafting_cluster:calculateMissingItems('techreborn:advanced_circuit', 1)
	local missing_item_names = array_map(missing_items, function(item) return item.name end)
	custom_assert(array_contains(missing_item_names, 'techreborn:silicon_plate'))
	custom_assert(array_contains(missing_item_names, 'techreborn:electrum_plate'))
	peripheral.custom.produce_item('minecraft:chest_0', 1, 'techreborn:silicon_plate', 4)
	peripheral.custom.produce_item('minecraft:chest_0', 2, 'techreborn:electrum_plate', 8)
	io_cluster:refresh()
	assert_equals(transfer(io_cluster, main_cluster), 12)
	crafting_cluster:executeCraftingTree(
		crafting_cluster:createCraftingTree('techreborn:advanced_circuit', 4)
	)
	assert_equals(main_cluster:itemCount('techreborn:advanced_circuit'), 4)

	test_utils.set_title('Testing stacking')
	-- The items are added one by one...
	reset()
	for _=1,20 do
		peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:stick')
		io_cluster:refresh()
		transfer(io_cluster, main_cluster)
	end
	-- ...but they should stack inside the inventory.
	assert_equals(peripheral.call('minecraft:barrel_0', 'list')[1].count, 20)

	reset()
	test_utils.set_title('Testing item handling')

	peripheral.custom.produce_item('minecraft:chest_0', 1, 'minecraft:oak_log', 64)
	io_cluster:refresh()
	bulk_cluster:registerItem('minecraft:oak_log')
	assert_equals(transfer(io_cluster, bulk_cluster), 64)

	-- TODO: Remove Volatile storage (let's be real, it's useless now), and add 'inputState' and 'outputState' to CraftingCluster.
	test_utils.set_title('Testing all inputs')
	reset()
	bulk_cluster:registerItem('minecraft:coal')
	-- Generating dummy output cluster.
	peripheral.custom.add_inventory('minecraft:barrel_1')
	local output_cluster = StandardCluster:new{name = 'Dummy Cluster'}
	output_cluster:registerInventory{name = 'minecraft:barrel_1'}
	-- Inputting to all clusters.
	for _,cluster in ipairs(clusters) do
		peripheral.custom.produce_item('minecraft:barrel_1', 1, 'minecraft:coal', 10)
		output_cluster:refresh()
		assert_equals(transfer(output_cluster, cluster), 10)
		assert_equals(cluster:itemCount('minecraft:coal'), 10)
	end


	test_utils.set_title('Testing all outputs')
	reset()
	-- Generating dummy input cluster.
	peripheral.custom.add_inventory('minecraft:barrel_1')
	local input_cluster = StandardCluster:new{name = 'Dummy Cluster'}
	input_cluster:registerInventory{name = 'minecraft:barrel_1'}
	-- Inputting from all clusters.
	for i,cluster in ipairs(clusters) do
		peripheral.custom.produce_item(cluster.invs[1].name, 1, 'minecraft:coal', 10)
		peripheral.custom.tick_inventory(cluster.invs[1].name)
		cluster:refresh()
		assert_equals(transfer(cluster, input_cluster), 10)
		assert_equals(input_cluster:itemCount('minecraft:coal'), 10*i)
	end

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

	test_utils.finish()

	peripheral = original_peripheral
end



return {
	test_module = test_module,
}
