local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')

local get_connected_inventories = utils.get_connected_inventories
local array_map = utils.array_map
local new_class = utils.new_class

local width, _ = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1

local InventoriesPage = new_class()

local CLUSTERS_DISPLAY_SIZE = 12

function InventoriesPage:new(main, clusters, interface_cluster)
	local inventories_page = {}

	local main_frame = main:addFrame("InventoriesPage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
		:setScrollable(true)
		:hide()

	local cluster_names = array_map(clusters, function(cluster) return cluster.name end)

	inventories_page.main_frame = main_frame
	inventories_page.clusters = clusters
	inventories_page.cluster_names = cluster_names
	inventories_page.interface_cluster = interface_cluster
	inventories_page.buttons = {}
	inventories_page.dropdowns = {}
	inventories_page.inv_components = {}

	setmetatable(inventories_page, InventoriesPage)

	return inventories_page
end

function InventoriesPage:_setListSize(size)
	local old_size = #self.textfields
	local change = size - old_size

	if change > 0 then
		for i=old_size+1,old_size+change do
			local textfield = self.main_frame:addTextfield('button_'..tostring(i))
				:setPosition(2, i+1)
				:setSize(width-CLUSTERS_DISPLAY_SIZE-1, 1)
				:onScroll(function() return false end)
				:disable()

			local dropdown = self.main_frame:addDropdown('dropdown_'..tostring(i))
				:setPosition(width-CLUSTERS_DISPLAY_SIZE+2, i+1)
				:setSize(CLUSTERS_DISPLAY_SIZE, 1)
				:setZIndex(size+10-i)

			for _,cluster_name in ipairs(self.cluster_names) do
				dropdown:addItem(cluster_name)
			end
			dropdown:addItem('None')

			self.textfields[i] = textfield
			self.dropdowns[i] = dropdown
		end
	elseif change < 0 then
		for i=old_size,old_size+change+1,-1 do
			self.main_frame:removeObject(self.textfields[i])
			self.main_frame:removeObject(self.dropdowns[i])

			self.textfields[i] = nil
			self.dropdowns[i] = nil
		end
	end
end

function InventoriesPage:refresh()
	local inv_names = get_connected_inventories()
	local inv_components = self.inv_components

	local remaining_components = {}

	for _,inv_name in ipairs(inv_names) do
		if inv_components[inv_name] then
			remaining_components[inv_name] = inv_components[inv_name]
		else
			local button = self.main_frame:addTextfield('button_'..inv_name)
				:setSize(width-CLUSTERS_DISPLAY_SIZE-1, 1)
				:addLine(inv_name)
				:onScroll(function() return false end)
				:disable()

			local dropdown = self.main_frame:addDropdown('dropdown_'..inv_name)
				:setSize(CLUSTERS_DISPLAY_SIZE, 1)

			for _,cluster_name in ipairs(self.cluster_names) do
				dropdown:addItem(cluster_name)
			end
			dropdown:addItem('None')

			dropdown:selectItem(#self.cluster_names+1)

			for j, cluster in ipairs(self.clusters) do
				if cluster:hasInventory(inv_name) then
					dropdown:selectItem(j)
					break
				end
			end

			dropdown.previous_selection = dropdown:getItemIndex()

			dropdown:onChange(function(_)
				local selected_option = dropdown:getItemIndex()
				local oldCluster = self.clusters[dropdown.previous_selection]

				queue:add{
					name = 'Changing inventory '..inv_name..' to cluster '..(oldCluster or {name = 'None'}).name,
					fn = function()
						local options = dropdown:getAll()

						-- if the selected option is 'None'.
						if selected_option == #options then
							if oldCluster then
								oldCluster:unregisterInventory(inv_name)
								oldCluster:save()
							end
						else
							-- if the previous option is a cluster (instead os 'None').
							if dropdown.previous_selection ~= #options then
								oldCluster:unregisterInventory(inv_name)
								oldCluster:save()
							end

							local newCluster = self.clusters[selected_option]
							newCluster:registerInventory{inv_name = inv_name}
							newCluster:save()
						end

						dropdown.previous_selection = selected_option
					end
				}
			end)

			remaining_components[inv_name] = {
				button = button,
				dropdown = dropdown,
			}
		end
	end

	table.sort(remaining_components,
		function(a, b)
			return a.button:getLine(1) < b.button:getLine(1)
		end)

	self.inv_components = remaining_components
	self.textfields = {}
	self.dropdowns = {}

	local size = #self.inv_components
	local i = 1
	for _,components in pairs(self.inv_components) do
		self.textfields[i] = components.button:setPosition(2, i+1)
		self.dropdowns[i] = components.dropdown:setPosition(width-CLUSTERS_DISPLAY_SIZE+2, i+1)

		self.textfields[i]
			:setPosition(2, i+1)
		self.dropdowns[i]
			:setPosition(width-CLUSTERS_DISPLAY_SIZE+2, i+1)
			:setZIndex(size+10-i)

		i = i + 1
	end
end

return InventoriesPage
