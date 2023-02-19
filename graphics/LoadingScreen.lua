require "UIContainer"
require "UIText"

-- FIXME: Change this to basalt
class "LoadingScreen" extends "UIContainer" {
	steps = nil,
	current_step = 1,
	textbox = nil,
	finish_callback = nil,
}

local TERMINAL_WIDTH, TERMINAL_HEIGHT = term.getSize()

function LoadingScreen:init(finish_callback, steps)
	self.super:init(0, 0, TERMINAL_WIDTH, TERMINAL_HEIGHT)

	self.textbox = self:addChild( UIText(0, 0, self.width, self.height, "@ac@tbLogistics\n\n"))
	self.textbox.alignment = 'centre'

	-- Formatting text
	for _,job in ipairs(steps) do
		job.text = '@tf@ac'..job.text..'\n'
	end

	self.steps = steps
	self.finish_callback = finish_callback

	if #self.steps > 0 then
		self.textbox.text = self.textbox.text..self.steps[1].text
	end
end

function LoadingScreen:runNext()
	local task = self.steps[self.current_step]

	if task.before_callback then
		task.before_callback()
	end

	local return_value = task.job()

	if task.after_callback then
		task.after_callback()
	end

	self.current_step = self.current_step + 1
	local next_task = self.steps[self.current_step]
	if not next_task then
		self:remove()
		self.finish_callback()

		self.textbox.text = self.textbox.text..'Done.\n'
		self:draw()
	else
		self.textbox.text = self.textbox.text..next_task.text
		self:draw()
	end

	return return_value
end
