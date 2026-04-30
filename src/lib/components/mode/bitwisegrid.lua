local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local Grid = require(path_name .. 'grid')

local BitwiseGrid = ModeComponent:new({})
BitwiseGrid.__base = ModeComponent
BitwiseGrid.name = 'Bitwise Grid'

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function BitwiseGrid:set(o)
	self.__base.set(self, o)
	self.component = 'input'
	self.track = o.track or 1
	self.selection = o.selection or 1
	self.playhead = o.playhead or 1
	self.lane = 'note' -- note, vel
	self.shift_direction = o.shift_direction or 'left'
	self.lock_tool = o.lock_tool or 'toggle_selected'

	self.grid = Grid:new({
		name = 'BitwiseGrid ' .. self.track,
		grid_start = { x = 1, y = 1 },
		grid_end = { x = 8, y = 8 },
		display_start = { x = 1, y = 1 },
		display_end = { x = 8, y = 8 },
		offset = { x = 0, y = 0 },
		midi = App.midi_grid,
	})
end

function BitwiseGrid:is_active(input)
	input = input or self:get_component()
	return input
		and input.note ~= nil
		and input.vel ~= nil
		and self.track
		and App.track[self.track]
		and App.track[self.track].input_type == 'bitwise'
end

function BitwiseGrid:current_step()
	return self.selection
end

function BitwiseGrid:get_lane(input, lane)
	if not input then return nil end
	lane = lane or self.lane
	if lane == 'note' then
		return input.note
	elseif lane == 'vel' then
		return input.vel
	end
	return nil
end

function BitwiseGrid:set_lane(lane)
	if lane == 'note' or lane == 'vel' then
		self.lane = lane
		self:set_grid(self:get_component())
		App.screen_dirty = true
	end
end

function BitwiseGrid:ensure_duration_lane(input)
	-- Duration lane removed pending further QC.
end

function BitwiseGrid:cycle(direction)
	local input = self:get_component()
	if not self:is_active(input) then return end
	self:ensure_duration_lane(input)
	local reverse = direction == 'right'
	input.note:cycle(reverse)
	input.vel:cycle(reverse)
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:reseed()
	local input = self:get_component()
	if not self:is_active(input) then return end
	self:ensure_duration_lane(input)
	input.note:seed()
	input.vel:seed()
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:clear()
	local input = self:get_component()
	if not self:is_active(input) then return end
	self:ensure_duration_lane(input)
	input.note:seed(0)
	input.vel:seed(0)
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:apply_lock_tool()
	local input = self:get_component()
	if not self:is_active(input) then return end
	self:ensure_duration_lane(input)
	local step = self:current_step()

	if self.lock_tool == 'toggle_selected' then
		local state = not input.note.lock[step]
		input.note.lock[step] = state
		input.vel.lock[step] = state
	elseif self.lock_tool == 'lock_all' then
		for i = 1, input.track.bitwise_length do
			input.note.lock[i] = true
			input.vel.lock[i] = true
		end
	elseif self.lock_tool == 'unlock_all' then
		for i = 1, input.track.bitwise_length do
			input.note.lock[i] = false
			input.vel.lock[i] = false
		end
	end
	input.note:update()
	input.vel:update()
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:adjust_selected(delta)
	local input = self:get_component()
	if not self:is_active(input) then return end
	self:ensure_duration_lane(input)
	local step = self:current_step()
	local lane = self:get_lane(input, self.lane)
	if not lane then return end

	if lane.triggers[step] ~= true then lane:flip(step) end
	lane.lock[step] = true
	lane.values[step] = clamp((lane.values[step] or 0) + (delta * 0.02), 0, 1)
	lane:update()
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:set_step(step)
	local input = self:get_component()
	if not self:is_active(input) then return end
	step = clamp(step, 1, input.track.bitwise_length)
	self.selection = step
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:move_selection(delta)
	local input = self:get_component()
	if not self:is_active(input) then return end
	local next = clamp(self.selection + delta, 1, input.track.bitwise_length)
	self.selection = next
	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:grid_event(input, data)
	if not self:is_active(input) or data.type ~= 'pad' or not data.state then return end
	self:ensure_duration_lane(input)
	local step = self.grid:grid_to_index(data)
	if not step then return end
	if step > input.track.bitwise_length then return end

	self:set_step(step)

	if self.mode.alt then
		self.lock_tool = 'toggle_selected'
		self:apply_lock_tool()
		return
	end

	local has_trigger = input.note.triggers[step] == true
	local is_locked = input.note.lock[step] == true

	-- Match legacy lock_note semantics:
	-- 1) no trigger -> enable trigger + lock
	-- 2) trigger + unlocked -> lock
	-- 3) trigger + locked -> disable trigger + unlock
	if not has_trigger then
		input.note:flip(step)
		input.note.lock[step] = true
		input.vel.lock[step] = true
	elseif has_trigger and not is_locked then
		input.note.lock[step] = true
		input.vel.lock[step] = true
	else
		input.note:flip(step)
		input.note.lock[step] = false
		input.vel.lock[step] = false
	end

	self:set_grid(input)
	App.screen_dirty = true
end

function BitwiseGrid:row_event(data)
	if data and data.state and data.row then
		self.track = data.row
		self:set_grid(self:get_component())
		App.screen_dirty = true
	end
end

function BitwiseGrid:transport_event(input, data)
	if not self.mode or not self.mode.enabled then return end
	if not self:is_active(input) then return end
	if data and data.type == 'clock' then
		self.playhead = input.index or 1
		self:set_grid(input)
		App.screen_dirty = true
	end
end

function BitwiseGrid:set_grid(input)
	local grid = self.grid
	if not grid then return end
	grid:for_each(function(s, x, y) s.led[x][y] = 0 end)

	if not self:is_active(input) then
		grid:refresh('BitwiseGrid inactive')
		return
	end

	self:ensure_duration_lane(input)
	local playhead = self.playhead or input.index or 1
	local length = input.track.bitwise_length

	for step = 1, length do
		local pos = grid:index_to_grid(step)
		if pos then
			local trig = input.note.triggers[step] == true
			local locked = input.note.lock[step] == true
			local color = 0
			if trig then color = { 24, 24, 24 } end
			if locked then color = { 127, 0, 0 } end
			if step == playhead and App.playing then color = { 127, 127, 127 } end
			grid.led[pos.x][pos.y] = color
		end
	end

	grid:refresh('BitwiseGrid:set_grid')
end

function BitwiseGrid:draw()
	local input = self:get_component()
	screen.level(15)
	screen.move(1, 8)
	screen.text('BITWISE')

	if not self:is_active(input) then
		screen.level(5)
		screen.move(1, 20)
		screen.text('Set track input type to bitwise')
		return
	end

	self:ensure_duration_lane(input)
	local step = self:current_step()
	local note = input.note:get(step)
	local vel = input.vel:get(step)

	screen.level(10)
	screen.move(1, 20)
	screen.text('step ' .. step .. '/' .. input.track.bitwise_length)
	screen.move(72, 20)
	screen.text('lane ' .. self.lane)

	screen.level(15)
	screen.move(1, 30)
	screen.text('note ' .. tostring(note.value))
	screen.move(1, 40)
	screen.text('vel ' .. tostring(vel.value))
	screen.move(1, 50)
	screen.text('dur ' .. tostring(math.max(1, input.track.step_length)) .. ' tks')

	screen.level(8)
	screen.move(72, 30)
	screen.text('chance ' .. math.floor(input.track.chance * 100) .. '%')
	screen.move(72, 40)
	screen.text('len ' .. tostring(input.track.bitwise_length))
	screen.move(72, 50)
	screen.text(input.note.lock[step] and 'locked' or 'free')

	local margin = 3
	local spacing = 7
	local values_height = 41

	-- Note range guides.
	screen.level(1)
	screen.rect(0, 54, 116, 1)
	screen.rect(0, 8, 116, 1)
	screen.fill()

	for i = 1, input.track.bitwise_length do
		local x = (i - 1) * spacing + margin
		local active = input.note.triggers[i] == true
		local is_playhead = (i == (input.index or 1)) and App.playing
		local is_selected = (i == step)

		if active then
			-- Trigger marker at bottom.
			if input.note.lock[i] then
				screen.level(is_playhead and 15 or 5)
				screen.rect(x, 57, 5, 5)
				screen.fill()
			else
				screen.level(is_playhead and 15 or 5)
				screen.rect(x + 1, 58, 4, 4)
				screen.stroke()
			end

			-- Velocity as vertical bar.
			local vel_h = math.floor((input.vel.values[i] or 0) * values_height)
			screen.level(is_playhead and 2 or 1)
			screen.rect(x + 1, 53 - vel_h, 3, vel_h)
			screen.fill()

			-- Note value as horizontal bar height.
			local note_y = 51 - math.floor((input.note.values[i] or 0) * values_height)

			-- Duration as horizontal width (ticks -> step units).
			local width = 5

			screen.level((is_playhead or is_selected) and 15 or 5)
			screen.rect(x, note_y, width, 2)
			screen.fill()
		else
			screen.level(2)
			screen.pixel(x + 2, 58)
			screen.fill()
		end
	end
end

return BitwiseGrid
