local utils = require('/logos-library.utils.utils')

local shapeless = require('/logos-library.core.shapeless')

local BarrelInventory = utils.new_class(shapeless.ShapelessInventory)
local BarrelCluster = utils.new_class(shapeless.ShapelessCluster)

return {
	BarrelInventory = BarrelInventory,
	BarrelCluster = BarrelCluster
}
