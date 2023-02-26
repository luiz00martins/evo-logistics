--Basalt configurated installer
local filePath = "/basalt.lua" --here you can change the file path default: basalt
if not(fs.exists(filePath))then
    shell.run("pastebin run ESs1mg7P packed true "..filePath:gsub(".lua", "")) -- this is an alternative to the wget command
end
local basalt = require(filePath:gsub(".lua", ""))

local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')

string.split = utils.string_split

local transfer = require('logistics.storage.core').transfer
local StandardCluster = require('logistics.storage.standard').StandardCluster
local OrderedCluster = require('logistics.storage.ordered').OrderedCluster
local BulkCluster = require('logistics.storage.bulk').BulkCluster
local BarrelCluster = require('logistics.storage.barrel').BarrelCluster
local CraftingCluster = require('logistics.storage.crafting').CraftingCluster
local InterfaceCluster = require('logistics.storage.interface').InterfaceCluster

local MainPage = require('graphics.MainPage')
local ExtraPage = require('graphics.ExtraPage')
local InventoriesPage = require('graphics.InventoriesPage')
local CraftingPage = require('graphics.CraftingPage')
local QueuePage = require('graphics.QueuePage')
local InterfacePage = require('graphics.InterfacePage')

local main_storage = OrderedCluster:new{name = "main cluster"}
local io_storage = StandardCluster:new{name = "io cluster"}
local bulk_storage = BulkCluster:new{name = "bulk cluster"}
local barrel_storage = BarrelCluster:new{name = "barrel cluster"}
local interface_cluster = InterfaceCluster:new{
	name = "interface cluster",
	storage_clusters = {barrel_storage, bulk_storage, main_storage}
}
local crafting_cluster = CraftingCluster:new{
	name = "crafting cluster",
	storage_clusters = {barrel_storage, bulk_storage, main_storage, interface_cluster},
}

local clusters = {io_storage, barrel_storage, bulk_storage, main_storage, crafting_cluster, interface_cluster}
local storage_clusters = {barrel_storage, bulk_storage, main_storage}

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

	io_storage:catalog()
	local moved
	for _, inv in pairs(io_storage.invs) do
		for _, item_state in pairs(inv.states) do
			local item = item_state:item()
			if item ~= nil then
				if barrel_storage.invs_with_item[item.name] then
					moved = transfer(io_storage, barrel_storage, item.name)
				elseif bulk_storage.invs_with_item[item.name] then
					moved = transfer(io_storage, bulk_storage, item.name)
				else
					moved = transfer(io_storage, main_storage, item.name)
				end

				if moved == 0 then
					notStored[item.name] = true
				end
			end
		end
	end

	for item_name,_ in pairs(notStored) do
		utils.log("WARNING: '"..item_name.."' not stored (inventory full)")
	end

	return true
end

local function save_clusters()
	for _,cluster in pairs(clusters) do
		cluster:save()
	end
end

local function load_clusters()
	for _,cluster in pairs(clusters) do
		if not cluster:load() then
			utils.log("File "..cluster:dataPath().." not found, skipping.")
		end
	end
end

local w, _ = term.getSize()

local main = basalt.createFrame("mainFrame")
local main_page = MainPage:new(main, io_storage, crafting_cluster, storage_clusters, save_clusters)
local inventories_page = InventoriesPage:new(main, clusters)
local crafting_page = CraftingPage:new(main, crafting_cluster, storage_clusters)
local queue_page = QueuePage:new(main)
local interface_page = InterfacePage:new(main, interface_cluster)

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
					barrel_storage:recount()
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
			-- crafting_cluster:transfer(storage_cluster)
		end
	end
}

main_page.main_frame:show()


local function log_traceback()
	utils.log(debug.traceback())
end

local ok, res = xpcall(basalt.autoUpdate, log_traceback)
if not ok then
	error(res)
end

