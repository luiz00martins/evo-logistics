---@diagnostic disable: need-check-nil
local utils = require('/logos.utils')
local core = require('/logos.logistics.storage.core')
local standard = require('/logos.logistics.storage.standard')

local get_connected_inventories = utils.get_connected_inventories
local array_unique = utils.array_unique
local array_map = utils.array_map
local table_map = utils.table_map
local table_reduce = utils.table_reduce
local table_shallowcopy = utils.table_shallowcopy
local array_contains = utils.array_contains
local array_filter = utils.array_filter
local inventory_type = utils.inventory_type
local new_class = utils.new_class

local StandardCluster = standard.StandardCluster
local transfer = core.transfer

-- Crafting Profile Class

local CraftingProfile = {}
CraftingProfile.__index = CraftingProfile

function CraftingProfile:new(args)
	-- These arguments must be passed.
	if args.name == nil then error("parameter missing `name`") end
	if args.inv_type == nil then error("parameter missing `inv_type`") end

	if not args.inv_size then
		-- Finding out size.
		local inventories = get_connected_inventories()
		for _,inv_name in ipairs(inventories) do
			local inv_type = inventory_type(inv_name)

			if inv_type == args.inv_type then
				args.inv_size = peripheral.call(inv_name, "size")
				break
			end
		end

		if not args.inv_size then
			error('Could not probe an inventory of type '..args.inv_type)
		end
	end

	local newCraftingProfile =  {
		name = args.name,
		inv_type = args.inv_type,
		inv_size = args.inv_size,
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
		inv_size = self.inv_size,
	}

	return serialized
end

function CraftingProfile:fromSerialized(serialized)
	local unserialized = textutils.unserialize(serialized)

	local newCraftingProfile = CraftingProfile:new{
		name = unserialized.name,
		recipes = unserialized.recipes,
		inv_type = unserialized.inv_type,
		inv_size = unserialized.inv_size,
	}

	return newCraftingProfile
end

function CraftingProfile:addRecipe(recipe)
	if not recipe.name then error('Recipe missing ´name´') end
	if not recipe.slots then error('Recipe '..recipe.name..' missing `slots`') end

	-- Checking slots.
	for _,slot_data in pairs(recipe.slots) do
		if not slot_data.item_name then error('not item_name provided in crafting slot') end
		if not slot_data.amount then error('not amount provided in crafting slot') end
		if not slot_data.type then error('not type provided in crafting slot') end

		if slot_data.type ~= 'input' and slot_data.type ~= 'output' then error('invalid crafting slot type provided ('..tostring(slot_data.type)..')') end
	end

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


local CraftingCluster = new_class(StandardCluster)

function CraftingCluster:new(args)
	local newCraftingCluster = StandardCluster:new(args)

	newCraftingCluster.storage_clusters = args.storage_clusters
	newCraftingCluster.profiles = {}
	newCraftingCluster.item_recipes = {}
	newCraftingCluster.recipe_profiles = {}

	setmetatable(newCraftingCluster, self)
	return newCraftingCluster
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
		self:registerInventory{inv_name = inv_name}
	end

	return true
end

function CraftingCluster:_addProfileData(profile)
	for _,recipe in ipairs(profile.recipes) do
		for _,slot_data in pairs(recipe.slots) do
			if slot_data.type == 'output' then
				local item_name = slot_data.item_name
				self.item_count[item_name] = 0

				self.item_recipes[item_name] = self.item_recipes[item_name] or {}
				self.item_recipes[item_name][#self.item_recipes[item_name]+1] = recipe
			end
		end

		self.recipe_profiles[recipe] = profile
	end
end

function CraftingCluster:addProfile(profile)
	if array_contains(self.profiles, profile) then
		error('Profile'..profile.name..' already present in cluster '..self.name)
	end

	self:_addProfileData(profile)
	self.profiles[#self.profiles+1] = profile
end

function CraftingCluster:refresh()
	StandardCluster.refresh(self)
	self.item_recipes = {}
	self.recipe_profiles = {}

	for _,profile in ipairs(self.profiles) do
		self:_addProfileData(profile)
	end
end

CraftingCluster.catalog = CraftingCluster.refresh

function CraftingCluster:itemNames()
	local item_names = {}

	for _,profile in ipairs(self.profiles) do
		for _,recipe in ipairs(profile.recipes) do
			for _,slot_data in pairs(recipe.slots) do
				if slot_data.type == 'output' then
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
		if slot_data.type == 'input' then
			inputs_needed[slot_data.item_name] = (inputs_needed[slot_data.item_name] or 0) + slot_data.amount

		elseif slot_data.item_name == item_name and slot_data.type == 'output' then
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
		if slot_data.type == 'input' then
			inputs_needed[slot_data.item_name] = (inputs_needed[slot_data.item_name] or 0) + slot_data.amount

		elseif slot_data.item_name == item_name and slot_data.type == 'output' then
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

	local inputs = table_map(recipe.slots, function(slot) if slot.type == 'input' then return slot end end)
	local outputs = table_map(recipe.slots, function(slot) if slot.type == 'output' then return slot end end)

	-- TODO: Right now, you get all of the item outputs before putting a new one. If you put the input item before proceding to the next ones, you can accelerate things quite a bit.
	-- Executing crafting recipe.
	for curr_count=1,crafting_count,#invs do
		local executions = math.min(crafting_count-curr_count+1, #invs)

		-- Starting up craftings.
		for i=1,executions do
			local inv = invs[i]

			inv:refresh()
			for j,slot_data in pairs(inputs) do
				local amount_pulled = 0
				local amount_needed = slot_data.amount

				for _,cluster in ipairs(self.storage_clusters) do
					if amount_pulled < amount_needed and cluster:itemIsAvailable(slot_data.item_name) then

						local toState = inv.states[j]
						amount_pulled = amount_pulled + transfer(cluster, toState, cluster, self, slot_data.item_name, amount_needed-amount_pulled)
						--amount_pulled = amount_pulled + cluster:move(fromState, self, toState, amount_needed-amount_pulled)
					end
				end
			end
		end

		-- Finishing craftings.
		for i=1,executions do
			local inv = invs[i]

			for j,slot in pairs(outputs) do
				local output_state = inv.states[j]
				-- Waiting for crafting.
				self:waitCrafting(inv, output_state, slot.item_name, slot.amount)

				-- Removing crafted items.
				for _,cluster in ipairs(self.storage_clusters) do
					if output_state:hasItem() and cluster:inputState(slot.item_name) then
						transfer(output_state, cluster, self, cluster)
					end
				end
				if output_state:hasItem() then
					error('Could not export item '..output_state:itemName())
				end
			end
		end
	end
end

function CraftingCluster:waitCrafting(inv, to_state, item_name, amount)
	-- TODO: Implement 'AbstractState:itemCount(item_name)' (with the 'item_name' argument).
	while to_state:itemCount() < amount do
		inv:refresh()
		os.sleep(0)
	end
end

-- Returning classes.
return {
	CraftingProfile = CraftingProfile,
	CraftingCluster = CraftingCluster,
}
