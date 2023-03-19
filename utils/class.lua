_M = {}

local _base_class
_base_class = {
	new = function(self, ...)
		local obj = setmetatable({}, self)
		obj:__init(...)
		return obj
	end,
	__init = function(self, ...)
	end,
}
_base_class.__index = _base_class

local function new_class(base)
	local new_cls = {}

	new_cls.__index = new_cls

	base = base or _base_class

	setmetatable(new_cls, base)
	new_cls.__super = base

	-- Inheriting '__call'.
	if base.__call then
		new_cls.__call = base.__call
	end

	return new_cls
end
_M.new_class = new_class

return _M
