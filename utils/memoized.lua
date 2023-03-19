local new_class = require('/logos-library.utils.class').new_class
local utils = require('/logos-library.utils.utils')

local Memoized = new_class()

function Memoized:new(args)
	if not args then error('args is required')
	elseif not args.name then error('args.name is required')
	elseif not args.fn then error('args.fn is required')
	end

	args.auto_save = args.auto_save or false

	local new_memoized = {
		name = args.name,
		fn = args.fn,
		auto_save = args.auto_save,
		path = '/logos-library/data/memoized/' .. args.name .. '.cache',
		cache = {},
	}

	setmetatable(new_memoized, Memoized)

	if args.auto_save then
		new_memoized:load()
	end

	return new_memoized
end

function Memoized:save()
	local data = textutils.serialize(self.cache)

	local file = fs.open(self.path, 'w')
	file.write(data)
	file.close()
end

function Memoized:load()
	if not fs.exists(self.path) then return end

	local file = fs.open(self.path, 'r')
	local data = file.readAll()
	file.close()

	self.cache = textutils.unserialize(data)
end

-- The cache has the following structure:
-- cache[n_args][arg1][arg2][arg3]...[argn] = result
local function _store_in_cache(cache, inputs, result)
	if not inputs then
		cache[0] = result
		return
	end

	cache[#inputs] = cache[#inputs] or {}

	local current_cache = cache[#inputs]

	for i,input in ipairs(inputs) do
		if not current_cache[input] then
			current_cache[input] = {}
		end

		if i ~= #inputs then
			current_cache = current_cache[input]
		else
			current_cache[input] = result
			break
		end
	end
end

local function _find_in_cache(cache, inputs)
	if not inputs then
		return cache[0]
	end

	local current_cache = cache[#inputs]

	if not current_cache then return nil end

	for i,input in ipairs(inputs) do
		if not current_cache[input] then
			return nil
		end

		current_cache = current_cache[input]
	end

	return current_cache
end

function Memoized:__call(...)
	local inputs = {...}

	local cached = _find_in_cache(self.cache, inputs)

	if cached then
		return table.unpack(cached)
	end

	local result = {self.fn(...)}

	_store_in_cache(self.cache, inputs, result)

	if self.auto_save then
		self:save()
	end

	return table.unpack(result)
end

return {
	Memoized = Memoized,
}
