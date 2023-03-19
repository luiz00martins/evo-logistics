---@diagnostic disable: need-check-nil
local utils = require('/logos-library.utils.utils')
local inv_utils = require('/logos-library.utils.inventories')
local abstract = require('/logos-library.core.abstract')
local shaped = require('/logos-library.core.shaped')
local shapeless = require('/logos-library.core.shapeless')

local new_class = require('/logos-library.utils.class').new_class
local array_unique = utils.array_unique
local array_map = utils.array_map
local table_map = utils.table_map
local table_reduce = utils.table_reduce
local table_values = utils.table_values
local table_shallowcopy = utils.table_shallowcopy
local table_contains = utils.table_contains
local array_contains = utils.array_contains
local array_filter = utils.array_filter
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

		if not table_contains(table_values(SLOT_TYPE), slot_data.type) then error('invalid crafting slot type provided ('..tostring(slot_data.type)..')') end
	end

	local new_recipe = {
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

	local newCraftingProfile =  {
		name = args.name,
		inv_type = args.inv_type,
		recipes = args.recipes or {}
	}

	setmetatable(newCraftingProfile, self)
	return newCraftingProfile
end

function CraftingProfile:serialize()
	local serialized = textutils.serialize{
		name = self.name,
		recipes = self.recipes,
		inv_type = self.inv_type,
	}

	return serialized
end

function CraftingProfile:fromSerialized(serialized)
	local unserialized = textutils.unserialize(serialized)

	local newCraftingProfile = CraftingProfile:new{
		name = unserialized.name,
		recipes = unserialized.recipes,
		inv_type = unserialized.inv_type,
	}

	return newCraftingProfile
end

function CraftingProfile:addRecipe(recipe_args)
	if not recipe_args.is_shaped then
		recipe_args.is_shaped = is_shaped(self.inv_type)
	end

	local recipe = CraftingRecipe:new(recipe_args)

	self.recipes[#self.recipes+1] = recipe
end

function CraftingProfile:removeRecipe(name)
	for i,recipe in ipairs(self.recipes) do
		if recipe.name == name then
			table.remove(self.recipes, i)
			return
		end
	end

	error('No recipe '..name..' found')
end


local CRAFTING_STATUS = {
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

	new_inventory.status = CRAFTING_STATUS.IDLE

	return new_inventory
end

function ShapedCraftingInventory:startRecipe(recipe, storage_clusters)
	if self.status ~= CRAFTING_STATUS.IDLE then
		error('Already started a recipe for '..self.executing_recipe.name)
	end

	self.executing_recipe = recipe
	self.storage_clusters = storage_clusters

	local templates = table_map(recipe.slots, function(slot) if slot.type == SLOT_TYPE.TEMPLATE then return slot end end)

	self:_retrieveItems(templates)

	self.status = CRAFTING_STATUS.TEMPLATED
end
ShapelessCraftingInventory.startRecipe = ShapedCraftingInventory.startRecipe

function ShapedCraftingInventory:executeRecipe()
	if self.status == CRAFTING_STATUS.IDLE then
		error('No recipe to execute')
	elseif self.status == CRAFTING_STATUS.EXECUTING then
		error('Already executing recipe for '..self.executing_recipe.name)
	end

	local inputs = table_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.INPUT then return slot end end)
	self:_retrieveItems(inputs)

	self.status = CRAFTING_STATUS.CRAFTING
end
ShapelessCraftingInventory.executeRecipe = ShapedCraftingInventory.executeRecipe

function ShapedCraftingInventory:awaitRecipe()
	if self.status == CRAFTING_STATUS.IDLE then
		error('No recipe to await')
	elseif self.status == CRAFTING_STATUS.TEMPLATED
			or self.status == CRAFTING_STATUS.CRAFTED then
		return
	end

	local outputs = table_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)

	for j,slot_data in pairs(outputs) do
		local output_slot = self.slots[j]

		repeat
			self:refresh()
			os.sleep(0)
		until output_slot:itemCount() >= slot_data.amount
	end

	self.status = CRAFTING_STATUS.CRAFTED
end

function ShapelessCraftingInventory:awaitRecipe()
	if self.status == CRAFTING_STATUS.IDLE then
		error('No recipe to await')
	elseif self.status == CRAFTING_STATUS.TEMPLATED
			or self.status == CRAFTING_STATUS.CRAFTED then
		return
	end

	local outputs = table_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)

	for _,slot_data in pairs(outputs) do
		repeat
			self:refresh()
			os.sleep(0)
		-- WARNING: We do not check for the amount of items (as there's no way to guarantee it for shapeless slots), only the existence of it.
		until self:hasItem(slot_data.item_name)
		utils.log(slot_data.item_name..':'..utils.tostring(self:hasItem(slot_data.item_name)))
	end

	self.status = CRAFTING_STATUS.CRAFTED
end

function ShapedCraftingInventory:finishRecipe()
	local outputs = table_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.OUTPUT then return slot end end)
	self:_dispatchItems(outputs)

	local templates = table_map(self.executing_recipe.slots, function(slot) if slot.type == SLOT_TYPE.TEMPLATE then return slot end end)
	self:_dispatchItems(templates)

	self.status = CRAFTING_STATUS.IDLE

	self.executing_recipe = nil
	self.storage_clusters = nil
end
ShapelessCraftingInventory.finishRecipe = ShapedCraftingInventory.finishRecipe

function ShapedCraftingInventory:_retrieveItems(slots_data)
	self:refresh()

	for j,slot_data in pairs(slots_data) do
		local amount_pulled = 0
		local amount_needed = slot_data.amount

		for _,cluster in ipairs(self.storage_clusters) do
			if amount_pulled < amount_needed and cluster:itemIsAvailable(slot_data.item_name) then

				local toSlot = self.slots[j]
				amount_pulled = amount_pulled + transfer(cluster, toSlot, slot_data.item_name, amount_needed-amount_pulled)
			end
		end

		if amount_pulled < amount_needed then
			error('Not enough '..slot_data.item_name..' to execute recipe '..self.executing_recipe.name..' ('..amount_pulled..'/'..amount_needed..')')
		end
	end
end

function ShapelessCraftingInventory:_retrieveItems(slots_data)
	self:refresh()

	for _,slot_data in ipairs(slots_data) do
		local amount_pulled = 0
		local amount_needed = slot_data.amount

		for _,cluster in ipairs(self.storage_clusters) do
			if amount_pulled < amount_needed and cluster:itemIsAvailable(slot_data.item_name) then

				amount_pulled = amount_pulled + transfer(cluster, self, slot_data.item_name, amount_needed-amount_pulled)
			end
		end

		if amount_pulled < amount_needed then
			error('Not enough '..slot_data.item_name..' to execute recipe '..self.executing_recipe.name..' ('..amount_pulled..'/'..amount_needed..')')
		end
	end
end

function ShapedCraftingInventory:_dispatchItems(slots_data)
	self:refresh()

	for j,_ in pairs(slots_data) do
		local output_slot = self.slots[j]

		-- Removing crafted items.
		for _,cluster in ipairs(self.storage_clusters) do
			if output_slot:hasItem() then
				transfer(output_slot, cluster)
			else
				break
			end
		end

		if output_slot:hasItem() then
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
				moved = moved + transfer(self, cluster, slot_data.item_name, slot_data.amount-moved)
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
	new_cluster.recipe_profiles = {}

	setmetatable(new_cluster, CraftingCluster)
	return new_cluster
end

CraftingCluster._getPriority = _getPriority

function CraftingCluster:dataPath()
	return "/logistics_data/"..self.name..".data"
end

function CraftingCluster:saveData()
	local profiles = array_map(self.profiles, function(profile) return profile:serialize() end)

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
	for _,serialized_profile in ipairs(data.profiles) do
		local profile = CraftingProfile:fromSerialized(serialized_profile)
		profiles[#profiles+1] = profile
	end

	self.profiles	= profiles
	self.invs	= {}
	for _,inv_name in ipairs(data.inv_names) do
		if peripheral.isPresent(inv_name) then
			self:registerInventory{name = inv_name}
		else
			utils.log("Inventory "..inv_name.." is no longer present")
		end
	end

	return true
end

function CraftingCluster:registerInventory(args)
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

function CraftingCluster:_addProfileData(profile)
	for _,recipe in ipairs(profile.recipes) do
		self.recipe_profiles[recipe] = profile

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
end

function CraftingCluster:addProfile(profile)
	local profile_names = array_map(self.profiles, function(_profile) return _profile.name end)
	if array_contains(profile_names, profile.name) then
		error('Profile'..profile.name..' already present in cluster '..self.name)
	end

	self:_addProfileData(profile)
	self.profiles[#self.profiles+1] = profile
end

function CraftingCluster:_createInventory(args)
	return CraftingInventory:new{
		parent = self,
		name = args.inv_name or error('argument `inv_name` not provided'),
	}
end

function CraftingCluster:_refreshInternals()
	self.item_recipes = {}
	self.recipe_profiles = {}

	for _,profile in ipairs(self.profiles) do
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

	for _,profile in ipairs(self.profiles) do
		for _,recipe in ipairs(profile.recipes) do
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

function CraftingCluster:createCraftingTree(item_name, amount, craft_list)
	local crafting_tree = {
		this = {
			recipe = nil,
			count = nil,
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


function CraftingCluster:executeCraftingTree(crafting_tree)
	for _,ct in ipairs(crafting_tree.children) do
		self:executeCraftingTree(ct)
	end

	local recipe = crafting_tree.this.recipe
	local crafting_count = crafting_tree.this.count
	local profile = self.recipe_profiles[recipe]
	local inv_type = profile.inv_type
	local invs = array_filter(self.invs, function(inv) if inventory_type(inv.name) == inv_type then return true end end)

	if #invs == 0 then
		error('No inventories of type '..inv_type..' found')
	end

	-- TODO: Right now, you get all of the item outputs before putting a new one. If you put the input item before proceding to the next ones, you can accelerate things quite a bit.
	-- Executing crafting recipe.
	for curr_count=1,crafting_count,#invs do
		local executions = math.min(crafting_count-curr_count+1, #invs)

		-- NOTE: We separate the starting and finishing of craftings to allow it them to run in parallel. Once real parallelization is available, this can be removed.

		-- Starting up craftings.
		for i=1,executions do
			local inv = invs[i]

			if inv.status == CRAFTING_STATUS.IDLE then
				inv:startRecipe(recipe, self.storage_clusters)
			end

			inv:executeRecipe()
		end

		-- Awaiting craftings.
		for i=1,executions do
			local inv = invs[i]

			inv:awaitRecipe()
			inv:finishRecipe()
		end
	end
end

function CraftingCluster:waitCrafting(inv, to_slot, item_name, amount)
	-- TODO: Implement 'AbstractSlot:itemCount(item_name)' (with the 'item_name' argument).
	while to_slot:itemCount(item_name) < amount do
		inv:refresh()
		os.sleep(0)
	end

	utils.log('Crafted '..amount..' '..item_name)
end

-- Returning classes.
return {
	CraftingProfile = CraftingProfile,
	CraftingCluster = CraftingCluster,
}
