local dl_list = require('/logos-library.utils.dl_list')

local queue = {
	scheduled = dl_list(),
	executing = dl_list(),
}

function queue:add(task)
	self.scheduled:push(task)
end

function queue:is_empty()
	return self.scheduled:is_empty() and self.executing:is_empty()
end

function queue:execute_next()
	local task = self.scheduled:shift()
	self.executing:push(task)

	task.fn()
	self.executing:shift()
end

return queue
