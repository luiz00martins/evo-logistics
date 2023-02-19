local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')
local graphics_utils = require('graphics.utils')

local table_shallowcopy = utils.table_shallowcopy
local array_map = utils.array_map
local array_filter = utils.array_filter
local get_order = utils.get_order
local shorten_item_names = utils.shorten_item_names
local new_class = utils.new_class
local visual_button = graphics_utils.visual_button
local transfer = require('logistics.storage.core').transfer

local ITEM_COUNT_SIZE = 5
local ITEM_COUNT_FORMATS = {'k', 'm', 'b', 't', 'q', 'Q', 's', 'S'}
TERMINAL_WIDTH, TERMINAL_HEIGHT = term.getSize()

local function format_item_count(count)
	local normalized_count = count
	local magnitude = ''

	for _,m in ipairs(ITEM_COUNT_FORMATS) do
		if normalized_count > 1000 then
			magnitude = m
			normalized_count = normalized_count / 1000
		else
			break
		end
	end

	local normalized_string = tostring(normalized_count):sub(1,4)
	if normalized_string:sub(#normalized_string, #normalized_string) == '.' then
		normalized_string = normalized_string:sub(1,#normalized_string-1)
	end

	return normalized_string..string.rep(' ', ITEM_COUNT_SIZE - (1 + #normalized_string))..magnitude
end

local MainPage = new_class()

-- FIXME: Use 'callback' argument
function MainPage:new(main, io_stor, crafting_cluster, storage_clusters, callback)
	local main_page = {}

	local main_frame = main:addFrame("MainPage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
		:hide()

	local width, height = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1

	local search_box = main_frame:addInput("item_name")
		:setPosition(2, 2)
		:setSize(width-ITEM_COUNT_SIZE, 1)
		:setBackground(colors.black)
		:setForeground(colors.lightGray)
		:setDefaultText("Item Name", colors.gray)
		:show()

	local amount_input = main_frame:addInput("amount")
		:setPosition(width-ITEM_COUNT_SIZE+2, 2)
		:setSize(ITEM_COUNT_SIZE, 1)
		:setBackground(colors.black)
		:setForeground(colors.lightGray)
		:setDefaultText("Amnt", colors.gray)
		:show()

	local function refresh_search()
		main_page:updateList(search_box:getValue() or '')
	end

	search_box:onChange(function(_)
		refresh_search()
	end)

	amount_input:onChange(function(_)
		refresh_search()
	end)

	-- Set up rows.
	local item_buttons = {}
	local item_counts = {}
	for i=1,height-3 do
		local button = main_frame:addButton("button_"..tostring(i))
			:setText('')
			:setSize(width-ITEM_COUNT_SIZE,1)
			:setPosition(2,i+2)
			:setHorizontalAlign('left')
			:onClick(function() end)
			:show()

		visual_button(button)

		local count = main_frame:addTextfield('item_count_'..tostring(i))
			:setSize(ITEM_COUNT_SIZE, 1)
			:setPosition(width-ITEM_COUNT_SIZE+2, i+2)
			:disable()

		button:onClickUp(function(_)
			local item_name = main_page.items[i].name
			local choice = amount_input:getValue()
			queue:add{
				name = 'Crafting '..tostring(count)..' '..item_name,
				fn = function()
					local amount

					if choice == 'all' then
						amount = main_frame.items_data_table[item_name].count
					elseif choice == '' then
						amount = 1
					else
						amount = tonumber(choice)

						if not amount then
							-- TODO: Add warning message.
							return
						else
							amount = math.floor(amount)
						end
					end

					local total_moved = 0
					local retrieve_from_clusters = function()
						for _, cluster in ipairs(storage_clusters) do
							if amount > 0 and cluster:itemCount(item_name) and cluster:itemCount(item_name) > 0 then
								local moved = transfer(cluster, io_stor, cluster, io_stor, item_name, amount)
								if moved == 0 then
									io_stor:refresh()
									moved = transfer(cluster, io_stor, cluster, io_stor, item_name, amount)
								end

								total_moved = total_moved + moved
								if moved < amount then
									-- TODO: Add warning message.
									--devIO:stdout_write("WARNING: Haul not fully completed ("..moved.."/"..amount..")\n")
								else
									break
								end
							end
						end
					end

					retrieve_from_clusters()
					if total_moved < amount then
						local craft_amount = amount - total_moved
						local missing_items = crafting_cluster:calculateMissingItems(item_name, craft_amount)
						if #missing_items == 0 then
							local crafting_tree = crafting_cluster:createCraftingTree(item_name,  craft_amount)
							crafting_cluster:executeCraftingTree(crafting_tree)
							retrieve_from_clusters()
						else
							for _,item in ipairs(missing_items) do
								utils.log('WARNING: Did not craft ' .. utils.tostring(item.count) .. ' ' .. utils.tostring(item.name))
							end
						end
					end

					-- Saving clusters.
					for _,cluster in pairs(storage_clusters) do
						cluster:save("/logistics_data/"..cluster.name)
					end

					--search_box:setValue('')
					--search_box:setFocus(false)
					--search_box:setFocus(true)

					main_page:refresh()
				end
			}
		end)
	
		item_buttons[i] = button
		item_counts[i] = count
	end

	main_page.storage_clusters = storage_clusters
	main_page.crafting_cluster = crafting_cluster
	main_page.main_frame = main_frame
	main_page.search_box = search_box
	main_page.amount_input = amount_input
	main_page.item_buttons = item_buttons
	main_page.item_counts = item_counts
	main_page.items = {}

	setmetatable(main_page, MainPage)

	main_page:refresh()

	return main_page
end

function MainPage:updateList(search_text)
	search_text = search_text or ''
	local matching = array_filter(self.items_data_array, function(v) return v.name:find(search_text) end)
	local item_buttons = self.item_buttons
	local item_counts = self.item_counts
	local items = self.items

	local item_names = array_map(matching, function(item) return item.name end)
	local short_item_names = shorten_item_names(item_names)

	local i = 1
	while matching[i] and item_buttons[i] do
		local item = matching[i]

		item_buttons[i]:setValue(short_item_names[i])
		item_counts[i]:removeLine()
		item_counts[i]:addLine(format_item_count(item.count))
		items[i] = item

		i = i + 1
	end

	while item_buttons[i] do
		item_buttons[i]:setValue('')
		item_counts[i]:removeLine()
		item_counts[i]:addLine('')
		items[i] = nil

		i = i + 1
	end
end

function MainPage:refresh()
	local items_data_array = {}
	local items_data_table = {}
	local tracker = {}

	local clusters = table_shallowcopy(self.storage_clusters)
	clusters[#clusters+1] = self.crafting_cluster

	for _, cluster in ipairs(clusters) do
		for _, item_name in ipairs(cluster:itemNames()) do
			if item_name ~= 'empty' then
				local i = tracker[item_name]
				if not i then
					i = #items_data_array+1
					tracker[item_name] = i
					items_data_array[i] = {
						name = item_name,
						count = 0,
					}
				end

				items_data_array[i].count = items_data_array[i].count + cluster:itemCount(item_name)
				items_data_table[item_name] = items_data_array[i]
			end
		end
	end

	local cmp = function(a, b) return a.count > b.count end

	self.items_data_table = items_data_table
	self.items_data_array = {}
	for i,j in ipairs(get_order(items_data_array, cmp)) do
		self.items_data_array[i] = items_data_array[j]
	end
end

return MainPage
