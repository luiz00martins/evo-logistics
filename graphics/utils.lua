local utils = require('/logos.utils')
local basalt = require('/basalt')

local function visual_button(btn)
    btn:onClick(function(self) btn:setBackground(colors.black) btn:setForeground(colors.lightGray) end)
    btn:onClickUp(function(self) btn:setBackground(colors.gray) btn:setForeground(colors.black) end)
    btn:onLoseFocus(function(self) btn:setBackground(colors.gray) btn:setForeground(colors.black) end)
end

local subframe_depth = {}

local function create_subframe(page, go_button)
	local parent = page:getParent()
	local page_width, page_height = parent:getSize()

	local subframe = parent:addFrame('subframe_'..page:getName()..'_'..go_button:getName())
		:setPosition(1, 1)
		:setSize(page_width, page_height)
		:setBackground(colors.lightGray)
		:hide()

	if subframe_depth[page] then
		subframe_depth[subframe] = subframe_depth[page] + 1
	else
		subframe_depth[subframe] = 1
	end

	local back_button = subframe:addButton('back_button')
		:setPosition(1, 1)
		:setSize(page_width, 1)
		:setValue(string.rep('<', subframe_depth[subframe]))
	visual_button(back_button)

	go_button:onClick(function()
		subframe:show()
		page:hide()
	end)

	back_button:onClick(function()
		page:show()
		subframe:hide()
	end)

	return subframe, back_button
end

return {
	visual_button = visual_button,
	create_subframe = create_subframe,
}
