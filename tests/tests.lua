local peripheral = require('/logos-library.tests.mocks.peripheral')
local logistics = require('/logos-library.tests.logistics')
local memoized = require('/logos-library.tests.memoized')
local dbg = require('/debugger')

local log = require('/logos-library.utils.log').file('/log.log')

local function test_all()
	print('Testing mock: memoized')
	memoized.test_module()
	print('Testing mock: peripheral')
	peripheral.test_module()
	print('Testing mock: logistics')
	logistics.test_module()
end

local status, error_msg = dbg.call(test_all, function(error_msg)
	log.info(error_msg)
	log.info(debug.traceback())
	print(error_msg)
end)
