--Basalt configurated installer
local filePath = "/basalt.lua" --here you can change the file path default: basalt
if not(fs.exists(filePath))then
    shell.run("pastebin run ESs1mg7P packed true "..filePath:gsub(".lua", "")) -- this is an alternative to the wget command
end
local basalt = require(filePath:gsub(".lua", ""))

local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')

string.split = utils.string_split

local getOrder = utils.getOrder
local transfer = require('logistics.storage.core').transfer
local StandardCluster = require('logistics.storage.standard').StandardCluster
local BulkCluster = require('logistics.storage.bulk').BulkCluster
local VolatileCluster = require('logistics.storage.volatile').VolatileCluster
local CraftingCluster = require('logistics.storage.crafting').CraftingCluster
local InterfaceCluster = require('logistics.storage.interface').InterfaceCluster

local MainPage = require('graphics.MainPage')
local ExtraPage = require('graphics.ExtraPage')
local InventoriesPage = require('graphics.InventoriesPage')
local CraftingPage = require('graphics.CraftingPage')
local QueuePage = require('graphics.QueuePage')
local InterfacePage = require('graphics.InterfacePage')

local main_storage = StandardCluster:new{name = "main cluster"}
local io_storage = StandardCluster:new{name = "io cluster"}
local bulk_storage = BulkCluster:new{name = "bulk cluster"}
local interface_cluster = InterfaceCluster:new{
	name = "interface cluster",
	storage_clusters = {bulk_storage, main_storage}
}
local crafting_cluster = CraftingCluster:new{
	name = "crafting cluster",
	storage_clusters = {bulk_storage, main_storage, interface_cluster},
}

local clusters = {io_storage, bulk_storage, main_storage, crafting_cluster, interface_cluster}
local storage_clusters = {bulk_storage, main_storage}

local function refresh()
		--devIO:stdout_write("Refreshing clusters... ")

		for _,cluster in ipairs(clusters) do
			cluster:refresh()
		end
end

local function catalog()
		--devIO:stdout_write("Catalogging clusters... ")

		for _,cluster in ipairs(clusters) do
			cluster:catalog()
		end
end

local function storeAll()
	local notStored = {}

	io_storage:refresh()

	-- TODO: Change this to use the new 'transfer'.
	local moved
	for _, inv in pairs(io_storage.invs) do
		for _, item_state in pairs(inv.states) do
			local item = item_state:item()
			if item ~= nil then
				if bulk_storage.invsItem[item.name] then
					moved = transfer(io_storage, bulk_storage, io_storage, bulk_storage, item.name)
				else
					moved = transfer(io_storage, main_storage, io_storage, main_storage, item.name)
				end

				if moved == 0 then
					notStored[item.name] = true
				end
			end
		end
	end

	for itemName,_ in pairs(notStored) do
		--devIO:stdout_write("WARNING: '"..itemName.."' not stored (inventory full)")
	end

	return true
end

-- FIXME: I've deleted the bulk cluster file, and for some reason now the rest isn't working. Find out why.
local function save_clusters()
	for _,cluster in pairs(clusters) do
		cluster:save()
	end
end

local function load_clusters()
	for _,cluster in pairs(clusters) do
		if not cluster:load() then
			utils.log("File "..cluster:data_path().." not found, skipping.")
		end
	end
end

local function get_items_data()
	local clusters = {bulk_storage, main_storage}

	local cmp = function(a,b)
		-- `nil` is interpreted as infinity for de purposes of ordering.
		if a == nil then
			return true
		elseif b == nil then
			return false
		else
			return a > b
		end
	end

	local items_data = {}

	for _,cluster in ipairs(clusters) do
		for _,item_name in ipairs(getOrder(cluster._itemCount, cmp)) do
			local i = #items_data+1

			items_data[#items_data+1] = {
				name = item_name,
				count = cluster._itemCount[item_name],
				cluster = cluster,
			}
		end
	end

	return items_data
end

local w, h = term.getSize()

local main = basalt.createFrame("mainFrame")
local main_page = MainPage:new(main, io_storage, crafting_cluster, storage_clusters, save_clusters)
local inventories_page = InventoriesPage:new(main, clusters)
local crafting_page = CraftingPage:new(main, crafting_cluster, storage_clusters)
local queue_page = QueuePage:new(main, crafting_cluster, storage_clusters)
local interface_page = InterfacePage:new(main, interface_cluster, storage_clusters)

local extra_page = ExtraPage:new(main, {
	{
		var = 'store',
		text = 'Store All',
		task = function()
			queue:add{
				name = 'Storing',
				fn = function()
					io_storage:refresh()
					storeAll()
					main_page:refresh()
					save_clusters()
				end
			}
		end,
	},{
		var = 'refresh',
		text = 'Refresh',
		task = function()
			queue:add{
				name = 'Refreshing Inventory',
				fn = function()
					refresh()
					save_clusters()
				end
			}
		end,
	},{
		var = 'catalog',
		text = 'Catalog',
		task = function()
			queue:add{
				name = 'Catalogging Inventory',
				fn = function()
					catalog()
					save_clusters()
				end
			}
		end,
	},{
		var = 'recount',
		text = 'Recount',
		task = function()
			queue:add{
				name = 'Recounting Inventory',
				fn = function()
					bulk_storage:recount()
					save_clusters()
				end
			}
		end,
	},{
		var = 'sort',
		text = 'Sort Inventory',
		task = function()
			queue:add{
				name = 'Sorting Inventory',
				fn = function()
					main_storage:pack()
					main_storage:sort()
					main_storage:pack()
				end
			}
		end,
	},{
		var = 'test',
		text = 'Test',
		task = function()
		end,
	},
})

local menuBar = main:addMenubar("mainMenuBar")
	:addItem("Main")
	:addItem("Extra")
	:addItem("Invs")
	:addItem("Crafting")
	:addItem("Interface")
	:addItem("Queue")
	:setBackground(colors.gray)
	:setSize(w, 1)
	:setSpace(2)
	:setScrollable()
	:show()

menuBar:onChange(function(self)
	main_page.main_frame:hide()
	extra_page.main_frame:hide()
	inventories_page.main_frame:hide()
	crafting_page.main_frame:hide()
	queue_page.main_frame:hide()
	interface_page.main_frame:hide()

	if(self:getValue().text=="Main")then
		main_page.main_frame:show()
	elseif(self:getValue().text=="Extra")then
		extra_page.main_frame:show()
	elseif(self:getValue().text=="Invs")then
		inventories_page:refresh()
		inventories_page.main_frame:show()
	elseif(self:getValue().text=="Crafting")then
		crafting_page.main_frame:show()
	elseif(self:getValue().text=="Interface")then
		interface_page.main_frame:show()
	elseif(self:getValue().text=="Queue")then
		queue_page:refresh()
		queue_page.main_frame:show()
	end
end)

local queue_thread = main:addThread()
local function execute_queue()
	while true do
		while not queue:is_empty() do
			queue:execute_next()
			queue_page:refresh()
		end
		os.sleep(0.1)
	end
end
queue_thread:start(execute_queue)

queue:add{
	name = 'Loading Clusters',
	fn = function()
		load_clusters()
		refresh()

		main_page:refresh()
		main_page:updateList()
		inventories_page:refresh()
		crafting_page:refresh()
	end
}

queue:add{
	name = 'Cleaning up crafting stations',
	fn = function()
		for _,storage_cluster in ipairs(storage_clusters) do
			transfer(crafting_cluster, storage_cluster)
		end
	end
}

main_page.main_frame:show()
basalt.autoUpdate()


