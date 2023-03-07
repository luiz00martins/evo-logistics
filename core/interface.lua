local utils = require('/logos-library.utils.utils')
local abstract = require('/logos-library.core.abstract')
local standard = require('/logos-library.core.standard')

local transfer = abstract.transfer
local new_class = utils.new_class
local array_reduce = utils.array_reduce
local array_map = utils.array_map

local StandardInventory = standard.StandardInventory
local StandardCluster = standard.StandardCluster


-- Interface inventory.
local InterfaceInventory = new_class(StandardInventory)

function InterfaceInventory:new(args)
	local new_inventory = StandardInventory:new(args)

	-- Could not find inventory.
	if not new_inventory then
		return nil
	end

	new_inventory.storage_clusters = args.storage_clusters or error('No storage clusters provided')
	new_inventory.config_types = {
		active_import = {},
		active_export = {},
		passive_import = {},
		passive_export = {},
	}

	setmetatable(new_inventory, InterfaceInventory)
	return new_inventory
end

function InterfaceInventory:registerConfig(config)
	if not config then
		error('config not provided')
	elseif not config.type then
		error('`config.type` not provided')
	end

	local config_type = config.type
	config.type = nil
	local config_slot = config.index
	config.index = nil

	local config_list = self.config_types[config_type] or error('No configuration of type '..config_type)

	if not config_slot then
		for index=1,self.size do
			config_list[index] = config
		end
	else
		config_list[config_slot] = config
	end
end

function InterfaceInventory:_executeActiveImports()
	for index,config in pairs(self.config_types.active_import) do
		local slot = self.slots[index]

		local item_name = config.item_name
		local amount = config.count

		local amount_moved = 0
		for _,storage_cluster in ipairs(self.storage_clusters) do
			repeat
				local just_moved = transfer(storage_cluster, slot, nil, nil, item_name, amount - amount_moved)
				amount_moved = amount_moved + just_moved
			until not storage_cluster:hasItem(item_name) or just_moved == 0 or amount == amount_moved

			if amount == amount_moved then
				break
			end
		end
	end
end

function InterfaceInventory:outputSlot(item_name)
	-- FIXME: That's pretty efficient, ain't it?
	self:refresh()
	for index,config in pairs(self.config_types.passive_export) do
		local slot = self.slots[index]
		if (not config.item_name or not item_name or config.item_name == item_name) and slot:hasItem(item_name) then
			return slot
		end
	end

	return nil
end

function InterfaceInventory:availableItemCount(item_name)
	local item_count = 0
	for index,config in pairs(self.config_types.passive_export) do
		local slot = self.slots[index]
		if (not config.item_name or not item_name or config.item_name == item_name) and slot:hasItem(item_name) then
			item_count = item_count + slot:itemCount(item_name)
		end
	end

	return item_count
end

function InterfaceInventory:hasItem(item_name)
	return self:outputSlot(item_name) ~= nil
end

InterfaceInventory.itemIsAvailable = InterfaceInventory.hasItem

function InterfaceInventory:execute()
	self:_executeActiveImports()
end

-- Interface cluster.
local InterfaceCluster = new_class(StandardCluster)

function InterfaceCluster:new(args)
	local new_cluster = StandardCluster:new(args)

	new_cluster.storage_clusters = args.storage_clusters or error('parameter missing `storage_clusters`')
	new_cluster.config_lists = {
		active_imports = {},
		active_exports = {},
		passive_imports = {},
		passive_exports = {},
	}

	setmetatable(new_cluster, InterfaceCluster)
	return new_cluster
end

function InterfaceCluster:availableItemCount(item_name)
	return array_reduce(
		array_map(
			self.invs,
			function(inv) return inv:availableItemCount(item_name) end),
		function(a, b) return a + b end,
		0
	)
end

function InterfaceCluster:_createInventory(args)
	return InterfaceInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
		storage_clusters = self.storage_clusters,
	}
end

function InterfaceCluster:registerConfig(config)
	if not config then
		error('config not provided')
	elseif not config.inv_name then
		error('`config.inv_name` not provided')
	end

	local inv_name = config.inv_name
	config.inv_name = nil

	local inv
	for _,invv in ipairs(self.invs) do
		if invv.name == inv_name then
			inv = invv
		end
	end
	if not inv then
		error('Inventory '..inv_name..' not in cluster '..self.name)
	end

	inv:registerConfig(config)
end

function InterfaceCluster:_executeActiveImports()
	for _,config in pairs(self.active_imports) do

	end

	local function active_import(index, item_name, amount)
		if not self:itemExists(item_name) then
			error('Item '..item_name..' does not exist in cluster '..self.name)
		end

		local amount_moved = 0
		for _,storage_cluster in ipairs(self.storage_clusters) do
			repeat
				-- FIXME: This doen't work
				local just_moved = storage_cluster:transfer(item_name, storage_cluster, amount - amount_moved)
				amount_moved = amount_moved + just_moved
			until not storage_cluster:itemExists(item_name) or just_moved == 0 or amount == amount_moved
		end
	end

	if item_name then
		active_import(item_name)
	else
		for _,item_name in ipairs(self:itemNames()) do
			active_import(item_name)
		end
	end
end

function InterfaceCluster:execute()
	for _,inv in ipairs(self.invs) do
		inv:execute()
	end
end

return {
	InterfaceInventory = InterfaceInventory,
	InterfaceCluster = InterfaceCluster,
}
