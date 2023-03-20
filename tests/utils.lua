local utils = require('/logos-library.utils.utils')

local test_title = ''
local test_count = 0
local function print_test_status()
	local w, h = term.getSize()
	local x, y = term.getCursorPos()

	term.setCursorPos(1, y)
	io.stdout:write(string.rep(' ', w))
	term.setCursorPos(1, y)
	--io.stdout:write(tostring(test_title..': ')..string.rep('>', test_count))
	io.stdout:write(tostring(test_title..': ')..tostring(test_count))
end

local function set_title(title)
	test_title = title
end

local function finish()
	local w, _ = term.getSize()
	local _, y = term.getCursorPos()

	term.setCursorPos(1, y)
	io.stdout:write(string.rep(' ', w))
	term.setCursorPos(1, y)
	print('Testing successful ('..tostring(test_count)..' tests)')
	test_count = 0
end

local function _bad_equals_path(v1, v2)
	io.stdout:write('\n')
	local msg = "Assertion failed: Got '"..utils.tostring(v1).."', expected '"..utils.tostring(v2).."'"
	print(msg)
	utils.log(msg)
	utils.log(debug.traceback())
	error()
end

local function assert_equals(value, expected)
	if value == expected then
		test_count = test_count + 1
		print_test_status()
	else
		_bad_equals_path(value, expected)
	end
end

local function assert_equals_table(t1, t2)
	if utils.table_compare_by_value(t1, t2) then
		test_count = test_count + 1
		print_test_status()
	else
		_bad_equals_path(t1, t2)
	end
end

local function custom_assert(value)
	if value then
		test_count = test_count + 1
		print_test_status()
	else
		io.stdout:write('\n')
		print('Assertion failed')
		utils.log(debug.traceback())
		error()
	end
end

return {
	custom_assert = custom_assert,
	assert_equals = assert_equals,
	assert_equals_table = assert_equals_table,
	set_title = set_title,
	finish = finish,
}
