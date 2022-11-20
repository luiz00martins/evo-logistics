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

local function array_contains(arr, val)
    for i, v in ipairs(arr) do
        if v == val then
            return true
        end
    end

    return false
end


local function table_contains(tab, val)
    for i, v in pairs(tab) do
        if v == val then
            return true
        end
    end

    return false
end

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

local function array_filter(tab, filter)
	local filtered = {}
	for _,v in ipairs(tab) do
		if filter(v) then
			filtered[#filtered+1] = v
		end
	end
	return filtered
end

local function table_filter(tab, filter)
	local filtered = {}
	for k,v in pairs(tab) do
		if filter(v) then
			filtered[k] = v
		end
	end
	return filtered
end

local function array_reduce(list, fn, init)
	local acc = init or next(list)
	for _, v in ipairs(list) do
		acc = fn(acc, v)
	end
	return acc
end

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

local function array_map(array, fn)
	local new_array = {}
	for i, v in ipairs(array) do
		new_array[i] = fn(v)
	end
	return new_array
end

local function table_map(table, fn)
	local new_table = {}
	for k, v in pairs(table) do
		new_table[k] = fn(v)
	end
	return new_table
end

local function reversedipairsiter(t, i)
    i = i - 1
    if i ~= 0 then
        return i, t[i]
    end
end
function reversed_ipairs(t)
    return reversedipairsiter, t, #t + 1
end

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

local function get_modem_side(is_wireless)
	if is_wireless == nil then
		error('wirelessness should be specified')
	end

	for _, side in pairs(rs.getSides()) do
		if peripheral.isPresent(side)
				and peripheral.getType(side) == "modem"
				and (is_wireless == nil or peripheral.call(side, "isWireless") == is_wireless) then 
			return side 
		end
	end

	return nil
end

local function rednet_open(is_wireless)
	local modem_side = get_modem_side(is_wireless)

	if not modem_side then
		return false
	else
		rednet.open(modem_side)
		return true
	end
end

local function get_connected_inventories()
	-- FIXME: you should probalbly... uh... y'know... actually filter these out.
	local blacklist = {'computer'}

	return peripheral.call(get_modem_side(false), "getNamesRemote")
end

local function inventory_type(inv_name)
	local stripped = string_split(inv_name, '_')
	stripped[#stripped] = nil
	return table.concat(stripped, '_')
end

local function shorten_item_names(item_names)
	local shortened_item_names = {}
	-- Tracks shortened item names for clashing.
	local tracker = {}

	for i,item_name in ipairs(item_names) do
		local shortened = string_split(item_name, ':')[2]

		if not tracker[shortened] then
			tracker[shortened] = i
			shortened_item_names[i] = shortened
		else
			-- A clash happened. Set both of them to their original names.
			local other_i = tracker[shortened]
			local other_item_name = item_names[other_i]

			shortened_item_names[i] = item_name
			shortened_item_names[other_i] = other_item_name
		end
	end

	return shortened_item_names
end

local function new_class(base)
	local new_cls = {}

	new_cls.__index = new_cls

	if base then
		setmetatable(new_cls, base)
	end

	return new_cls
end

-- Returning functions.
return {
	table_deepcopy = table_deepcopy,
	table_shallowcopy = table_shallowcopy,
	array_contains = array_contains,
	table_contains = table_contains,
	array_unique = array_unique,
	array_filter = array_filter,
	table_filter = table_filter,
	array_reduce = array_reduce,
	table_reduce = table_reduce,
	array_map = array_map,
	table_map = table_map,
	get_order = get_order,
	string_split = string_split,
	reversed_ipairs = reversed_ipairs,
	get_modem_side = get_modem_side,
	rednet_open = rednet_open,
	get_connected_inventories = get_connected_inventories,
	inventory_type = inventory_type,
	shorten_item_names = shorten_item_names,
	new_class = new_class,
	log = log,
	serialize = serialize,
	deserialize = deserialize,
}

