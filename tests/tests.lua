local utils = require('/logos-library.utils.utils')
local peripheral = require('/logos-library.tests.mocks.peripheral')
local logistics = require('logistics')
local memoized = require('memoized')
local dbg = require('/debugger')

local function test_all()
	memoized.test_module()
	peripheral.test_module()
	logistics.test_module()
end

local status, error_msg = dbg.call(test_all, function(error_msg)
	utils.log(error_msg)
	utils.log(debug.traceback())
	print(error_msg)
end)

if not status then
	print('Test failed. See logs for details.')
end
