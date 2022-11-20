local getOrder = require('utils').getOrder

local core = require('core')
local StorageCluster = core.StorageCluster
local BulkCluster = core.BulkCluster

local devIO = require('..remote_term.remote_term').relayIO

-- Global user options.
-- TODO: Make it autodect then remove this.
USE_BULK = true

-- TODO: Make UI/UX better, this includes:
	-- TODO: Implement GUI with sheets (downloaded from [https://github.com/Exerro/Sheets/releases], and wiki on [https://github.com/exerro/Sheets/wiki]) (also, ask on the subreddit if there's a better one available (perhaps ask aboout titanium))
	-- TODO: Some inputs error out when they should just present a message (like expecting numbers, and getting string)
	-- TODO: Add autocompletion and uparrow.
	-- TODO: Sort 'haul' by recency
	-- TODO: Make 'haul' search "substring fuzzy" (you'l probable have to implement this yourself).
	-- TODO: Add progress statuses (specially to expensive processing, such as catalogging (recounting))
	-- TODO: Add some info in the setup ("X inventories found" and "no inventories found, skipping cluster" or "no inventories found, please connect" for ones you cannot skip)
	-- TODO: Set relay to 'relaying to: computer_1, computer_3...' etc
	-- TODO: Add colors to output (and maybe to input, if that's even possible).
-- TODO: Implement way to register items to bulk storage (remember to move items to from normal to bulk).
-- TODO: Implement way to add inventories without having to re-setup everything.
-- TODO: Add crafting (with different categories).
-- TODO: Use git and github, and add installer (perhaps using [http://www.computercraft.info/forums2/index.php?/topic/17387-gitget-version-2-release/], or making a 'installer.lua' by hand and running with 'wget run').
-- TODO: Implement import and export clusters with an extra computer (you can make it opt-in as well as the bulk storage (by simply skipping it in the setup)).
-- TODO: Make soem cluster types opt-in (by simply skipping them in setup).
-- TODO: Make remote_term reliable for multiple users.


-----------------------------------------------
-- Storage functions

local mainStor = StorageCluster:new(mainStor, "main cluster")
local ioStor = StorageCluster:new(ioStor, "io cluster")
local selectStor = StorageCluster:new(selectStor, "selection cluster")
local bulkStor = BulkCluster:new(bulkStor, "bulk cluster")

local clusters = {ioStor, selectStor, bulkStor, mainStor}

local function rebuildSelectStor()
	if selectStor.invs == nil then
		return
	end

	-- Removing all items from the select storage.
	for itemName,itemStates in pairs(selectStor.itemStates) do
		if itemName ~= 'empty' and selectStor:itemExists(itemName) then
			mainStor:import(selectStor, itemStates.first)
		end
	end

	local bigger = function(a, b) return a > b end
	local i = 1

	-- Adding one of each item to the selection cluster.
	-- 'getOrder' and 'statesList' guarantees that they'll go from highest amount in storage to lowest.
	for _,itemName in pairs(getOrder(mainStor.itemCount, bigger)) do
		if itemName ~= 'empty' and mainStor:itemExists(itemName) then
			mainStor:move(mainStor:outputState(itemName), selectStor, selectStor.statesList[i], 1)
			i = i + 1

			-- Finishing early if the view storage is full.
			if not selectStor:itemExists('empty') then
				return
			end
		end
	end
end

local function storeAll()
	local notStored = {}

	local moved
	for itemName, itemStates in pairs(ioStor.itemStates) do
		if itemName ~= 'empty' then
			while itemStates.last do
				if bulkStor.invsItem[itemName] then
					moved = bulkStor:import(ioStor, itemStates.last)
				else
					moved = mainStor:import(ioStor, itemStates.last)
				end

				if moved == 0 then
					notStored[itemName] = true
					break
				end
			end
		end
	end

	for itemName,_ in pairs(notStored) do
		devIO:stdout_write("WARNING: '"..itemName.."' not stored (inventory full)")
	end

	return true
end
 
----------------------------------
-- Multithreading (Master) functions

rednet.open("back")

local master_handshake = {
	sender_type = 'master',
	message_type = 'handshake'
}

local slave_ids
local function handshake(slave_count)
	slave_ids = {}

	-- Sending handshake request.
	rednet.broadcast(master_handshake)

	for i=1,slave_count do
		repeat
			id, message = rednet.receive()
		until (type(message) == "table" and message.sender_type == "slave" and message.message_type == "handshake")

		slave_ids[i] = id
		devIO:stdout_write("Connected to slave "..i.."(id "..id..")\n")
	end
end

local function packAllMulti()
    slave_count = #slave_ids
    slaves_active = 0

    for itemName, _ in pairs(mainStor.itemCount) do
        if slaves_active < slave_count then
            rednet.send(slave_ids[slaves_active+1] ,{
                message_type = 'task',
                task = 'pack',
                args = {mainStor, itemName}
            })
            
            slaves_active = slaves_active + 1
        end

        if slaves_active == slave_count then
            repeat
                id, message = rednet.receive()
            until (contains(slave_ids, id) and message.message_type == "completed_task")

            rednet.send(id, {
                message_type = "confirm_task_completed"
            })
            
            rednet.send(id ,{
                message_type = 'task',
                task = 'pack',
                args = {mainStor, itemName}
            })
        end

        packItem(itemName)
    end

    while slaves_active > 0 do
        repeat
            id, message = rednet.receive()
        until (contains(slave_ids, id) and message.message_type == "completed_task")


        slaves_active = slaves_active - 1
    end
end

----------------------------------
-- Setup functions

-- TODO: Finds this automatically.
MODEM_POSITION = "bottom"

local function setupCluster(cluster, filter)
	cluster.invNames = peripheral.call(MODEM_POSITION, "getNamesRemote")

	local done_yet = false
	while not done_yet do
		done_yet = true

		for i,inv in ipairs(cluster.invNames) do

			-- Filtering out slave computers.
			if string.find(inv, "computer_") ~= nil then
					table.remove(cluster.invNames, i)
			end

			-- Filtering out inventories.
			for _,f_list in ipairs(filter) do
				for _,f in ipairs(f_list) do
					if inv == f then
						table.remove(cluster.invNames, i)
						done_yet = false
					end
				end
			end
		end
	end

	fs.delete("/logistics_data")
	fs.makeDir("/logistics_data")

	local file = fs.open("/logistics_data/"..cluster.name, "w")
	file.write(textutils.serialize(cluster))

	file.close()
end

----------------------------------
-- User IO functions

local function refresh()
    devIO:stdout_write("Refreshing clusters... ")

    for _,cluster in ipairs(clusters) do
			cluster:refresh()
		end

    devIO:stdout_write("Rebuilding selection table... ")
    rebuildSelectStor()
    devIO:stdout_write("Done.\n")
end

local function catalog()
    devIO:stdout_write("Catalogging clusters... ")

    for _,cluster in ipairs(clusters) do
			cluster:catalog()
		end

    devIO:stdout_write("Rebuilding selection table... ")
    rebuildSelectStor()
    devIO:stdout_write("Done.\n")
end

-- Detects a selection from the user.
local function getSelection()
	-- Creates a list with all item names (in order).
	local function getSelectItems()
		local selItems = {}

		for _,inv in ipairs(selectStor.invs) do
			local items = peripheral.call(inv, "list")

			-- Concatenate the two lists.
			for _,item in pairs(items) do
				selItems[#selItems+1] = item.name
			end
		end

		return selItems
	end

	local selItems = getSelectItems()
	local itemName
	
	-- Incessantly tries to find a missing item in the list.
	while true do
		local newSelItems = getSelectItems()

		for i=1,#newSelItems do
			-- If you find an item missing....
			if newSelItems[i] ~= selItems[i] then
				-- Wait for the user to put it back...
				while getSelectItems()[i] ~= selItems[i] do
					-- Wait...
				end
				-- Then return.
				return selItems[i]
			end
		end
	end

end

local function haulItems(n)
	local itemNames = {}
	local amounts = {}

	devIO:stdout_write("Waiting for item selection...\n")
	local itemName = nil
	itemName = getSelection()
	
	devIO:stdout_write(mainStor.itemCount[itemName]+1 .. " " .. itemName .. " found.\n")
	devIO:stdout_write("Type the amount to haul:\n")
	local choice = devIO:stdin_read()

	local amount
	if choice == 'all' then
		amount = mainStor.itemCount[itemName]+1
	else
		amount = tonumber(choice)
	end

	if (mainStor.itemCount[itemName] == nil) or (mainStor.itemCount[itemName]+1 < amount) then
			devIO:stdout_write("Not enough items!\n")
			return
	end

	if amount == mainStor.itemCount[itemName]+1 then
		amount = amount - selectStor:transfer(itemName, ioStor, 1)
	end

	if amount > 0 then
		mainStor:transfer(itemName, ioStor, amount)
	end

	devIO:stdout_write("Done.\n")
end

local function haulByText()
	devIO:stdout_write("Type the name of an item in storage:\n")
	local choice = devIO:stdin_read()
	local matches = {}
	local matchCluster = {}
	local itemName
	local cluster
	local amount

	local cmp = function(a,b)
		-- `nil` is interpreted as infinity for de purposes of ordering.
		if a == nil then
			return true
		elseif b == nil then
			return false
		else
			return a > b
		end
	end

	for _,itemName in ipairs(getOrder(bulkStor.itemCount, cmp)) do
		if itemName:find(choice, 1, true) then
			matchCluster[#matchCluster+1] = bulkStor
			matches[#matches+1] = itemName
		end
	end

	for _,itemName in ipairs(getOrder(mainStor.itemCount, cmp)) do
		if itemName:find(choice, 1, true) then
			matchCluster[#matchCluster+1] = mainStor
			matches[#matches+1] = itemName
		end
	end

	if #matches > 10 then
		devIO:stdout_write("There are more than 10 matches! (try being more specific)\n")
		return
	elseif #matches == 0 then
		devIO:stdout_write("No items match this search!\n")
		return
	elseif #matches == 1 then
		itemName = matches[1]
		cluster = matchCluster[1]
	else
		for i,candidate in ipairs(matches) do
			devIO:stdout_write(i..". "..candidate.."\n")
		end

		devIO:stdout_write("Select one of the above:\n")
		choice = tonumber(devIO:stdin_read())
		
		if choice > 0 and choice <= #matches then
			itemName = matches[choice]
			cluster = matchCluster[choice]
		else
			devIO:stdout_write("Invalid choice.\n")
			return
		end
	end

	-- TODO: 'getItemDetail' has a "displayName" attribute, which would make display and search cleaner. Implement it (it'll probably require adding these names to the cluster as a list and whatnot (good idea to make it a table indexed by the normal name)).
	devIO:stdout_write(cluster.itemCount[itemName] .. " " .. itemName .. " found.\n")
	devIO:stdout_write("Type the amount to haul:\n")
	local choice = devIO:stdin_read()

	if choice == 'all' then
		amount = cluster.itemCount[itemName]
	else
		amount = tonumber(choice)
	end

	if amount == nil then
		devIO:stdout_write("Invalid amount.\n")
		return
	end

	amount = math.floor(amount)

	--if cluster.itemCount[itemName] < amount then
	--    devIO:stdout_write("Not enough items!\n")
	--    return
	--end

	if amount > 0 then
		local moved = cluster:transfer(itemName, ioStor, amount)
		if moved < amount then
			devIO:stdout_write("WARNING: Haul not fully completed ("..moved.."/"..amount..")\n")
		end
	end

	devIO:stdout_write("Done.\n")
end

local function showMainScreen()
	devIO:clear()
	devIO:setCursorPos(1,1)
	devIO:stdout_write("Storage Logistics\n")
end

local function printHelp()
	devIO:stdout_write("- haul : Haul items from the main storage\n")
	devIO:stdout_write("- store : Stores all items in the IO container\n")
	devIO:stdout_write("- sort : Sorts the main storage (most operations run faster in a sorted storage)\n")
	devIO:stdout_write("- pack : Condenses spread out items, making them take less space\n")
	devIO:stdout_write("- refresh : Refreshes the item database and the selection table (use if you've manually handled inventory in the main storage)\n")
	devIO:stdout_write("- clear : Clears the screen\n")
	devIO:stdout_write("- help : Displays the help page\n")
	devIO:stdout_write("- exit : Closes Storage Logistics\n")
end

---------------------------------------------
-- Main

args = ...

if args == "-s" then
	clusters_done = {}
	for _,cluster in pairs(clusters) do
		devIO:stdout_write("Connect the "..cluster.name.." and press enter to continue.\n")
		devIO:stdout_write("> ")
		local command = io.stdin:read()
		setupCluster(cluster, clusters_done)
		table.insert(clusters_done, cluster.invNames)
	end
	catalog()
else
	for _,cluster in pairs(clusters) do
		if not cluster:load("/logistics_data/"..cluster.name) then
			error("no configurations found. try running 'logistics -s'")
		end
	end
end


devIO:clear()
devIO:setCursorPos(1,1)
handshake(0)
refresh()
showMainScreen()

while true do
	for _,cluster in pairs(clusters) do
		cluster:save("/logistics_data/"..cluster.name)
	end

	devIO:stdout_write("> ")
	local command = devIO:stdin_read()
	
	-- TODO: Make this optional.
	if command == "pick" then
		haulItems()
	elseif command == "haul" then
		haulByText()
	elseif command == "relay" then
		devIO:handshake(1)
		showMainScreen()
	elseif command == "store" then
		storeAll()
	elseif command == "refresh" then
		refresh()
	elseif command == "catalog" then
		catalog()
	elseif command == "clear" then
		showMainScreen()
	elseif command == "sort" then
		devIO:stdout_write("Sorting... ")
		mainStor:sort()
		devIO:stdout_write("Done.\n")
	elseif command == "pack" then
		devIO:stdout_write("Packing... ")
		mainStor:pack()
		devIO:stdout_write("Done.\n")
	elseif command == "help" then
		printHelp()
	elseif command == "debug" then
		devIO:stdout_write(mainStor.firstItemState["minecraft:coal"].slot.."\n")
		devIO:stdout_write(mainStor.lastItemState["minecraft:coal"].slot.."\n")
		devIO:stdout_write(mainStor.itemCount["minecraft:coal"].."\n")
	elseif command == "exit" then
		term.setCursorPos(1,1)
		term.clear()
		break
	else
		devIO:stdout_write("Command not recognized\n")
	end
end








