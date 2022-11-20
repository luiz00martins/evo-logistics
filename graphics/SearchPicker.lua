local utils = require('/logos.utils')
local graphics_utils = require('graphics.utils')

local array_filter = utils.array_filter
local new_class = utils.new_class
local visual_button = graphics_utils.visual_button

local SearchPicker = new_class()

function SearchPicker:new(parent)
	local width, height = parent:getSize()

	local search_picker = {}

	local main_frame = parent:addFrame('picker_window')
		:setPosition(2, 3)
		:setSize(width-2, height-4)
		:setBackground(colors.black)
		:setZIndex(1000)
		:hide()

	local self_width, self_height = main_frame:getSize()
	
	local options = options or {}
	local handler = handler or function(picked) end
	local input = main_frame:addInput('input')
		:setPosition(2, 2)
		:setSize(self_width-2, 1)
		:setDefaultText('Item Name')

	local function run_and_exit(button)
		search_picker.handler(button:getValue())
		search_picker.main_frame:hide()
		input:setValue('')
	end

	local buttons = {}
	for i=1,height-7 do
		local button = main_frame:addButton('button_'..tostring(i))
			:setPosition(2, i+2)
			:setSize(self_width-2, 1)
			:setValue('')

		button:onClick(function()
			run_and_exit(button)
		end)
		visual_button(button)

		buttons[i] = button
	end
	
	input:onChange(function()
		search_picker:refresh()
	end)

	input:onKey(function(_, event, key)
		-- Enter
		if key == 257 then
			run_and_exit(buttons[1])
		end
	end)

	search_picker.main_frame = main_frame
	search_picker.options = options
	search_picker.handler = handler
	search_picker.input = input
	search_picker.buttons = buttons

	setmetatable(search_picker, SearchPicker)

	return search_picker
end

function SearchPicker:refresh()
	local options = self.options
	if type(options) == 'function' then
		options = options()
	end

	local text = self.input:getValue()
	local matching = array_filter(self.options, function(v) return v:find(text) end)

	for i=1,#self.buttons do
		local match = matching[i]
		if match then
			self.buttons[i]:setValue(match)
		else
			self.buttons[i]:setValue('')
		end
	end	
end

function SearchPicker:show()
	self.main_frame:show()
end

function SearchPicker:hide()
	self.main_frame:hide()
end

function SearchPicker:setFocus()
	self.main_frame:setFocus()
	self.input:setFocus()
end

return SearchPicker
