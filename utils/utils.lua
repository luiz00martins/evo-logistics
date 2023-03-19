local _M = {}

local function serializeInt(i)
        local s = ""
        repeat
                s = s .. string.char((i % 128) + ((i >= 128) and 128 or 0))
                i = math.floor(i / 128)
        until i == 0
        return s
end
-- returns int, next position
local function deserializeInt(s,pos)
        local k = pos
        local i = 0
        local m = 1
        while true do
                local b = string.byte(s:sub(k,k))
                i = i + m * (b % 128)
                m = m * 128
                k = k + 1
                if b < 128 then break end
        end
        return i, k
end

local nextid_key = {}
local function serializeInternal(obj, seen)
        if obj ~= nil and seen[obj] then
                return "06" .. serializeInt(seen[obj])
        end
        if type(obj) == "table" then
                local id = seen[nextid_key]
                seen[nextid_key] = id + 1
                seen[obj] = id

                local s = "05"
                local ikeys = {}
                for k,v in ipairs(obj) do
                        ikeys[k] = v
                        s = s .. serializeInternal(v, seen)
                end
                s = s .. serializeInternal(nil, seen)
                for k,v in pairs(obj) do
                        if ikeys[k] == nil then
                                s = s .. serializeInternal(k, seen) .. serializeInternal(v, seen)
                        end
                end
                s = s .. serializeInternal(nil, seen)
                return s
        elseif type(obj) == "number" then
                local ns = tostring(obj)
                return "04" .. serializeInt(ns:len()) .. ns
        elseif type(obj) == "string" then
                return "03" .. serializeInt(obj:len()) .. obj
        elseif type(obj) == "boolean" then
                if obj then
                        return "01"
                else
                        return "02"
                end
        elseif type(obj) == "nil" then
                return "00"
        elseif type(obj) == "userdata" then
                error("cannot serialize userdata")
        elseif type(obj) == "thread" then
                error("cannot serialize threads")
        elseif type(obj) == "function" then
                error("cannot serialize functions")
        else
                error("unknown type: " .. type(obj))
        end
end
local function serialize(obj)
        return serializeInternal(obj, {[nextid_key] = 0})
end
local function deserialize(s)
        local pos = 1
        local seen = {}
        local nextid = 0
        local function internal()
                local tch = s:sub(pos,pos)
                local len
                pos = pos + 2
                if tch == "00" then
                        return nil
                elseif tch == "01" then
                        return true
                elseif tch == "02" then
                        return false
                elseif tch == "03" then
                        len, pos = deserializeInt(s, pos)
                        local rv = s:sub(pos, pos+len-1)
                        pos = pos + len
                        return rv
                elseif tch == "04" then
                        len, pos = deserializeInt(s, pos)
                        local rv = s:sub(pos, pos+len-1)
                        pos = pos + len
                        return tonumber(rv)
                elseif tch == "05" then
                        local id = nextid
                        nextid = id + 1
                        local t = {}
                        seen[id] = t

                        local k = 1
                        while true do
                                local v = internal()
                                if v == nil then break end
                                t[k] = v
                                k = k + 1
                        end

                        while true do
                                local k = internal()
                                if k == nil then break end
                                local v = internal()
                                if v == nil then break end
                                t[k] = v
                        end
                        return t
                elseif tch == "06" then
                        local id
                        id, pos = deserializeInt(s, pos)
                        return seen[id]
                else
                        return nil
                end
        end
        return internal()
end

local function log(vals, nvals, sep, endchar)
	endchar = endchar or '\n'

	local text
	if vals == nil then
		text = 'nil'
	elseif type(vals) == 'table' then
		nvals = nvals or #vals
		for i=1,nvals do
			if vals[i] == nil then
				vals[i] = 'nil'
			else
				vals[i] = tostring(vals[i])
			end
		end

		sep = sep or ' '
		text = table.concat(vals, sep)
	else
		text = tostring(vals)
	end

	local path = '/log.log'
	local file = fs.open(path, "a")
	file.write(text..endchar)
	file.flush()
	file.close()
end
_M.log = log

-- Retuns the order (i.e. list of keys) of the given table based on a comparison function of its values.
local function get_order(tab, cmp)
	local tableCmp = function(a,b)
			return cmp(a[2], b[2])
		end

	local order = {}
	local i = 1
	
	-- Storing data
	for k,v in pairs(tab) do
		order[i] = {k,v}
		i = i + 1
	end
	
	-- Sorting
	table.sort(order, tableCmp)
	
	-- Removing values from order, leaving only the labels.
	i = 1
	for i,v in ipairs(order) do
		order[i] = order[i][1]
	end
	
	return order
end
_M.get_order = get_order

local function table_compare_by_value(t1, t2, memo, visited)
	if type(t1) ~= type(t2) then
		return false
	elseif type(t1) ~= "table" then
		return t1 == t2
	else
		-- We do some memoization to avoid repeating work on the second loop.
		memo = memo or {}
		-- We need to keep track of visited tables to avoid infinite loops.
		visited = visited or {}

		if visited[t1] or visited[t2] then
			return true
		end

		visited[t1] = true
		visited[t2] = true

		for k, v in pairs(t1) do
			if not table_compare_by_value(v, t2[k], memo, visited) then
				return false
			end
			memo[k] = true
		end
		for k, v in pairs(t2) do
			if not memo[k] and not table_compare_by_value(v, t1[k], memo, visited) then
				return false
			end
		end
		return true
	end
end
_M.table_compare_by_value = table_compare_by_value

local function table_shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
_M.table_shallowcopy = table_shallowcopy

local function table_deepcopy(orig, copies)
    copies = copies or {}
    local copy
    if type(orig) == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[table_deepcopy(orig_key, copies)] = table_deepcopy(orig_value, copies)
            end
            setmetatable(copy, table_deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
_M.table_deepcopy = table_deepcopy

local function table_keys(t)
		local keys = {}
		for k, _ in pairs(t) do
				table.insert(keys, k)
		end

		return keys
end
_M.table_keys = table_keys

local function table_values(t)
		local values = {}
		for _, v in pairs(t) do
				table.insert(values, v)
		end

		return values
end
_M.table_values = table_values

local function array_contains(arr, val)
    for i, v in ipairs(arr) do
        if v == val then
            return true
        end
    end

    return false
end
_M.array_contains = array_contains


local function _format_key(k)
	if type(k) == 'number' or type(k) == 'boolean' then
		k = string.format("[%s]", k)
	elseif type(k) == 'string' then
		-- TODO: Create a check for disallowed characters, making this unnecessary for valid strings.
		k = string.format('["%s"]', k)
	end

	return k
end

local function _format_value(v)
	if type(v) == 'string' then
		v = string.format('"%s"', v)
	else
		v = tostring(v)
	end

	return v
end

local function table_serialize (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
		--table.insert(sb, string.rep (" ", indent))
    table.insert(sb, "{\n")
    for key, value in pairs (tt) do
      if type (value) == "table" and not done [value] then
        done [value] = true
				table.insert(sb, string.rep (" ", indent+2))
				table.insert(sb, _format_key(key) .. ' = ')
        table.insert(sb, table_serialize (value, indent + 2, done))
			else
				table.insert(sb, string.rep (" ", indent + 2)) -- indent it
				table.insert(sb, string.format("%s = %s,\n", _format_key(key), _format_value(value)))
			end
    end
		table.insert(sb, string.rep (" ", indent)) -- indent it
    table.insert(sb, "},\n")
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

local function to_string( tbl )
    if nil == tbl then
        return 'nil'
    elseif "table" == type( tbl ) then
        return table_serialize(tbl)
    elseif "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end
_M.tostring = to_string

local function table_contains(tab, val)
    for i, v in pairs(tab) do
        if v == val then
            return true
        end
    end

    return false
end
_M.table_contains = table_contains

local function array_unique(arr)
	local unique = {}
	local keys = {}

	for _,v in ipairs(arr) do
		if not keys[v] then
			keys[v] = true
			unique[#unique+1] = v
		end
	end

	return unique
end
_M.array_unique = array_unique

local function table_partition(tab, pred)
	local partitioned = {}

	for _,v in pairs(tab) do
		local result = pred(v)

		if result then
			partitioned[result] = partitioned[result] or {}
			table.insert(partitioned[result], v)
		end
	end

	return partitioned
end
_M.table_partition = table_partition

local function array_partition(tab, pred)
	local partitioned = {}

	for _,v in pairs(table_partition(tab, pred)) do
		table.insert(partitioned, v)
	end

	return partitioned
end
_M.array_partition = array_partition

local function array_filter(tab, filter)
	local filtered = {}
	for _,v in ipairs(tab) do
		if filter(v) then
			filtered[#filtered+1] = v
		end
	end
	return filtered
end
_M.array_filter = array_filter

local function table_filter(tab, filter)
	local filtered = {}
	for k,v in pairs(tab) do
		if filter(v) then
			filtered[k] = v
		end
	end
	return filtered
end
_M.table_filter = table_filter

local function array_reduce(list, fn, init)
	local acc = init or next(list)
	for _, v in ipairs(list) do
		acc = fn(acc, v)
	end
	return acc
end
_M.array_reduce = array_reduce

local function table_reduce(list, fn, init)
	local acc
	if init then
		acc = init
	else
		_, acc = next(list)
	end

	for _, v in pairs(list) do
		acc = fn(acc, v)
	end
	return acc
end
_M.table_reduce = table_reduce

local function array_map(array, fn)
	local new_array = {}
	for i, v in ipairs(array) do
		new_array[i] = fn(v)
	end
	return new_array
end
_M.array_map = array_map

local function table_map(table, fn)
	local new_table = {}
	for k, v in pairs(table) do
		new_table[k] = fn(v)
	end
	return new_table
end
_M.table_map = table_map

local function reversedipairsiter(t, i)
    i = i - 1
    if i ~= 0 then
        return i, t[i]
    end
end

local function reversed_ipairs(t)
    return reversedipairsiter, t, #t + 1
end
_M.reversed_ipairs = reversed_ipairs

local function string_split(inputstr, sep)
	if sep == nil then
					sep = ' '
	end

	local t = {}

	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		t[#t+1] = str
	end

	return t
end
_M.string_split = string_split

local function log_error(fn)
	local status, err, ret = xpcall(fn, debug.traceback)

	if not status then
		local path = '/error.log'
		local file = fs.open(path, "w")
		file.write(err)
		file.close()

		error('backtrace saved to '..path)
	end

	return ret
end
_M.log_error = log_error

-- Returning functions.
return _M
