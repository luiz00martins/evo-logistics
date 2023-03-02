local utils = require('/logos.utils')
local graphics_utils = require('graphics.utils')
local SearchableList = require('graphics.SearchableList')

local new_class = utils.new_class
local array_filter = utils.array_filter
local visual_button = graphics_utils.visual_button

local SearchPicker = new_class(SearchableList)

function SearchPicker:new(args)
	local newSearchPicker = SearchableList.new(self, args)

	newSearchPicker.handler = args.handler

	local function run_and_exit(button)
		if button then
			newSearchPicker.handler(button:getValue())
		end

		newSearchPicker.main_frame:hide()
		newSearchPicker.search_bar:setValue('')
	end

	newSearchPicker.searcher = function(item_data, search)
		return item_data:lower():find(search:lower())
	end

	function newSearchPicker.item_builder(parent, index, button_data)
		local width, _ = parent:getSize()

		local button = parent:addButton('button_'..index)
			:setSize(width - 2, 1)
			:setValue(button_data)

		button:onClick(function()
			run_and_exit(button)
		end)
		visual_button(button)

		return button
	end

	local parent_width, parent_height = args.parent:getSize()
	newSearchPicker.main_frame
		:setPosition(2, 4)
		:setSize(parent_width-2, parent_height-6)
		--:setBackground(colors.black)
		:setZIndex(1000)

	newSearchPicker.search_bar
		:setPosition(1, 1)
		:setSize(parent_width, 1)
		:setDefaultText('Search Text')

	newSearchPicker.search_bar:onKey(function(_, _, key)
		-- Enter
		if key == 257 then
			run_and_exit(newSearchPicker.items[newSearchPicker.matching_items[1]])
		end
	end)

	setmetatable(newSearchPicker, SearchPicker)

	return newSearchPicker
end

-- function SearchPicker:refresh()
--  local options = self.options
--  if type(options) == 'function' then
--    options = options()
--  end
--
--  local text = self.search_bar:getValue()
--  local matching = array_filter(self.options, function(v) return v:find(text) end)
--
--  for i=1,#self.items do
--    local match = matching[i]
--    if match then
--      self.items[i]:setValue(match)
--    else
--      self.items[i]:setValue('')
--    end
--  end
-- end

function SearchPicker:show()
	self.main_frame:show()
end

function SearchPicker:hide()
	self.main_frame:hide()
end

function SearchPicker:setFocus()
	self.main_frame:setFocus()
	self.search_bar:setFocus()
end

return SearchPicker
