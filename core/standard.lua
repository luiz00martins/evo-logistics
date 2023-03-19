local shaped = require('/logos-library.core.shaped')

local new_class = require('/logos-library.utils.class').new_class

local StandardSlot = new_class(shaped.ShapedSlot)
local StandardInventory = new_class(shaped.ShapedInventory)
local StandardCluster = new_class(shaped.ShapedCluster)

return {
	StandardSlot = StandardSlot,
	StandardInventory = StandardInventory,
	StandardCluster = StandardCluster
}
