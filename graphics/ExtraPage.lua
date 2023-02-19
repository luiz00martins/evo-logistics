local utils = require('/logos.utils')
local graphics_utils = require('graphics.utils')

local new_class = utils.new_class
local visual_button = graphics_utils.visual_button

local ExtraPage = new_class()

local width, _ = TERMINAL_WIDTH-2, TERMINAL_HEIGHT-1

function ExtraPage:new(main, functionalities)
	local extra_page = {}

	local main_frame = main:addFrame("ExtraPage_main_frame")
		:setPosition(1,2)
		:setBackground(colors.lightGray)
		:setSize(TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
		:hide()

	local buttons = {}
	for i,v in ipairs(functionalities) do
		local button = main_frame:addButton('button_'..tostring(i))
			:setPosition(2, i+1)
			:setSize(width, 1)
			:setValue(v.text)

		visual_button(button)

		button:onClick(function()
			v.task()
		end)

		buttons[v.var] = button
	end

	extra_page.main_frame = main_frame
	extra_page.buttons = buttons

	setmetatable(extra_page, ExtraPage)

	return extra_page
end

return ExtraPage
