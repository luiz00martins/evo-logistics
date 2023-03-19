local test_utils = require('/logos-library.tests.utils')
local utils = require('/logos-library.utils.utils')

local Memoized = require('/logos-library.utils.memoized').Memoized
local custom_assert = test_utils.custom_assert
local assert_equals_table = test_utils.assert_equals_table
local assert_equals = test_utils.assert_equals

local function test_module()
	print('Testing module: memoized')

	test_utils.set_title('Testing return')
	local fn1 = Memoized:new {
		name = 'fn1',
		fn = function(v)
			return 'test'..v
		end,
	}

	assert_equals(fn1(''), 'test')
	assert_equals(fn1(' abc'), 'test abc')

	test_utils.set_title('Testing autosave')
	local path = '/logos-library/data/memoized/test_autosave.cache'
	local test_autosave = Memoized:new {
		name = 'test_autosave',
		auto_save = true,
		path = path,
		fn = function(v)
			return 'test'..v
		end,
	}

	assert_equals(test_autosave(''), 'test')
	assert_equals(test_autosave(' abc'), 'test abc')
	assert_equals(test_autosave(' 123'), 'test 123')
	local old_cache = test_autosave.cache
	local file = fs.open(path, 'r')
	local data = file.readAll()
	file.close()
	fs.delete(path)
	local new_cache = textutils.unserialize(data)
	assert_equals_table(old_cache, new_cache)

	test_utils.finish()
end

return {
	test_module = test_module,
}
