local utils = require('/logos.utils')
local graphics_utils = require('graphics.utils')
local basalt = require('/basalt')
local crafting = require('logistics.storage.crafting')

local get_connected_inventories = utils.get_connected_inventories
local shorten_item_names = utils.shorten_item_names
local string_split = utils.string_split
local table_contains = utils.table_contains
local array_unique = utils.array_unique
local array_filter = utils.array_filter
local new_class = utils.new_class
local visual_button = graphics_utils.visual_button
local create_subframe = graphics_utils.create_subframe

local CraftingProfile = crafting.CraftingProfile
local SearchPicker = require('graphics.SearchPicker')

local width, height = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1
local page_width, page_height = TERMINAL_WIDTH, TERMINAL_HEIGHT-1


local function get_inventory_types()
	local invs = get_connected_inventories()
	local inv_types = {}

	for _, inv_name in ipairs(invs) do
		-- Removing number at the end.
		inv_name = string_split(inv_name, '_')
		inv_name[#inv_name] = nil
		inv_name = table.concat(inv_name, '_')

		if not table_contains(inv_types, inv_name) then
			inv_types[#inv_types+1] = inv_name
		end
	end

	return inv_types
end

local CraftingPage = new_class()

function CraftingPage:new(main, crafting_cluster, storage_clusters)

	local crafting_page = {}

	crafting_page.main_frame = main:addFrame("CraftingPage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(page_width, page_height)
		:setScrollable(true)
		:hide()

	crafting_page.storage_clusters = storage_clusters
	crafting_page.crafting_cluster = crafting_cluster
	crafting_page.profile_buttons = {}
	crafting_page.profile_frames = {}
	crafting_page.recipe_buttons = {}
	crafting_page.recipe_frames = {}
	crafting_page.new_recipe_frames = {}

	setmetatable(crafting_page, CraftingPage)

	crafting_page:_createNewProfileFrame()
	crafting_page:_refreshProfileFrames()

	return crafting_page
end

function CraftingPage:refresh()
	self:_refreshProfileFrames()
end

function CraftingPage:_createNewProfileFrame()
	local new_profile_button = self.main_frame:addButton('new_profile_button')
		:setPosition(2,2)
		:setSize(width, 1)
		:setValue('Create New Profile')

	local new_profile_frame = create_subframe(self.main_frame, new_profile_button)

	local name_input = new_profile_frame:addInput('name_input')
		:setPosition(2, 3)
		:setSize(width-1, 1)
		:setDefaultText('Profile Name')

	local middle = math.floor(width/2)

	-- Accept button
	local accept_button = new_profile_frame
		:addButton('accept_button')
		:setPosition(2, height-1)
		:setSize(width-(middle+1), 1)
		:setValue('accept')
	visual_button(accept_button)
	--accept_button.colour = colours.green

	-- Cancel button
	local cancel_button = new_profile_frame
		:addButton('cancel_button')
		:setPosition(middle+2, height-1)
		:setSize(width-(middle), 1)
		:setValue('cancel')
	visual_button(cancel_button)
	--cancel_button.colour = colours.red

	-- Inv types
	local inv_types = get_inventory_types()
	local inv_types_dropdown = new_profile_frame
		:addDropdown('inv_types_dropdown')
		:setPosition(2, 4)
		:setSize(width-1, 1)
		:setDropdownSize(width-1, 6)
	for _,inv_type in pairs(inv_types) do
		inv_types_dropdown:addItem(inv_type)
	end

	-- FIXME: What... what is this even used for. I think nothing, this should be removed.
	local size
	inv_types_dropdown:onChange(function(dropdown)
		local i = dropdown:getItemIndex()
		local inv_type = inv_types[i]
		local inventories = get_connected_inventories()

		for _,inv_name in ipairs(inventories) do
			-- FIXME: This is literally 'inventory_type(inv_name)'.
			local stripped = string_split(inv_name, '_')
			stripped[#stripped] = nil
			stripped = table.concat(stripped, '_')

			if stripped == inv_type then
				size = peripheral.call(inv_name, "size")
			end
		end
	end)

	accept_button:onClick(function(button)
		local inv_type = inv_types_dropdown:getItem(inv_types_dropdown:getItemIndex()).text
		local name = name_input:getValue()

		local profile = CraftingProfile:new{
			name = name,
			inv_type = inv_type,
		}

		self.crafting_cluster:addProfile(profile)
		self.crafting_cluster:refresh()
		self.crafting_cluster:save("/logistics_data/"..self.crafting_cluster.name)
		self:refresh()
	end)

	self.new_profile_frame = new_profile_frame
end

function CraftingPage:_refreshProfileFrames()
	for i=1,#self.profile_buttons do
		self.profile_buttons[i]:getParent():removeObject(self.profile_buttons[i])
		self.profile_frames[i]:getParent():removeObject(self.profile_frames[i])
		self.new_recipe_buttons[i]:getParent():removeObject(self.new_recipe_buttons[i])
		self.new_recipe_frames[i]:getParent():removeObject(self.new_recipe_frames[i])
	end
	self.profile_buttons = {}
	self.profile_frames = {}
	self.new_recipe_buttons = {}
	self.new_recipe_frames = {}

	for i=1,#self.recipe_buttons do
		self.recipe_buttons[i]:getParent():removeObject(self.recipe_buttons[i])
		self.recipe_frames[i]:getParent():removeObject(self.recipe_frames[i])
	end
	self.recipe_buttons = {}
	self.recipe_frames = {}

	local profile_buttons = self.profile_buttons
	local profile_frames = self.profile_frames

	for i,profile in ipairs(self.crafting_cluster.profiles) do
		local profile_button = self.main_frame:addButton('profile_button_'..profile.name)
			:setPosition(2, i+3)
			:setSize(width, 1)
			:setValue(profile.name)

		local profile_frame = create_subframe(self.main_frame, profile_button)
			:setScrollable(true)

		local inv_type = profile_frame:addTextfield()
			:setPosition(2, 3)
			:setSize(width, 1)
			:addLine(profile.inv_type)
			:disable()
	
		local recipe_dropdowns = self:_refreshRecipeFrames(profile_frame, profile)
	
		local new_recipe_dropdown = self:_createNewRecipeFrame(profile_frame, profile)
	
		profile_buttons[#profile_buttons+1] = profile_button
		profile_frames[#profile_frames+1] = profile_frame
	end
	
	self.profile_buttons = profile_buttons
	self.profile_frames = profile_frames
end

function CraftingPage:_refreshRecipeFrames(profile_frame, profile)
	local recipe_buttons = self.recipe_buttons
	local recipe_frames = self.recipe_frames
	local inv_size = profile.inv_size
	
	for i,recipe in ipairs(profile.recipes) do
		local recipe_button = profile_frame:addButton('recipe_'..recipe.name)
			:setPosition(2, i+4)
			:setSize(width, 1)
			:setValue(recipe.name)

		local recipe_frame = create_subframe(profile_frame, recipe_button)
			:setScrollable(true)

		local slots_frame = recipe_frame:addFrame('slots_frame')
			:setPosition(2, 3)
			:setSize(width, inv_size)
			:setScrollable(true)

		local delete_button = recipe_frame:addButton('delete_buton')
			:setPosition(2, height-1)
			:setSize(width, 1)
			:setValue('Delete Recipe')
		--delete_button.colour = colours.red

		local self_page = self
		local picker = self.picker
		local picker_window = self.picker_window

		delete_button:onClick(function(button)
			profile:removeRecipe(recipe.name)
			self.crafting_cluster:refresh()
			self.crafting_cluster:save("/logistics_data/"..self_page.crafting_cluster.name)
			self:refresh()
		end)

		local x1 = math.floor(width*(0/4))+1
		local x2 = math.floor(width*(1/4))+1
		local x3 = math.floor(width*(2/4))+1
		local x4 = math.floor(width*(3/4))+1

		local slots = {}
		for i=1,inv_size do
			local text = slots_frame:addTextfield('name_'..tostring(i))
				:setPosition(x1, i)
				:setSize(x2-x1, 1)
				:addLine('Slot '..tostring(i))
			local type = slots_frame:addDropdown('type_'..tostring(i))
				:setPosition(x2, i)
				:setSize(x3-x2, 1)
				:setZIndex(#profile.recipes+10-i)
				:addItem('None')
				:addItem('Input')
				:addItem('Output')
			type:selectItem(1)
			local item = slots_frame:addButton('item_'..tostring(i))
				:setPosition(x3, i)
				:setSize(x4-x3, 1)
				:setValue('item')
			local amount = slots_frame:addInput('amount_'..tostring(i))
				:setPosition(x4, i)
				:setSize(width-(x4+2))

			item:onClick(function()
				self:addChild(picker_window)
				picker:focusOn()
				picker.input.text = ''
				picker.options = self_page:getItemNames()
				picker:updateList()

				picker.handler = function(item_name)
					item.text = item_name
					self_page:removeChild(picker_window)
				end
			end)

			slots[#slots+1] = {
				text = text,
				type = type,
				item = item,
				amount = amount,
			}
		end

		for i,slot_data in pairs(recipe.slots) do
			local slot = slots[i]

			if slot_data.type == 'input' then
				slot.type:selectItem(2)
			else
				slot.type:selectItem(3)
			end

			slot.item:setValue(slot_data.item_name)
			slot.amount:setValue(tostring(slot_data.amount))
		end

		recipe_buttons[#recipe_buttons+1] = recipe_button
		recipe_frames[#recipe_frames+1] = recipe_frame
	end

	self.recipe_buttons = recipe_buttons
	self.recipe_frames = recipe_frames
end

function CraftingPage:_createNewRecipeFrame(profile_frame, profile)
	local new_recipe_button = profile_frame:addButton('new_recipe_button')
		:setPosition(2, 3)
		:setSize(width, 1)
		:setValue('Create New Recipe')
	--new_recipe_frame.header_button.colour = colours.green
	--new_recipe_frame.dropdown_icon.colour = colours.green

	local new_recipe_frame = create_subframe(profile_frame, new_recipe_button)
		:setScrollable(true)

	table.insert(self.new_recipe_buttons, new_recipe_button)
	table.insert(self.new_recipe_frames, new_recipe_frame)

	local middle = math.floor(width/2)

	-- Accept button
	local accept_button = new_recipe_frame:addButton('accept_button')
		:setPosition(2, height)
		:setSize(width-(middle+1), 1)
		:setValue('accept')
	--accept_button.colour = colours.green

	-- Cancel button
	local cancel_button = new_recipe_frame:addButton('cancel_button')
		:setPosition(middle+2, height)
		:setSize(width-(middle), 1)
		:setValue('cancel')
	--cancel_button.colour = colours.red

	-- Inv types
	local name_input = new_recipe_frame:addInput('name_input')
		:setPosition(2, 3)
		:setSize(width, 1)
		:setDefaultText('Recipe Name')
	local slots_frame = new_recipe_frame:addFrame('slots_frame')
		:setPosition(2, 4)
		:setSize(width, height-5)
		:setScrollable(true)

	-- Handling item names.
	local item_names = {}
	local short_item_names = {}
	local get_full_name = {}
	
	local function refresh_item_names()
		item_names = array_filter(self:getItemNames(), function(item_name) return item_name ~= 'empty' end)
		short_item_names = shorten_item_names(item_names)
		get_full_name = {}
		for i=1,#item_names do
			get_full_name[short_item_names[i]] = item_names[i]
		end
	end

	local slots = {}
	local search_picker = SearchPicker:new(new_recipe_frame)

	local x1 = math.floor(width*(0/4))+1
	local x2 = math.floor(width*(1/4))+1
	local x3 = math.floor(width*(2/4))+1
	local x4 = math.floor(width*(3/4))+1
	for i=1,profile.inv_size do
		local text = slots_frame:addTextfield('text_'..tostring(i))
			:setPosition(x1, i)
			:setSize(x2-x1-1, 1)
			:addLine('Slot '..tostring(i))
		local type = slots_frame:addDropdown('type_'..tostring(i))
			:setPosition(x2, i)
			:setSize(x3-x2-1, 1)
			:setZIndex(profile.inv_size+10-i)
			:addItem('None')
			:addItem('Input')
			:addItem('Output')
		type:selectItem(1)
		local item = slots_frame:addButton('item'..tostring(i))
			:setPosition(x3, i)
			:setSize(x4-x3-1, 1)
			:setValue('item')
		local amount = slots_frame:addInput('amount_'..tostring(i))
			:setPosition(x4, i)
			:setSize(width-(x4+2))
			:setDefaultText('Amount')

		item:onClick(function(button)
			refresh_item_names()

			search_picker.options = short_item_names
			search_picker.handler = function(short_item_name)
				item:setValue(short_item_name)
				-- Setting defaults.
				if amount:getValue() == '' then
					amount:setValue('1') 
				end
				if type:getItemIndex() == 1 then
					type:selectItem(2)
				end
			end

			search_picker:refresh()
			search_picker:show()
			search_picker:setFocus()
		end)

		slots[#slots+1] = {
			type = type,
			item = item,
			amount = amount,
		}
	end

	accept_button:onClick(function(button)
		self.main_frame:show()

		local recipe = {
			name = name_input:getValue(),
			slots = {}
		}

		for i,slot in ipairs(slots) do
			if slot.type:getItemIndex() ~= 1 then
				local type
				if slot.type:getItemIndex() == 2 then
					type = 'input'
				else
					type = 'output'
				end

				local item_name = get_full_name[slot.item:getValue()]
				local amount = tonumber(slot.amount:getValue())

				recipe.slots[i] = {
					type = type,
					item_name = item_name,
					amount = amount,
				}
			end
		end

		profile:addRecipe(recipe)
		self.crafting_cluster:refresh()
		self.crafting_cluster:save("/logistics_data/"..self.crafting_cluster.name)
		-- TODO: This can be optimized, by only refreshing the profile's page, instead of everything.
		self:refresh()
	end)

	return new_recipe_frame
end

function CraftingPage:getItemNames()
	local item_names = {}

	local clusters = table_shallowcopy(self.storage_clusters)
	clusters[#clusters+1] = self.crafting_cluster

	for _, cluster in ipairs(clusters) do
		for _, item_name in ipairs(cluster:itemNames()) do
			item_names[#item_names+1] = item_name
		end
	end

	return array_unique(item_names)
end

return CraftingPage
