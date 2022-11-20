local nodeIO = require('..remote_term.remote_term').nodeIO:new()

nodeIO:connect()

while nodeIO:isConnected() do
	nodeIO:executeNext()
end
