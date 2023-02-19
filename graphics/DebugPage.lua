local utils = require('logistics.utils.utils')

local array_map = utils.array_map
local new_class = utils.new_class

local w, h = term.getSize()

local DebugPage = new_class()

function DebugPage:new(main)
	local debug_frame = main:addFrame("debug_frame"):setPosition(1,2):setBackground(colors.lightGray):setSize(w, h-1):hide()

	local text_field = debug_frame:addTextfield("exampleTextfield"):setPosition(2,2):setBackground(colors.black):setSize(w-2,h-3):setForeground(colors.white):show()

	function debug_frame:log(text)
		if text == nil then
			text = 'nil'
		elseif type(text) == 'table' then
			text = array_map(text, tostring)
			text = table.concat(text, ' ')
		else
			text = tostring(text)
		end

		text_field:addLine(text)
	end


	return debug_frame
end

return DebugPage
