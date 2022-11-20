require "UIContainer"

local TERMINAL_WIDTH, TERMINAL_HEIGHT = term.getSize()

class "Page" extends "UIContainer" {

}

function Page:init()
	self.super:init(0, 1, TERMINAL_WIDTH, TERMINAL_HEIGHT-1)
end

