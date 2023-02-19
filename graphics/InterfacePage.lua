local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')
local graphics_utils = require('graphics.utils')
local basalt = require('/basalt')

local get_connected_inventories = utils.get_connected_inventories
local array_filter = utils.array_filter
local array_map = utils.array_map
local get_order = utils.get_order
local new_class = utils.new_class
local visual_button = graphics_utils.visual_button

local width, height = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1

local InterfacePage = new_class()

local CLUSTERS_DISPLAY_SIZE = 12

function InterfacePage:new(main, interface_cluster)
	local interface_page = {}

	local main_frame = main:addFrame("InterfacePage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
		:setScrollable(true)
		:hide()

	local boxes = {
		{'passive_importer', 'Passive Importer'},
		{'active_importer', 'Active Importer'},
		{'passive_exporter', 'Passive Exporter'},
		{'active_exporter', 'Active Exporter'},
	}

	local checkboxes = {}
	local buttons = {}
	for i,box in ipairs(boxes) do
		checkboxes[i] = main_frame:addCheckbox('Checkbox_'..boxes[i][1])
			:setPosition(2, i*2)
		main_frame:addLabel('Label_'..boxes[i][1])
			:setText(boxes[i][2])
			:setPosition(4, i*2)
	end

	interface_page.main_frame = main_frame
	interface_page.checkboxes = checkboxes
	interface_page.buttons = buttons

	setmetatable(interface_page, InterfacePage)

	return interface_page
end

function InterfacePage:_setListSize(size)
	local old_size = #self.textfields
	local change = size - old_size

	if change > 0 then
		for i=old_size+1,old_size+change do
			local textfield = self.main_frame:addTextfield('textfield_'..tostring(i))
				:setPosition(2, i+1)
				:setSize(width-CLUSTERS_DISPLAY_SIZE-1, 1)
				:onScroll(function() return false end)
				:disable()

			local button = self.main_frame:addButton('button_'..tostring(i))
				:setPosition(width-CLUSTERS_DISPLAY_SIZE+2, i+1)
				:setSize(CLUSTERS_DISPLAY_SIZE, 1)
				:setValue('Cancel')
		
			self.textfields[i] = textfield
			self.buttons[i] = button
		end
	elseif change < 0 then
		for i=old_size,old_size+change+1,-1 do
			self.main_frame:removeObject(self.textfields[i])
			self.main_frame:removeObject(self.buttons[i])

			self.textfields[i] = nil
			self.buttons[i] = nil
		end
	end
end

function InterfacePage:_buildTypeSubpage(type)
	
end

function InterfacePage:_buildInvSubpage(subpage)
	
end

function InterfacePage:refresh()
	self:_setListSize(queue.scheduled.length + queue.executing.length)

	local inv_pages = self.main_frame:addFrame('inv_pages')

	local i = 1
	for task in queue.executing:iterate() do
		self.textfields[i]:removeLine()
		self.textfields[i]:addLine(task.name or '<no name>')
		i = i + 1
	end

	for task in queue.scheduled:iterate() do
		self.textfields[i]:removeLine()
		self.textfields[i]:addLine(task.name or '<no name>')
		i = i + 1
	end
end

return InterfacePage


