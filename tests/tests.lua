local peripheral = require('/evo-logistics/tests/mocks/peripheral')
local logistics = require('/evo-logistics/tests/logistics')
local memoized = require('/evo-logistics/tests/memoized')
local dbg = require('/debugger')

local log = require('/evo-log').file('/log.log')

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
