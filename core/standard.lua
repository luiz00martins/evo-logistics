local utils = require('/logos-library.utils.utils')

local shaped = require('/logos-library.core.shaped')

local StandardSlot = utils.new_class(shaped.ShapedSlot)
local StandardInventory = utils.new_class(shaped.ShapedInventory)
local StandardCluster = utils.new_class(shaped.ShapedCluster)

return {
	StandardSlot = StandardSlot,
	StandardInventory = StandardInventory,
	StandardCluster = StandardCluster
}
