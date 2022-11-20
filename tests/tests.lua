local utils = require('/logos.utils')
local peripheral = require('/logos.tests.mocks.peripheral')
local logistics = require('logistics')

local function test_all()
	peripheral.test_module()
	logistics.test_module()
end

xpcall(test_all, function(error_msg)
	utils.log(error_msg)
	utils.log(debug.traceback())
end)

