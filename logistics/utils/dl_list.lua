-- Implementation for a doubly linked list.

----------------------------
-- Double linked list.
local dl_list = {}
dl_list.__index = dl_list

setmetatable(dl_list, { __call = function(_, ...)
  local t = setmetatable({ length = 0 }, dl_list)
  for _, v in ipairs{...} do t:push(v) end
  return t
end })

function dl_list:push(t)
  if self.last then
    self.last._next = t
    t._prev = self.last
    self.last = t
  else
    -- this is the first node
    self.first = t
    self.last = t
  end

  self.length = self.length + 1
end

function dl_list:unshift(t)
  if self.first then
    self.first._prev = t
    t._next = self.first
    self.first = t
  else
    self.first = t
    self.last = t
  end

  self.length = self.length + 1
end

function dl_list:insert(t, after)
  if after then
    if after._next then
      after._next._prev = t
      t._next = after._next
    else
      self.last = t
    end

    t._prev = after
    after._next = t
    self.length = self.length + 1
  elseif not self.first then
    -- this is the first node
    self.first = t
    self.last = t
  end
end

function dl_list:pop()
  if not self.last then return end
  local ret = self.last

  if ret._prev then
    ret._prev._next = nil
    self.last = ret._prev
    ret._prev = nil
  else
    -- this was the only node
    self.first = nil
    self.last = nil
  end

  self.length = self.length - 1
  return ret
end

function dl_list:shift()
  if not self.first then return end
  local ret = self.first

  if ret._next then
    ret._next._prev = nil
    self.first = ret._next
    ret._next = nil
  else
    self.first = nil
    self.last = nil
  end

  self.length = self.length - 1
  return ret
end

function dl_list:remove(t)
  if t._next then
    if t._prev then
      t._next._prev = t._prev
      t._prev._next = t._next
    else
      -- this was the first node
      t._next._prev = nil
      self.first = t._next
    end
  elseif t._prev then
    -- this was the last node
    t._prev._next = nil
    self.last = t._prev
  else
    -- this was the only node
    self.first = nil
    self.last = nil
  end

  t._next = nil
  t._prev = nil
  self.length = self.length - 1
end

function dl_list:is_empty()
	return self.first == nil
end

local function iterate(self, current)
  if not current then
    current = self.first
  elseif current then
    current = current._next
  end

  return current
end

-- TODO: Implement this as '__pairs' and/or '__ipairs'.
function dl_list:iterate()
  return iterate, self, nil
end

return dl_list
