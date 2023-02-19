local utils = require('/logos.utils')

local new_class = utils.new_class

local SearchableList = new_class()

function SearchableList:new(args)
	local newSearchableList = {
		parent = args.parent,
		-- Format of the item builder function:
		--  item_builder(parent, index, item_data) -> item
		--  params:
		--   parent: the parent component
		--   index: the index of the item in the list
		--   item_data: the data for the item
		--   item: the item component (may be a table of items)
		item_builder = args.item_builder,
		-- Format of the search function:
		-- search(item_data, query) -> boolean
		--  params:
		--   item_data: the data of the item
		--   query: the query to search for
		searcher = args.searcher,
		-- An array of item data.
		data = args.data,
		items = {},
		matching_items = {},
	}

	local width, height = args.parent:getSize()

	newSearchableList.main_frame  = args.parent:addFrame(args.name or 'searchable_list')
		:setPosition(2, 3)
		:setSize(width-2, height-3)

	newSearchableList.search_bar = newSearchableList.main_frame:addInput('search_bar')
		:setPosition(1, 1)
		:setSize(width, 1)
		:setDefaultText('Search Text')

	newSearchableList.search_bar:onChange(function()
		newSearchableList:refresh()
	end)

	setmetatable(newSearchableList, SearchableList)

	if newSearchableList.data
			and newSearchableList.item_builder
			and newSearchableList.searcher then
		newSearchableList:rebuild(newSearchableList.data)
	end

	return newSearchableList
end

function SearchableList:rebuild(data)
	for _, item in ipairs(self.items) do
		self.main_frame:removeObject(item)
	end

	self.items = {}

	for i, item_data in ipairs(data) do
		local item = self.item_builder(self.main_frame, i, item_data)
		if not item then
			error('Item builder function returned nil')
		end
		table.insert(self.items, item)
	end

	self.data = data

	self:refresh()
end

function SearchableList:refresh()
	if #self.items == 0 then
		return
	end

	self.matching_items = {}

	local _, item_height = self.items[1]:getSize()
	for i, item in ipairs(self.items) do
		if self.searcher(self.data[i], self.search_bar:getValue()) then
			table.insert(self.matching_items, i)
			item:setPosition(0, (#self.matching_items + 1) * item_height)
			item:show()
		else
			item:hide()
		end
	end
end

return SearchableList

