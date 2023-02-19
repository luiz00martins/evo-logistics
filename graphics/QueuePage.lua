local utils = require('/logos.utils')
local queue = require('logistics.utils.queue')

local new_class = utils.new_class

local width, _ = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1

local QueuePage = new_class()

local CLUSTERS_DISPLAY_SIZE = 12

function QueuePage:new(main)
	local queue_page = {}

	local main_frame = main:addFrame("QueuePage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
		:setScrollable(true)
		:hide()

	queue_page.main_frame = main_frame
	queue_page.buttons = {}
	queue_page.textfields = {}

	setmetatable(queue_page, QueuePage)

	return queue_page
end

function QueuePage:_setListSize(size)
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

function QueuePage:refresh()
	self:_setListSize(queue.scheduled.length + queue.executing.length)

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

return QueuePage

