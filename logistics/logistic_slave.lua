local VERSION = "0.0.3"
-- 0.0.1: Catalog, haul and store systems.
-- 0.0.2: Much more scalable haul and store.
-- 0.0.3: Capability to sort the storage, which
-- improves hauling and storing efficiency.

-- Storages.
local mainStor = {
    -- The list of containers (strings) connected to that storage.
    invs = {},
    -- The size (integer) of each of those inventories.
    invSizes = {},
    -- itemCount[<item>] is the amount (integer) of <item> (string) in storage.
    itemCount = {},
    -- firstItemState[<item>] is the state of the first of <item> (string) 
firstItemState = {},
    -- lastItemState[<item>] is the state of the last of <item> (string)
    lastItemState = {}
}
local ioStor = {
    invs = {
        "minecraft:barrel_4",
        "minecraft:barrel_5",
    },
    invSizes = {}
}
local selectStor = {
    invs = {
        "minecraft:barrel_6",
        "minecraft:barrel_7",
    },
    invSizes = {}
}

------------------------------------
-- Data structures management

-- Retuns the order (i.e. an ordered list of keys) of the given table.
local function getOrder(tab, cmp)
    cmp = cmp 
        or function(a,b) 
            return a < b 
        end
        
    tableCmp = function(a,b)
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
    
    -- Removing values from order, leaving only
    -- the labels.
    i = 1
    for i,v in ipairs(order) do
        order[i] = order[i][1]
        --print(v[1]," ",v[2])
    end
    
    return order
end

local function deepcopy(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
  
    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do res[deepcopy(k, s)] = deepcopy(v, s) end
    return setmetatable(res, getmetatable(obj))
end

local function contains(tab, val)
    for i, v in ipairs(tab) do
        if v == val then
            return true
        end
    end

    return false
end

-- Gets the SL name of an item 
-- ("empty" if none provided).
local function getItemName(item)
    if item == nil then 
        return "empty"
    else
        return item.name
    end
end

-- `State` methods.
State = {}
State.__index = State
function State:new (o)
  o = o or {}   -- create object if user does not provide one
  setmetatable(o, self)
  self.__index = self
  return o
end

function State:isBefore(other)
    return (self.invPos < other.invPos or (self.invPos == other.invPos and self.slot < other.slot))
end

function State:isAfter(other)
    return (self.invPos > other.invPos or (self.invPos == other.invPos and self.slot > other.slot))
end

function State:isAt(other)
    return (self.invPos == other.invPos and self.slot == other.slot)
end

-- Storage Cluster methods.
-- TODO: Refine this concept.

StorageCluster = {}
StorageCluster.__index = StorageCluster
function StorageCluster:new (o)
    o = o or {
            invs = {}, -- The list of containers (strings) connected to that storage.
            invSizes = {}, -- The size (integer) of each of those inventories.
            itemCount = {}, -- itemCount[<item>] is the amount (integer) of <item> (string) in storage.
            firstItemState = {}, -- firstItemState[<item>] is the state of the first of <item> (string) 
            lastItemState = {} -- lastItemState[<item>] is the state of the last of <item> (string)
        }

    setmetatable(o, self)
    self.__index = self
    return o
end

mainStor = StorageCluster:new(mainStor)
ioStor = StorageCluster:new(ioStor)
selectStor = StorageCluster:new(selectStor)

-- Iterator for storage. Returns the next slot after `state`. Returns the first slot it the `state == nil`.
-- Each state has a form {.invPos, .inv, .slot, .items, .size}
function StorageCluster:next(state)
    -- Starting up first state.
    if state == nil then
        state = {}
        
        state.invPos = 1
        state.inv = self.invs[state.invPos]
        state.items = peripheral.call(state.inv, "list")
        state.size = self.invSizes[state.invPos]
        state.slot = 0
        
        State:new(state)
    end

    state.slot = state.slot + 1
    
    -- If reached the end of container, load next state.
    if state.slot > state.size then
        state.invPos, state.inv = next(self.invs, state.invPos)
        
        -- Detecting when reached the end of all containers.
        if state.invPos == nil then
            return nil
        end
        
        state.items = peripheral.call(state.inv, "list")
        state.slot = 1
    end
    
    return state, state.items[state.slot]
end

-- Backwards iterator for storage.
function StorageCluster:prev(state)
    -- Starting up last state.
    if state == nil then
        state = {}
        
        state.invPos = table.getn(self.invs)
        state.inv = self.invs[state.invPos]
        state.size = self.invSizes[state.invPos]
        state.items = peripheral.call(state.inv, "list")
        state.slot = state.size + 1
    end
    
    state.slot = state.slot - 1
    
    -- If reached the start of container,
    --     load previous state.
    if state.slot < 1 then
        state.invPos = state.invPos - 1
        
        -- Detecting when it reached the start
        --     of all containers.
        if state.invPos < 1 then return nil end

        state.inv = self.invs[state.invPos]
        state.size = self.invSizes[state.invPos]
        state.items = peripheral.call(state.inv, "list")
        state.slot = state.size
    end
    
    return state, state.items[state.slot]
end

function StorageCluster:nextItem(state, itemName)
    -- Initial setup --

    -- NOTE: This "item of interest" only comes into 
    -- play when the "next item" isn`t already 
    -- determined in the state.
    local prepItem
    if state == nil then
        -- When you don`t already have an item
        -- to search, the item of interest is in 
        -- the first state in the nil case, so it
        -- needs to be found after the "next".
        state = self:next(state)
        prepItem = state.items[state.slot]
    else
        -- Otherwise, the item of interest is in
        -- the current state, and needs to be found
        -- before calling for the "next".
        
        prepItem = state.items[state.slot]
        local name = itemName 
            or state.nextName 
            or getItemName(prepItem)
        
        if self.lastItemState ~= nil then
            -- If there`s a last item list, use it
            -- to finish early.
        
            local lastState = self.lastItemState[name]
            if lastState ~= nil
                    and lastState.inv == state.inv
                    and lastState.slot == state.slot then
                -- If it reached the last item, halt.
                return nil
            end
        end
        
        state = self:next(state)
    end

    -- If the next is nil, the storage ended.    
    if state == nil then return nil end

    if state.nextName == nil then
        -- If the "next item" is not already
        -- determined in the state, decide it
        -- with the item of interest.
        state.nextName = getItemName(prepItem)
    end
    
    if itemName ~= nil then
        -- Note: The provided "item name" is more
        -- relevant than the state "next item", so
        -- it overwrites.
        state.nextName = itemName
    end
    
    -- Finding next "item". --
    
    -- Going though the items.
    -- Note: The cases for "empty" and an actual
    -- item are separated for efficiency (this may be completely unnecessary).
    if state.nextName == "empty" then
        -- In case it`s empty, check for next empty.
        while true do
            --print(state.slot)
            --os.sleep(1)
            if (state == nil) or
                    (state.items[state.slot] == nil) then
                return state, nil
            end

            state = self:next(state)
        end
    else
        -- In case it`s an item, check next item
        --     (with the same name).
        while true do
            --print(state.slot)
            --os.sleep(1)
            if state == nil then
                return state, nil
            elseif (state.items[state.slot] ~= nil) and
                    (state.items[state.slot].name == state.nextName) then
                return state, state.items[state.slot]
            end
            
            state = self:next(state)
        end
    end
end

function StorageCluster:prevItem(state, itemName)
    
    local prepItem
    if state == nil then
        state = self:prev(state)
        prepItem = state.items[state.slot]
    else
        prepItem = state.items[state.slot]
        local name = itemName
            or state.nextName 
            or getItemName(prepItem)
    
        if self.firstItemState ~= nil then
            local firstState = self.firstItemState[name]
            if firstState ~= nil
                    and firstState.inv == state.inv
                    and firstState.slot == state.slot then
               return nil
            end     
        end
        state = self:prev(state)
    end
    
    if state == nil then return nil end
    
    if state.nextName == nil then
        state.nextName = getItemName(prepItem)
    end
    
    if itemName ~= nil then
        state.nextName = itemName
    end
    
    
    if state.nextName == "empty" then
        while true do
            --print(state.slot)
            --os.sleep(1)
            if state == nil
                    or state.items[state.slot] == nil then
                return state,nil
            end
            
            state = self:prev(state)
        end
    else
        while true do
            --print(state.slot)
            --os.sleep(1)
            if state == nil then
                return state,nil
            elseif state.items[state.slot] ~= nil
                    and state.items[state.slot].name == state.nextName then
                return state, state.items[state.slot]
            end
            
            state = self:prev(state)
        end
    end
end

-- Creates a generator for a `for` loop starting from `initState` (if it's `nil`, it starts from the beginning).
function StorageCluster:gen(initState)
    -- NOTE: The `initState` given should not be modified, it should be copied.
    
    if initState == nil then
        return self.next, self, nil
    else
        -- Copying the state. to not mess with the rest of its data (`next` and `prev` functions modify the state).
        initState = deepcopy(initState)

        -- Refreshing possibly outdated items table (the passed state will be updated).
        -- WARN: This may prove to be unnecessary and inefficient.
        initState.items = peripheral.call(
            copy.inv, "list"
        )
        
        return self.next, self, self:prev(initState)
    end
end

-- Creates an inverse generator for a `for` loop starting from `initState` (if it's `nil`, it starts from the beginning).
function StorageCluster:genInv(initState)
    -- NOTE: The `initState` given should not be modified, it should be copied.
    
    if initState == nil then
        return self.next, self, nil
    else
        -- Copying the state. to not mess with the rest of its data.
        initState = deepcopy(initState)

        -- Refreshing possibly outdated items table (the passed state will be updated).
        -- WARN: This may prove to be unnecessary and inefficient.
        initState.items = peripheral.call(
            copy.inv, "list"
        )
    
        return self.next, self, self:next(initState)
    end
end

-- "specifier" can be an initial state or an item name.
function StorageCluster:genItem(specifier)
    if specifier == nil then
        error("specifier is nil.")
    end
    
    local initState
    if type(specifier) == "table" then
        -- If the specifier is a table, it treats it like a state.
        initState = specifier
    elseif type(specifier) == "string" then
        -- If the specifier is a string, it treats it like an item name.
        if self.firstItemState == nil then
            -- If there's no table specifying where the first item is, we search for it.
            initState = self:nextItem(nil, specifier)
        else
            -- If there is one, we use it to find the first state (it creates a copy of the state, to not mess with the stored state).
            initState = deepcopy(self.firstItemState[specifier])
        end
    else
        error("specifier type not recognized")
    end
    
    if initState == nil then
        -- If no initial state was found, the item is not present.
        
        -- This sets up the "for loop" for failure
        return self.next, self, self:prev()
    end
    
    -- Refreshing possibly outdated inventory table.
    initState.items = peripheral.call(
        initState.inv, "list"
    )
    
    -- Setting up the item to be searched.
    if type(specifier) == "string" then
        initState.nextName = specifier
    else
        initState.nextName = getItemName(initState.items[initState.slot])
    end
        
    -- Note: The for loop always calls the next state at the start. Since we want the "initial state" to be the first, we return the state right before it.
    
    -- Accounting for bugs on the very first state of the storage, where "prev" is nil.
    local nextName = initState.nextName
    local prevState,_ = self:prev(initState)
    if prevState == nil then
        -- If we don`t do this, the "next name" may not be correctly set up on the initial state, so the iterator might look for the wrong item.
        initState = self:nextItem(nil, nextName)
        return self.nextItem, self, self:prev(initState)
    else
        return self.nextItem, self, prevState    
    end
end

function StorageCluster:genItemInv(specifier)
    if specifier == nil then
        error("specifier is nil")
    end
    
    local initState
    if type(specifier) == "table" then
        initState = specifier
    elseif type(specifier) == "string" then
        if self.lastItemState == nil then
            initState = self:prevItem(nil, specifier)
        else
            initState = self.lastItemState[specifier]
            initState.nextName = specifier
        end
    else
        error("specifier type not recognized")
    end
    
    if initState == nil then
        return self.prev, self, self:next()
    end
    
    initState.items = peripheral.call(
        initState.inv, "list"
    )
    
    initState = deepcopy(initState)
    
    initState.nextName = 
        getItemName(initState.items[initState.slot])
    
    local nextName = initState.nextName
    local nextState = self:next(initState)
    if nextState == nil then
        initState = self:prevItem(nil, nextName)
        return self.prevItem, self, self:next(initState)
    else
        return self.prevItem, self, nextState
    end
end

------------------------------
-- Startup functions

local function catalogMainStor()
    mainStor.invs = peripheral.call("back", "getNamesRemote")
    
    -- Figuring out the main storage containers.
    local name
    for i=#mainStor.invs,1,-1 do
        name = mainStor.invs[i]
        
        -- Deleting IO containers.
        for _,ioName in pairs(ioStor.invs) do
            if name == ioName then
                table.remove(mainStor.invs, i)
                break
            end
        end

        -- Deleting selection containers.
        for _,selectName in pairs(selectStor.invs) do
            if name == selectName then
                table.remove(mainStor.invs, i)
                break
            end
        end
        
        -- Deleting slave computers.
        if string.find(name, "computer_") ~= nil then
            table.remove(mainStor.invs, i)
        end
    end
    
    -- Getting inventory sizes --
    for i,inv in pairs(mainStor.invs) do
        mainStor.invSizes[i] = peripheral.call(inv, "size")
    end
    
    -- Counting and finding the first/last of each item --
    mainStor.firstItemState = {}
    mainStor.lastItemState = {}
    mainStor.itemCount = {}
    
    local itemName
    for state,item in mainStor:gen() do
        -- For all states in the storage...
        
        itemName = getItemName(item)
            
        -- Saving state of the first item
        if mainStor.firstItemState[itemName] == nil then
            mainStor.firstItemState[itemName] = deepcopy(state)
        end
        
        -- Updating the state of the last item
        mainStor.lastItemState[itemName] = deepcopy(state)
        
        if item ~= nil then
            -- If the item is not empty, work the
            -- counter.
        
            -- Creating counter
            if mainStor.itemCount[itemName] == nil then
                mainStor.itemCount[itemName] = 0
            end
        
            -- Adding items to counter
            mainStor.itemCount[itemName] = mainStor.itemCount[itemName] + item.count
        end
    end
end

local function setupSize(stor)
    for i,inv in pairs(stor.invs) do
        stor.invSizes[i] = peripheral.call(inv, "size")
    end
end

local function getSelectItems()
    local selTable = {}
    for state,item in selectStor:gen() do
        if item ~= nil then
            table.insert(selTable, item.name)
        end
    end
    return selTable
end

-------------------------------------------
-- Logistics functions
--
-- Not aware of item counts, but aware of
-- first and last item states.

-- Think of a smarter way of handling the first/last items (I literally don't know who can and can't modify them).
-- TODO: Move Item *should* update the first/last items list. For IO and selection container, a different (insecure) function should be used.
-- This function moves an item from `fromState` to `toState`, updating both states accordingly (it does not update the first/last item's list).
local function moveItem(fromState, toState, limit)
    -- If the states are in the same inventory, their item tables (state.items) should be *the exact same table in memory*, this removes the need for updating both tables. Yes, this may change the table passed, and it should (they shoud've already been the same).
    if fromState.inv == toState.inv then
        fromState.items = toState.items
    end
    
    local fromItem = fromState.items[fromState.slot]

    -- If there`s no item to move, return nil
    if fromItem == nil then
        return nil
    end
    -- If no limit (or negative limit) was given, then we assume every item is to be moved.
    if limit == nil or limit < 0 then
        limit = fromItem.count
    end
    
    -- Moving item
    local moved = peripheral.call(
            fromState.inv, "pushItems", toState.inv,
            fromState.slot, limit,
            toState.slot
        )
    
    -- NOTE: The following codes' correctness heavily relies on the guarantee that `state.items` is the same when both states are in the same inventory (i.e. updates in one will affect the other if they are in the same inventory).

    -- Updating toState items table (adding item count).
    if toState.items[toState.slot] == nil then
        -- If there was no item, then we create a table for it.
        toState.items[toState.slot] = {
            name = fromItem.name,
            count = moved
        }
    else
        -- If there was already one, we just add to the count.
        toState.items[toState.slot].count = toState.items[toState.slot].count + moved
    end

    -- Updating fromState items table (removing item count).
    fromState.items[fromState.slot].count =
        fromState.items[fromState.slot].count - moved
    if fromState.items[fromState.slot].count == 0 then
        -- If all items were removed from the slot, then we destroy its table.
        fromState.items[fromState.slot] = nil
    end
    
    return moved
end

-- Stores item, but does not add to the total counter.
-- Note: This is notably used for retrieving
-- from "selectedStor" without changing the counter.
pushItem = function(fromState)
    local fromItem = fromState.items[fromState.slot]

    if fromItem == nil then
        -- If there`s no item to push, return nil.
        return nil
    end
    
    -- Trying to put on the last available spot
    -- that already has the item.
    local amount = fromItem.count
    local moved = 0
    local toState = mainStor.lastItemState[fromItem.name]
    
    if toState ~= nil then
        -- If there`s an item in inventory, we
        -- start from their end.
        
        -- Trying to move items to the last slot.
        moved = moved + moveItem(fromState, toState) 
        
        -- If all items were moved, return.
        if moved == amount then
            -- If all items were moved, return.
            return moved
        end
        -- If not, we try the empty spaces after it.
        
        -- Finding the first empty space after the last
        -- item.
        toState = mainStor:nextItem(toState, "empty")
    
        local lastState = mainStor.lastItemState[fromItem.name]
        if toState ~= nil then
            -- If an empty space was found, start from
            -- it and try to store the item.
            
            for toState,item in mainStor:genItem(toState) do
                moved = moved + moveItem(fromState, toState)
                
                -- Saving the current last item state.
                lastState = toState
                
                -- Stop if all items were stored.
                if moved == amount then
                    break
                end
            end
        end
    
        -- Storing the new last item state
        mainStor.lastItemState[fromItem.name] = lastState
    end

    if amount ~= moved then
        -- If there are still items to be stored,
        -- do a second pass, this time from the
        -- very beggining (instead of from the
        -- last item state).

        local firstCurr = mainStor.firstItemState[fromItem.name]
        local firstState = mainStor.firstItemState["empty"]
            
        --local firstState = mainStor:nextItem(nil, "empty")
        
        if firstState ~= nil then
            -- If an empty space was found, start storing.
        
            -- If the empty space comes before the old first slot, that one is the new first slot.
            if (firstState:isBefore(firstCurr)) then
                mainStor.firstItemState[fromItem.name] = firstState
            end
            
            -- Storing items.
            for toState,_ in mainStor:genItem(firstState) do
                moved = moved + moveItem(fromState, toState, amount)
                
                if moved == amount then
                    -- If all items were moved, save the last item state and halt.
                    mainStor.lastItemState[fromItem.name] = toState
                    break
                end
            end
        end
    end
    
    -- Note: The reason we are using
    -- genItem/genItemInv instead of
    -- nextItem/prevItem in the following updates
    -- is because the generators will stars from
    -- the lastest first/last item state recorded,
    -- which makes it more efficient (so efficient
    -- in fact, that it`s almost no cost if the
    -- first/last item state didn`t change).
    
    -- Updating last empty space
    for state,_ in mainStor:genItemInv("empty") do
        mainStor.lastItemState["empty"] = state
        break
    end
    
    -- Updating first empty space
    for state,_ in mainStor:genItem("empty") do
        mainStor.firstItemState["empty"] = state
        break
    end
    
    return moved
end

pullItem = function(toState, itemName, limit)
    local fromState = deepcopy(mainStor.lastItemState[itemName])
    
    -- If there's no item in storage, there's nothing to pull.
    if fromState == nil then
        return nil
    end
    
    local currMoved
    local moved = 0
    local remaining = limit
    local lastState = fromState
    -- Pulling items
    for fromState,item in mainStor:genItemInv(fromState) do
        if limit < 0 then
            -- If the limit is below 0, all items are to be pulled.
            remaining = item.count
        end
        
        currMoved = moveItem(fromState, toState, remaining)
        
        moved = moved + currMoved
        remaining = limit - moved
        
        -- Remembering new last item state
        lastState = fromState
        
        if fromState.items[fromState.slot] ~= nil then
            -- If there are not all items were
            -- moved, that means we can`t move 
            -- any more items. 
            break
        else
            if remaining == 0 then
                -- If everything was moved, update
                -- the last state (its currently
                -- empty) and halt.
            
                mainStor:prevItem(lastState)
                break
            end
        end
    end
    -- Saving new last item state.
    mainStor.lastItemState[itemName] = lastState
    
    if lastState == nil then
        -- If there`s no last item state, there`s
        -- no items, so remove the first item
        -- state as well.
        mainStor.firstItemState[itemName] = nil
    end
    
    return moved
end

-----------------------------------------------
-- Storage functions
--
-- Aware of item counts.

local function rebuildSelectStor()
    -- Removing all items from the select storage.
    for state,item in selectStor:gen() do
        if item ~= nil then
            pushItem(state)
            
            -- Updating counter
            if mainStor.itemCount[item.name] ~= nil then
                mainStor.itemCount[item.name] =
                    mainStor.itemCount[item.name] + 1
            else
                mainStor.itemCount[item.name] = 1
            end
        end
    end
    
    local toState = nil
    local cmp = function(a,b) return a > b end
    -- Pulling one of each item in storage,
    -- in decrescent item count order.
    for _,name in pairs(getOrder(mainStor.itemCount, cmp)) do
        if name ~= "empty" then
            toState = selectStor:next(toState)
            
            pullItem(toState, name, 1)
            
            -- Updating counter
            mainStor.itemCount[name] =
                mainStor.itemCount[name] - 1
        
            -- If the item counter reaches 0,
            -- delete it.
            if mainStor.itemCount[name] == 0 then
                mainStor.itemCount[name] = nil
            end
        end
    end
end

local function storeAll()
    local stored
    local itemCount
    for state,item in ioStor:gen() do
        -- Storing every item in the IO storage.
        if item ~= nil then
            itemCount = item.count
            stored = pushItem(state)
            
            if mainStor.itemCount[item.name] ~= nil then
                -- If there`s no counter for the item,
                -- create it.
                mainStor.itemCount[item.name] =
                    mainStor.itemCount[item.name] + stored
            else
                -- If there is, add to it.
                mainStor.itemCount[item.name] = stored
            end
            
            if item.count ~= 0 then
                -- If some items remain, there`s
                -- not enough space to store.
                error("not enough storage.")
            end
        end
    end
end

haulItems = function(itemName, amount)
    if (mainStor.itemCount[itemName] == nil) 
            or (mainStor.itemCount[itemName] < amount) then
        error("not enough items")
    end
    
    local moved = 0
    local remaining = amount
    local justMoved
    for freeState,item in ioStor:genItem("empty") do
        justMoved = nil
        while justMoved ~= 0 do
            justMoved = pullItem(freeState, itemName, remaining)
            
            moved = moved + justMoved
            remaining = amount - moved
        end
        if remaining == 0 then break end
    end
    
    mainStor.itemCount[itemName] =
        mainStor.itemCount[itemName] - moved
    
    if mainStor.itemCount[itemName] == 0 then
        mainStor.itemCount[itemName] = nil
    end
end

local function packItem(itemName)
    -- This works by moving items to the back to the front of its available slots.
		
		print("Processing ", itemName)
		
		setmetatable(mainStor.firstItemState[itemName], State)
		setmetatable(mainStor.lastItemState[itemName], State)
 
    -- If the last and first slots are in the same place, then there's nothing to pack.
    if mainStor.firstItemState[itemName]:isAt(mainStor.lastItemState[itemName]) then
        return
    end
    
    local head = deepcopy(mainStor.firstItemState[itemName])
    
    -- Move the head forward and the tail backward, always moving the items back to front, until head and tail meet.
    local moved
    for state,item in mainStor:genItemInv(itemName) do
        repeat
            moved = moveItem(state, head)

            -- If it couldn't move the items to the head, move the head forward.
            if moved == 0 then
                oldHead = deepcopy(head)

                head, _ = mainStor:nextItem(head, itemName) 
                
                -- If the head is `nil`, then we've reached the end.
                if head == nil then
                    -- These set up the outter conditional for failure.
                    head = oldHead
                    tail = head
                    break
                end
            end
            
            -- Repeat until the tail moved the slot (no more items in it), or the head reached the end (next of `head` is `nil` / head met tail).
        until state.items[state.slot] == nil or head:isAt(state)

        if head:isAt(state) then
            break
        end
    end
    
    mainStor.lastItemState[itemName] = head
end

local function sortMainStor()
    -- Finding an empty space in the ioStor for item swapping.
    local swapState,_ = ioStor:nextItem(nil, "empty")
    
    if swapState == nil then
        error("no empty space available for swapping")
    end
    
    local cmp = function(a,b) return a > b end
    local tail = mainStor:next()
    
    -- NOTE: Calling `getOrder` makes sure that the `for` goes through items in order (by item count).
    -- For every item (name).
    for _,itemName in pairs(getOrder(mainStor.itemCount, cmp)) do
        -- Setting up the new first state (current tail).
        mainStor.firstItemState[itemName] = tail
        
        -- For every item of that type...
        for state,item in mainStor:genItem(itemName) do
            -- ...move it to the tail (i.e. only stop if there`s no more items to move, or if it was swapped).
            while state.items[state.slot] ~= nil and state.items[state.slot].name == itemName do
                -- If the tail reaches the item, it`s already in its place.
                if state.invPos == tail.invPos and state.slot == tail.slot then
                    mainStor:next(tail)
                    break
                -- It should be impossible for the current item to be behind the tail.
                elseif state.invPos < tail.invPos or (state.invPos == tail.invPos and state.slot < tail.slot) then
                    error("wrong state while sorting")
                end


                -- In case there`s a free space or an item of the same type, try to move.                     
                if tail.items[tail.slot] == nil then
                    moveItem(state, tail)
                    mainStor:next(tail)
                -- In case there`s different item there, we swap them.
                else
                    moveItem(state, swapState)
                    moveItem(tail, state)
                    moveItem(swapState, tail)
                    mainStor:next(tail)
                    
                    item = state.items[state.slot]
                    -- If item swapped ends up after the last item in the inventory, then update the last item table.
                    lastItemState = mainStor.lastItemState[item.name]
                    if lastItemState.invPos < state.invPos or (lastItemState.invPos == state.invPos and lastItemState.slot < state.slot) then
                        mainStor.lastItemState[item.name] = deepcopy(state)
                    end    
                end
            end
        end
    end
end

------------------------------------------------------------

rednet.open("back")

local id = nil
local message = nil

-- Waiting for handshake.
repeat
	id, message = rednet.receive()
until (type(message) == "table" and message.sender_type == "master" and message.message_type == "handshake")

local master_id = id

-- Sending master confirmation handshake.
rednet.send(master_id, {
	sender_type = "slave",
	message_type = "handshake"
})

print("Connected to master (id ", master_id, ")")

while true do
	repeat
		id, message = rednet.receive()
	until (id == master_id and message.message_type == "task")

	if message.task == "pack" then
		mainStor, itemName = unpack(message.args)
		setmetatable(mainStor, StorageCluster)

		packItem(itemName)

		repeat
			rednet.send(master_id, {
				sender_type = "slave",
				message_type = "completed_task"
			})
			
			id, message = rednet.receive(nil, 1)
		until (id == master_id and message.message_type == "confirm_task_completed")
	end
end

--repeae
--	id, message = rednesage_type = "confirm_task_i".receive()
--until (id == master_id && type(message) == "table" && message.sender_type == "master")



