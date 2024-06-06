---@diagnostic disable: need-check-nil
local utils = require('/logos-library.utils.utils')
local inv_utils = require('/logos-library.utils.inventories')
local abstract = require('/logos-library.core.abstract')
local shaped = require('/logos-library.core.shaped')
local shapeless = require('/logos-library.core.shapeless')

local new_class = require('/logos-library.utils.class').new_class
local array_find = utils.array_find
local table_find = utils.table_find
local array_unique = utils.array_unique
local array_map = utils.array_map
local table_map = utils.table_map
local table_map2 = utils.table_map2
local table_reduce = utils.table_reduce
local table_keys = utils.table_keys
local table_values = utils.table_values
local table_shallowcopy = utils.table_shallowcopy
local table_contains = utils.table_contains
local array_contains = utils.array_contains
local array_slice = utils.array_slice
local table_filter = utils.table_filter
local array_filter = utils.array_filter
local uuid = utils.uuid
local inventory_type = inv_utils.inventory_type
local is_shaped = inv_utils.is_shaped

local ShapedInventory = shaped.ShapedInventory
local ShapelessInventory = shapeless.ShapelessInventory
local AbstractCluster = abstract.AbstractCluster
local transfer = abstract.transfer

local CRAFTING_COMPONENT_PRIORITY = 1

local function _getPriority(_) return CRAFTING_COMPONENT_PRIORITY end

local SLOT_TYPE = {
	INPUT = 'input',
	OUTPUT = 'output',
	TEMPLATE = 'template',
}

-- Crafting Recipe Class

local CraftingRecipe = new_class()

local function _check_output(slots)
	for _, slot in pairs(slots) do
		if slot.type == SLOT_TYPE.OUTPUT then
			return true
		end
	end

	return false
end

function CraftingRecipe:new(args)
	if not args then error("parameter missing `args`")
	elseif not args.name then error("parameter missing `name`")
	elseif not args.slots then error('recipe '..args.name..' missing `slots`')
	elseif args.is_shaped == nil then error('recipe '..args.name..' missing `is_shaped`')
	end

	-- Checking slots.
	for _,slot_data in pairs(args.slots) do
		if not slot_data.item_name then error('no item_name provided in crafting slot') end
		if not slot_data.amount then error('no amount provided in crafting slot') end
		if not slot_data.type then error('no type provided in crafting slot') end
		if args.is_shaped and not slot_data.index then error('no index provided in crafting slot') end

		if not table_contains(table_values(SLOT_TYPE), slot_data.type) then error('invalid crafting slot type provided ('..tostring(slot_data.type)..')') end
	end

	if not _check_output(args.slots) then error('no output slots found in recipe '..args.name) end

	local new_recipe = {
		id = args.id or uuid(),
		name = args.name,
		is_shaped = args.is_shaped,
		slots = args.slots,
	}

	setmetatable(new_recipe, CraftingRecipe)
	return new_recipe
end

-- Crafting Profile Class

local CraftingProfile = new_class()

function CraftingProfile:new(args)
	-- These arguments must be passed.
	if args.name == nil then error("parameter missing `name`") end
	if args.inv_type == nil then error("parameter missing `inv_type`") end
	if args.whitelist_invs and args.blacklist_invs then error("cannot pass both whitelist and blacklist") end

	if args.whitelist_invs then
		args.whitelist_invs = table_map2(args.whitelist_invs, function(_, inv_name) return inv_name, true end)
	elseif args.blacklist_invs then
		args.blacklist_invs = table_map2(args.blacklist_invs, function(_, inv_name) return inv_name, true end)
	end

	local newCraftingProfile = {
		id = args.id or uuid(),
		name = args.name,
		inv_type = args.inv_type,
		recipes = args.recipes or {},
		whitelist_invs = args.whitelist_invs,
		blacklist_invs = args.blacklist_invs,
	}

	setmetatable(newCraftingProfile, self)
	return newCraftingProfile
end

function CraftingProfile:serialize()
	-- Whitelists and blacklists are formatted as 'list[item_name]' for ease of use. However, they are saved as an array of names, since this is the way that we expose the interface.

	local whitelist_invs
	local blacklist_invs
	if self.whitelist_invs then
		whitelist_invs = table_keys(self.whitelist_invs)
	elseif self.blacklist_invs then
		blacklist_invs = table_keys(self.blacklist_invs)
	end

	local serialized = textutils.serialize{
		name = self.name,
		recipes = self.recipes,
		inv_type = self.inv_type,
		whitelist_invs = whitelist_invs,
		blacklist_invs = blacklist_invs,
	}

	return serialized
end

function CraftingProfile:fromSerialized(serialized)
	local unserialized = textutils.unserialize(serialized)

	local newCraftingProfile = CraftingProfile:new{
		name = unserialized.name,
		recipes = unserialized.recipes,
		inv_type = unserialized.inv_type,
		whitelist_invs = unserialized.whitelist_invs,
		blacklist_invs = unserialized.blacklist_invs,
	}

	return newCraftingProfile
end

function CraftingProfile:addRecipe(recipe_args)
	if not recipe_args.is_shaped then
		recipe_args.is_shaped = is_shaped(self.inv_type)
	end

	local recipe = CraftingRecipe:new(recipe_args)

	self.recipes[recipe.id] = recipe
end

function CraftingProfile:removeRecipe(recipe)
	self.recipes[recipe.id] = nil

	error('No recipe '..recipe.name..' found')
end


local INV_CRAFTING_STATUS = {
	IDLE = 'idle',
	TEMPLATED = 'templated',
	CRAFTING = 'crafting',
	CRAFTED = 'crafted',
}

local ShapedCraftingInventory = new_class(ShapedInventory)
local ShapelessCraftingInventory = new_class(ShapelessInventory)
local CraftingInventory = new_class()

function CraftingInventory:new(args)
	local new_inventory
	if is_shaped(inventory_type(args.name)) then
		new_inventory = ShapedInventory:new(args)
		setmetatable(new_inventory, ShapedCraftingInventory)
	else
		new_inventory = ShapelessInventory:new(args)
		setmetatable(new_inventory, ShapelessCraftingInventory)
	end

	new_inventory.status = INV_CRAFTING_STATUS.IDLE
	new_inventory.executing_amount = 0

	return new_inventory
end

function ShapedCraftingInventory:startRecipe(recipe, storage_clusters)
	if self.status ~= INV_CRAFTING_STATUS.IDLE then
		error('Already started a recipe for '..self.executing_recipe.name)
	end

	self.executing_recipe = recipe
	self.storage_clusters = storage_clusters

	local templates = array_map(recipe.slots, function(slot) if slot.type == SLOT_TYPE.TEMPLATE then return slot end end)

	self:_retrieveItems(templates)

	self.status = INV_CRAFTING_STATUS.TEMPLATED
end
ShapelessCraftingInventory.startRecipe = ShapedCraftingInventory.startRecipe

function ShapedCraftingInventory:executeRecipe()
	if self.status == INV_CRAFTING_STATUS.IDLE then
		error('No recipe to execute')
	elseif self.status == INV_CRAFTING_STATUS.CRAFTING then
		error('Already executing recipe for '..self.executing_recipe.name)
	end

	local inputs = array_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.INPUT then return slot end end)

	if self:_retrieveItems(inputs) then
		self.status = INV_CRAFTING_STATUS.CRAFTING
		self.executing_amount = self.executing_amount + 1

		return true
	else
		return false
	end

end
ShapelessCraftingInventory.executeRecipe = ShapedCraftingInventory.executeRecipe

function ShapedCraftingInventory:awaitRecipe()
	if self.status == INV_CRAFTING_STATUS.IDLE then
		error('No recipe to await')
	elseif self.status == INV_CRAFTING_STATUS.TEMPLATED
			or self.status == INV_CRAFTING_STATUS.CRAFTED then
		return
	end

	local outputs = array_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)

	for _,slot_data in pairs(outputs) do
		local output_slot = self.slots[slot_data.index]

		repeat
			self:refresh()
			os.sleep(0)
		until output_slot:itemCount() >= slot_data.amount
	end

	self.status = INV_CRAFTING_STATUS.CRAFTED
end

function ShapelessCraftingInventory:awaitRecipe()
	if self.status == INV_CRAFTING_STATUS.IDLE then
		error('No recipe to await')
	elseif self.status == INV_CRAFTING_STATUS.TEMPLATED
			or self.status == INV_CRAFTING_STATUS.CRAFTED then
		return
	end

	local outputs = array_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)

	for _,slot_data in pairs(outputs) do
		repeat
			self:refresh()
			os.sleep(0)
		-- WARNING: We do not check for the amount of items (as there's no way to guarantee it for shapeless slots), only the existence of it.
		until self:hasItem(slot_data.item_name)
	end


	self.status = INV_CRAFTING_STATUS.CRAFTED
end

function ShapedCraftingInventory:finishRecipe()
	local outputs = array_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)
	self:_dispatchItems(outputs)

	local templates = array_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.TEMPLATE then return slot end end)
	self:_dispatchItems(templates)
	self.executing_amount = self.executing_amount - 1

	if self.executing_amount == 0 then
		self.status = INV_CRAFTING_STATUS.IDLE

		self.executing_recipe = nil
		self.storage_clusters = nil
	else
		self.status = INV_CRAFTING_STATUS.CRAFTING
	end
end
ShapelessCraftingInventory.finishRecipe = ShapedCraftingInventory.finishRecipe

-- This function may fail to retrieve all the items. In which case, it will return false. Otherwise, it returns true.
function ShapedCraftingInventory:_retrieveItems(slots_data)
	self:refresh()

	local amount_pulled = array_map(slots_data, function() return 0 end)
	local amount_needed = array_map(slots_data, function(slot_data) return slot_data.amount end)

	-- Pulling the items.
	for i,slot_data in ipairs(slots_data) do
		local item_name = slot_data.item_name

		for _,cluster in ipairs(self.storage_clusters) do
			if amount_pulled[i] < amount_needed[i] and cluster:itemIsAvailable(slot_data.item_name) then
				local toSlot = self.slots[slot_data.index]
				amount_pulled[i] = amount_pulled[i] + transfer(cluster, toSlot, item_name, amount_needed[i]-amount_pulled[i])
				self.log.trace('Pulled '..utils.tostring(amount_pulled[i])..'/'..utils.tostring(amount_needed[i])..' of '..item_name..' from '..cluster.name..' to slot '..toSlot.index..' of '..self.name)
			end
		end

		if amount_pulled[i] < amount_needed[i] then
			-- Failed to retrieve all the items. Break early.
			break
		end
	end

	-- Checking if we have all the items.
	local failed = false
	for i,amount in ipairs(amount_needed) do
		if amount_pulled[i] < amount then
			self.log.trace('Not enough '..slots_data[i].item_name..' to execute recipe '..self.executing_recipe.name..' ('..amount_pulled[i]..'/'..amount..'). Pulling back...')
			failed = true
		end
	end

	-- Pulling back the items.
	if failed then
		local pulled_back = array_map(amount_pulled, function(_) return 0 end)

		for _,cluster in ipairs(self.storage_clusters) do
			for i,amount in pairs(amount_pulled) do
				local item_name = slots_data[i].item_name

				if pulled_back[i] < amount then
					local fromSlot = self.slots[i]
					pulled_back[i] = pulled_back[i] + transfer(fromSlot, cluster, item_name, amount-pulled_back[i])

					self.log.trace('Pulled back '..utils.tostring(pulled_back[i])..'/'..utils.tostring(amount)..' of '..item_name..' from '..self.name..' to '..cluster.name)
				end
			end
		end
	end

	return not failed
end

-- This function may fail to retrieve all the items. In which case, it will return false. Otherwise, it returns true.
function ShapelessCraftingInventory:_retrieveItems(slots_data)
	self:refresh()

	-- NOTE: The order is guaranteed by the API. That is, slots_data[1] will be retrieved first, then slots_data[2] and so on.
	local amount_pulled = array_map(slots_data, function(_) return 0 end)
	local amount_needed = array_map(slots_data, function(data) return data.amount end)

	-- Pulling the items.
	for _,cluster in ipairs(self.storage_clusters) do
		for i,amount in ipairs(amount_needed) do
			local item_name = slots_data[i].item_name

			if amount_pulled[i] < amount and cluster:itemIsAvailable(item_name) then
				amount_pulled[i] = amount_pulled[i] + transfer(cluster, self, item_name, amount-amount_pulled[i])
				self.log.trace('Pulled '..utils.tostring(amount_pulled[i])..'/'..utils.tostring(amount_needed[i])..' of '..item_name..' from '..cluster.name..' to '..self.name)
			end
		end
	end

	-- Checking if we have all the items.
	local failed = false
	for i,amount in ipairs(amount_needed) do
		if amount_pulled[i] < amount then
			local item_name = slots_data[i].item_name

			self.log.trace('Not enough '..item_name..' to execute recipe '..self.executing_recipe.name..' ('..amount_pulled[i]..'/'..amount..'). Pulling back...')
			failed = true
		end
	end

	-- Pulling back the items.
	if failed then
		local pulled_back = array_map(slots_data, function(_) return 0 end)

		for _,cluster in ipairs(self.storage_clusters) do
			for i,amount in ipairs(amount_pulled) do
				if pulled_back[i] < amount then
					local item_name = slots_data[i].item_name

					pulled_back[i] = pulled_back[i] + transfer(self, cluster, item_name, amount-pulled_back[i])

					self.log.trace('Pulled back '..utils.tostring(pulled_back[i])..'/'..utils.tostring(amount)..' from '..self.name..' to '..cluster.name)
				end
			end
		end
	end

	return not failed
end

function ShapedCraftingInventory:_dispatchItems(slots_data)
	self:refresh()

	for j,slot_data in pairs(slots_data) do
		local full_amount_moved = 0
		local output_slot = self.slots[slot_data.index]

		-- Removing crafted items.
		for _,cluster in ipairs(self.storage_clusters) do
			if full_amount_moved ~= slot_data.amount then
				local moved_amount = transfer(output_slot, cluster, slot_data.item_name, slot_data.amount - full_amount_moved)

				self.log.trace('Dispatched '..utils.tostring(moved_amount)..'/'..utils.tostring(slot_data.amount)..' of '..slot_data.item_name..' from '..self.name..' to '..cluster.name)
				full_amount_moved = full_amount_moved + moved_amount
			else
				break
			end
		end

		if full_amount_moved ~= slot_data.amount then
			error('Could not export item '..output_slot:itemName())
		end
	end
end

function ShapelessCraftingInventory:_dispatchItems(slots_data)
	self:refresh()

	for _,slot_data in pairs(slots_data) do
		local moved = 0

		-- Removing crafted items.
		for _,cluster in ipairs(self.storage_clusters) do
			if moved < slot_data.amount then
				local moved_amount = transfer(self, cluster, slot_data.item_name, slot_data.amount-moved)
				moved = moved + moved_amount

				self.log.trace('Dispatched '..utils.tostring(moved_amount)..'/'..utils.tostring(slot_data.amount)..' of '..slot_data.item_name..' from '..self.name..' to '..cluster.name)
			else
				break
			end
		end

		if moved < slot_data.amount then
			error('Could not export item '..slot_data.item_name..' ('..moved..'/'..slot_data.amount..')')
		end
	end
end


local CraftingCluster = new_class(AbstractCluster)

function CraftingCluster:new(args)
	local new_cluster = AbstractCluster:new(args)

	new_cluster.storage_clusters = args.storage_clusters
	new_cluster.profiles = {}
	new_cluster.item_recipes = {}

	setmetatable(new_cluster, CraftingCluster)
	return new_cluster
end

CraftingCluster._getPriority = _getPriority

function CraftingCluster:_itemAddedHandler(_, _, _) end
function CraftingCluster:_itemRemovedHandler(_, _, _) end

function CraftingCluster:dataPath()
	return "/logistics_data/"..self.name..".data"
end

function CraftingCluster:saveData()
	local profiles = table_map(self.profiles, function(profile) return profile:serialize() end)

	local inv_names = array_map(self.invs, function(inv) return inv.name end)

	local data = {
		profiles = profiles,
		inv_names = inv_names,
	}

	return textutils.serialize(data)
end

function CraftingCluster:loadData(data)
	data = textutils.unserialize(data)

	local profiles = {}
	for _,serialized_profile in pairs(data.profiles) do
		local profile = CraftingProfile:fromSerialized(serialized_profile)
		profiles[#profiles+1] = profile
	end

	self.profiles	= profiles
	self.invs	= {}
	for _,inv_name in ipairs(data.inv_names) do
		if peripheral.isPresent(inv_name) then
			self:registerInventory{
				parent = self,
				name = inv_name,
			}
		else
			self.log.warning("Inventory "..inv_name.." is no longer present")
		end
	end

	return true
end

function CraftingCluster:registerInventory(args)
	args.parent = self
	local inv = CraftingInventory:new(args)

	table.insert(self.invs, inv)
end

function CraftingCluster:unregisterInventory(inv_name)
	for i,inv in ipairs(self.invs) do
		if inv.name == inv_name then
			table.remove(self.invs, i)
			return true
		end
	end

	error("Inventory "..inv_name.." is not registered")
end

function CraftingCluster:itemCount(_)
	return 0
end

function CraftingCluster:_addRecipeData(recipe)
	local done = {}
	for _,slot_data in pairs(recipe.slots) do
		if slot_data.type == SLOT_TYPE.OUTPUT and not done[slot_data.item_name] then
			if not self.item_recipes[slot_data.item_name] then
				self.item_recipes[slot_data.item_name] = {}
			end

			table.insert(self.item_recipes[slot_data.item_name], recipe)
			done[slot_data.item_name] = true
		end
	end
end

function CraftingCluster:_addProfileData(profile)
	for _,recipe in pairs(profile.recipes) do
		local extended_recipe = table_shallowcopy(recipe)
		extended_recipe.profile = profile.id
		self:_addRecipeData(extended_recipe)
	end
end

function CraftingCluster:addProfile(profile)
	-- local profile_names = array_map(self.profiles, function(_profile) return _profile.name end)
	local id = table_find(self.profiles, function(_profile) return _profile.name == profile.name end)
	if id then
		error('Profile '..profile.name..' already present in cluster '..self.name)
	end

	self:_addProfileData(profile)
	self.profiles[profile.id] = profile
end

function CraftingCluster:_removeRecipeData(recipe)
	local output_item_names = table_filter(recipe.slots, function(slot_data) return slot_data.type == SLOT_TYPE.OUTPUT end)
	output_item_names = table_map(output_item_names, function(slot_data) return slot_data.item_name end)

	for _,item_name in pairs(output_item_names) do
		for i,_recipe in ipairs(self.item_recipes[item_name]) do
			if _recipe == recipe then
				table.remove(self.item_recipes[item_name], i)
				break
			end
		end
	end
end

function CraftingCluster:_removeProfileData(profile)
	for _,recipe in pairs(profile.recipes) do
		self:_removeRecipeData(recipe)
	end
end

function CraftingCluster:removeProfile(profile)
	local id = table_find(self.profiles, function(_profile) return _profile.name == profile.name end)
	if not id then
		error('Profile'..profile.name..' not present in cluster '..self.name)
	end

	self:_removeProfileData(profile)
	self.profiles[id] = nil
end

function CraftingCluster:_createInventory(args)
	return CraftingInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function CraftingCluster:_refreshInternals()
	self.item_recipes = {}

	for _,profile in pairs(self.profiles) do
		self:_addProfileData(profile)
	end
end

function CraftingCluster:refresh()
	for _,inv in ipairs(self.invs) do
		inv:refresh()
	end

	self:_refreshInternals()
end

function CraftingCluster:catalog()
	for _,inv in ipairs(self.invs) do
		inv:catalog()
	end

	self:_refreshInternals()
end

function CraftingCluster:itemNames()
	local item_names = {}

	for _,profile in pairs(self.profiles) do
		for _,recipe in pairs(profile.recipes) do
			for _,slot_data in pairs(recipe.slots) do
				if slot_data.type == SLOT_TYPE.OUTPUT then
					item_names[#item_names+1] = slot_data.item_name
				end
			end
		end
	end

	return array_unique(item_names)
end

function CraftingCluster:getAvailableItems(storage_clusters)
	local items = {}

	for _,cluster in ipairs(storage_clusters) do
		for item_name,count in pairs(cluster.item_count) do
			if not items[item_name] then
				items[item_name] = 0
			end

			items[item_name] = items[item_name] + count
		end
	end

	return items
end

function CraftingCluster:calculateMissingItems(item_name, amount, craft_list)
	local missing_items = {}

	craft_list = craft_list or {}

	-- find available crafting
	local recipes = self.item_recipes[item_name]
	if not recipes then
		table.insert(missing_items, {
			name = item_name,
			count = amount,
		})
		return missing_items
	end
	local recipe = recipes[1]

	local output_crafted = 0

	-- Getting how many items are needed for each crafing.
	local inputs_needed = {}
	for _,slot_data in pairs(recipe.slots) do
		if slot_data.type == SLOT_TYPE.INPUT then
			inputs_needed[slot_data.item_name] = (inputs_needed[slot_data.item_name] or 0) + slot_data.amount

		elseif slot_data.item_name == item_name and slot_data.type == SLOT_TYPE.OUTPUT then
			output_crafted = output_crafted + slot_data.amount
		end
	end

	-- Findind out now many crafting actions will be necessary.
	local crafting_count = math.ceil(amount/output_crafted)

	-- Recursively crafting necessaty items, if they are not already in inventory.
	for _item_name,amount_needed in pairs(inputs_needed) do
		amount_needed = amount_needed * crafting_count

		local item_counts = table_map(self.storage_clusters, function(cluster) return cluster.item_count[_item_name] end)
		local total_stored = table_reduce(item_counts, function(a, b) return a + b end, 0)

		if total_stored < amount_needed then
			if array_contains(craft_list, _item_name) then
				error('More '.._item_name..' needed to craft itself')
			end

			local new_craft_list = table_shallowcopy(craft_list)
			new_craft_list[#new_craft_list+1] = _item_name

			local missing_found = self:calculateMissingItems(_item_name, amount_needed, new_craft_list)
			for _,item in ipairs(missing_found) do
				table.insert(missing_items, item)
			end
		end
	end

	return missing_items
end

local CRAFTING_NODE_STATUS = {
	WAITING = "waiting",
	CRAFTING = "crafting",
	FINISHED = "finished",
	FAILED = "failed",
}

function CraftingCluster:createCraftingTree(item_name, amount, craft_list)
	local crafting_tree = {
		this = {
			recipe = nil,
			count = nil,
			status = CRAFTING_NODE_STATUS.WAITING,
		},
		children = {},
	}
	craft_list = craft_list or {}

	-- find available crafting
	local recipes = self.item_recipes[item_name] or error('No recipes found for '..item_name)
	local recipe = recipes[1]

	local output_crafted = 0

	-- Getting how many items are needed for each crafing.
	local inputs_needed = {}
	for _,slot_data in pairs(recipe.slots) do
		if slot_data.type == SLOT_TYPE.INPUT then
			inputs_needed[slot_data.item_name] = (inputs_needed[slot_data.item_name] or 0) + slot_data.amount

		elseif slot_data.item_name == item_name and slot_data.type == SLOT_TYPE.OUTPUT then
			output_crafted = output_crafted + slot_data.amount
		end
	end

	-- Findind out now many crafting actions will be necessary.
	local crafting_count = math.ceil(amount/output_crafted)

	crafting_tree.this.recipe = recipe
	crafting_tree.this.count = crafting_count

	-- Recursively crafting necessaty items, if they are not already in inventory.
	for _item_name,amount_needed in pairs(inputs_needed) do
		amount_needed = amount_needed * crafting_count

		local total_stored = table_reduce(
			table_map(
				self.storage_clusters,
				function(cluster) return cluster:availableItemCount(_item_name) end),
			function(a, b) return a + b end, 0)

		if total_stored < amount_needed then
			if array_contains(craft_list, _item_name) then
				error('More '.._item_name..' needed to craft itself')
			end

			local new_craft_list = table_shallowcopy(craft_list)
			new_craft_list[#new_craft_list+1] = _item_name

			table.insert(crafting_tree.children, self:createCraftingTree(_item_name, amount_needed, new_craft_list))
		end
	end

	return crafting_tree
end

function CraftingCluster:findAvailableCraftingInventories(profile_id)
	local profile = self.profiles[profile_id]

	if not profile then
		error('Profile '..profile_id..' not found in cluster '..self.name)
	end

	local inv_type = profile.inv_type

	local invs = self.invs
	invs = array_filter(invs, function(inv) return inventory_type(inv.name) == inv_type end)
	invs = array_filter(invs, function(inv) return inv.status == INV_CRAFTING_STATUS.IDLE end)
	if profile.whitelist_invs then
		invs = array_filter(invs, function(inv) return profile.whitelist_invs[inv.name] end)
	elseif profile.blacklist_invs then
		invs = array_filter(invs, function(inv) return not profile.blacklist_invs[inv.name] end)
	end

	return invs
end

function CraftingCluster:executeCraftingNode(crafting_node)
	local function craft()
		local recipe = crafting_node.this.recipe
		local total_crafting_count = crafting_node.this.count
		local profile_id = recipe.profile

		local invs = self:findAvailableCraftingInventories(profile_id)

		if #invs == 0 then
			crafting_node.status = CRAFTING_NODE_STATUS.FAILED
			error('No available crafting inventories found in '..self.name..' for crafting '..recipe.name..' in profile '..self.profiles[profile_id].name)
		end

		local function distributeEvenly(total, bins)
			local result = {}
			local each = math.floor(total / bins)
			local remainder = total % bins

			for i = 1, bins do
				if remainder > 0 then
					result[i] = each + 1
					remainder = remainder - 1
				else
					result[i] = each
				end
			end

			return result
		end

		local function executeCraftingForInventory(inv, crafting_count)
			self.log.info('Executing crafting recipe '..recipe.name.. ' x'..crafting_count)

			local total_craftings_issued = 0
			while total_craftings_issued < crafting_count do
				inv:startRecipe(recipe, self.storage_clusters)

				if inv:executeRecipe(recipe, self.storage_clusters) == 0 then
					crafting_node.status = CRAFTING_NODE_STATUS.FAILED
					error('No craftings issued for inventory '..inv.name)
				end

				inv:awaitRecipe()
				inv:finishRecipe()

				total_craftings_issued = total_craftings_issued + 1
			end

			self.log.info('Finished crafting recipe '..recipe.name.. ' x'..crafting_count)
		end

		local distributed_crafting_counts = distributeEvenly(total_crafting_count, #invs)
		parallel.waitForAll(table.unpack(array_map(invs, function(inv, i)
			return function()
				local count_for_this_inv = distributed_crafting_counts[i]
				executeCraftingForInventory(inv, count_for_this_inv)
			end
		end)))
	end

	if #crafting_node.children == 0 then
		crafting_node.status = CRAFTING_NODE_STATUS.CRAFTING
		craft()
		if crafting_node.status == CRAFTING_NODE_STATUS.FAILED then
			return
		end
		crafting_node.status = CRAFTING_NODE_STATUS.FINISHED
	else
		local all_finished = false
		while not all_finished do
			all_finished = true
			for _,child in ipairs(crafting_node.children) do
				if child.status ~= CRAFTING_NODE_STATUS.FINISHED then
					all_finished = false
				end
			end

			for _,child in ipairs(crafting_node.children) do
				if child.status == CRAFTING_NODE_STATUS.FAILED then
					crafting_node.status = CRAFTING_NODE_STATUS.FAILED
					return
				end
			end
			os.sleep(0)
		end

		crafting_node.status = CRAFTING_NODE_STATUS.CRAFTING
		craft()
		if crafting_node.status == CRAFTING_NODE_STATUS.FAILED then
			return
		end
		crafting_node.status = CRAFTING_NODE_STATUS.FINISHED
	end
end

function CraftingCluster:executeCraftingTree(crafting_tree)
	local function collectAllNodes(node, all_nodes)
		table.insert(all_nodes, node)
		for _, child in ipairs(node.children) do
			collectAllNodes(child, all_nodes)
		end
	end

	local all_nodes = {}
	collectAllNodes(crafting_tree, all_nodes)

	parallel.waitForAll(
		table.unpack(array_map(all_nodes, function(node) return function() self:executeCraftingNode(node) end end))
	)
end

function CraftingCluster:waitCrafting(inv, to_slot, item_name, amount)
	-- TODO: Implement 'AbstractSlot:itemCount(item_name)' (with the 'item_name' argument).
	while to_slot:itemCount(item_name) < amount do
		inv:refresh()
		os.sleep(0)
	end

	self.log.info('Crafted '..amount..' '..item_name)
end

-- Returning classes.
return {
	CraftingProfile = CraftingProfile,
	CraftingCluster = CraftingCluster,
}
