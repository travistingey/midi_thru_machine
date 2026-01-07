local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local UI = require(path_name .. 'ui')

local BufferSeq = ModeComponent:new()
BufferSeq.__base = ModeComponent
BufferSeq.name = 'bufferseq'

local max_step_length = App.ppqn * 16 -- 4 bars
local min_step_length = App.ppqn / 8 -- 1/32th note
local max_ticks = max_step_length * 64

function BufferSeq:set(o)
	self.__base.set(self, o)
	self.active = true
	self.index = nil
	self.component = 'auto'

	-- Buffer-only lane
	self.selected_lane = 'buffer'
	-- step_length is now read from track's auto.buffer_step_length
	-- This allows different tracks to have different step lengths
	self.display_offset = o.display_offset or 0

	self.grid = Grid:new({
		name = 'BufferSeq ' .. o.track,
		grid_start = o.grid_start or { x = 1, y = 8 },
		grid_end = o.grid_end or { x = 8, y = 1 },
		display_start = o.display_start or { x = 1, y = 1 },
		display_end = o.display_end or { x = 8, y = 8 },
		offset = o.offset or { x = 0, y = 0 },
		midi = App.midi_grid,
	})

	self.row_length = self.grid.bounds.width
	-- row_ticks and display_ticks will be calculated in recalculate_display
	-- after we can access the track's buffer_step_length

	self.display_length = self.grid.bounds.height * self.row_length
	self.step_offset = self.display_offset * self.row_length

	-- Scrub/loop playback state
	self.scrub_active = false
	self.scrub_start_tick = nil
	self.scrub_end_tick = nil
	self.scrub_saved_step = nil
	self.scrub_saved_seq_start = nil
	self.scrub_saved_seq_length = nil
	self.held_pads = {} -- Track currently held pads for multi-pad selection

	-- Initialize display calculations (will be recalculated when component is available)
	self.row_ticks = 0
	self.display_ticks = 0

	self.grid:refresh()

	self.context = {
		press_fn_3 = function() print('press_fn_3') end,
	}

	self.screen = function(text, completion)
		local has_menu = false
		if self.mode then has_menu = self.mode:has_active_menu() end

		if not has_menu then
			if self.scrub_active then
				UI:draw_tag(1, 36, 'scrub', self.scrub_start_tick .. '-' .. self.scrub_end_tick)
			else
				UI:draw_tag(1, 36, 'step', self.last_event)
			end
		end
	end
end

function BufferSeq:enable_event()
	-- No preset selection needed for buffer mode
	-- Initialize display calculations now that we can access the component
	self:recalculate_display()
end

-- Get current step_length from track's auto component
function BufferSeq:get_step_length()
	local auto = self:get_component()
	if auto and auto.buffer_step_length then return auto.buffer_step_length end
	return 24 -- fallback default
end

function BufferSeq:recalculate_display(previous_offset)
	local step_length = self:get_step_length()
	self.row_ticks = step_length * self.row_length
	local new_offset = step_length * self.display_length
	self.display_ticks = step_length * self.display_length + new_offset
	if previous_offset then
		self.display_offset = math.floor(previous_offset / step_length)
		self.step_offset = self.display_offset * self.row_length
	end
end

function BufferSeq:increase_step_length()
	local auto = self:get_component()
	if not auto then return end

	local current_step_length = auto.buffer_step_length or 24
	local current_display_offset = self.display_offset * current_step_length

	if current_step_length < max_step_length then
		if current_step_length == 1 then
			auto.buffer_step_length = 3
		else
			auto.buffer_step_length = current_step_length * 2
		end
		self:recalculate_display(current_display_offset)
		self:set_grid(auto)
		print('Buffer step length: ' .. auto.buffer_step_length .. ' ticks')
	end
end

function BufferSeq:decrease_step_length()
	local auto = self:get_component()
	if not auto then return end

	local current_step_length = auto.buffer_step_length or 24
	local current_display_offset = self.display_offset * current_step_length

	if current_step_length > min_step_length then
		auto.buffer_step_length = current_step_length / 2
		self:recalculate_display(current_display_offset)
		self:set_grid(auto)
		print('Buffer step length: ' .. auto.buffer_step_length .. ' ticks')
	elseif current_step_length <= min_step_length then
		auto.buffer_step_length = 1
		self:recalculate_display(current_display_offset)
		self:set_grid(auto)
		print('Buffer step length: ' .. auto.buffer_step_length .. ' ticks')
	end
end

function BufferSeq:increase_display_offset()
	local step_length = self:get_step_length()
	local new_offset = self.step_offset * step_length + self.display_ticks
	if new_offset < max_ticks then
		self.display_offset = self.display_offset + 1
		self.step_offset = self.display_offset * self.row_length
		self:set_grid(self:get_component())
	end
end

function BufferSeq:decrease_display_offset()
	if self.display_offset > 0 then
		self.display_offset = self.display_offset - 1
		self.step_offset = self.display_offset * self.row_length
		self:set_grid(self:get_component())
	end
end

-- Convert grid pad to tick range
function BufferSeq:pad_to_tick_range(pad_index)
	local step_length = self:get_step_length()
	local start_tick = (pad_index - 1) * step_length
	local end_tick = pad_index * step_length - 1
	return start_tick, end_tick
end

-- Start scrub playback from a pad
function BufferSeq:start_scrub(pad_index)
	local auto = self:get_component()
	local start_tick, end_tick = self:pad_to_tick_range(pad_index)

	-- Save current playback state
	self.scrub_saved_step = auto.step
	self.scrub_saved_seq_start = auto.seq_start
	self.scrub_saved_seq_length = auto.seq_length

	-- Set scrub range
	self.scrub_start_tick = start_tick
	self.scrub_end_tick = end_tick
	self.scrub_active = true

	-- Start scrub playback
	auto:start_scrub(start_tick, end_tick, App.buffer_scrub_loop)

	print('Scrub started: ' .. start_tick .. '-' .. end_tick .. (App.buffer_scrub_loop and ' (loop)' or ' (play-through)'))
end

-- Extend scrub range when holding multiple pads
function BufferSeq:extend_scrub(pad_index)
	local auto = self:get_component()
	local start_tick, end_tick = self:pad_to_tick_range(pad_index)

	-- Extend scrub range to include new pad
	self.scrub_start_tick = math.min(self.scrub_start_tick, start_tick)
	self.scrub_end_tick = math.max(self.scrub_end_tick, end_tick)

	-- Update scrub playback range
	auto:update_scrub(self.scrub_start_tick, self.scrub_end_tick)

	print('Scrub extended: ' .. self.scrub_start_tick .. '-' .. self.scrub_end_tick)
end

-- Stop scrub playback and restore normal playback
function BufferSeq:stop_scrub()
	if not self.scrub_active then return end

	local auto = self:get_component()

	-- Stop scrub and restore previous state
	auto:stop_scrub(self.scrub_saved_step, self.scrub_saved_seq_start, self.scrub_saved_seq_length)

	self.scrub_active = false
	self.scrub_start_tick = nil
	self.scrub_end_tick = nil
	self.scrub_saved_step = nil
	self.scrub_saved_seq_start = nil
	self.scrub_saved_seq_length = nil

	print('Scrub stopped')
end

function BufferSeq:grid_event(component, data)
	local grid = self.grid
	local auto = component
	local pad_index = self.grid:grid_to_index(data) + self.step_offset

	-- Update context/screen overlay
	if self.mode:has_active_menu() then
		self.mode:toast(self.last_event, self.screen, { timeout = 2 })
	else
		self.mode:use_context(self.context, self.screen, { timeout = true, interrupt = true })
	end
	self.last_event = pad_index

	-- Handle pad press (start scrub)
	if data.type == 'pad' and data.state then
		-- Track held pad
		self.held_pads[pad_index] = true

		-- Count held pads
		local held_count = 0
		for _ in pairs(self.held_pads) do
			held_count = held_count + 1
		end

		if held_count == 1 then
			-- First pad: start scrub
			self:start_scrub(pad_index)
		else
			-- Additional pad: extend scrub range
			self:extend_scrub(pad_index)
		end
	end

	-- Handle pad release
	if data.type == 'pad' and not data.state then
		-- Remove from held pads
		self.held_pads[pad_index] = nil

		-- Count remaining held pads
		local held_count = 0
		for _ in pairs(self.held_pads) do
			held_count = held_count + 1
		end

		if held_count == 0 then
			-- All pads released: stop scrub
			self:stop_scrub()
		end
	end

	-- Handle long press for loop point setting (alt mode)
	if data.type == 'pad_long' and data.pad_down and #data.pad_down == 1 and self.mode.alt then
		local pad_1 = self.grid:grid_to_index(data) + self.step_offset
		local pad_2 = self.grid:grid_to_index(data.pad_down[1]) + self.step_offset
		local selection_start = math.min(pad_1, pad_2)
		local selection_end = math.max(pad_1, pad_2)

		local step_length = self:get_step_length()
		local loop_start = (selection_start - 1) * step_length
		local loop_end = selection_end * step_length - 1
		auto:set_loop(loop_start, loop_end)
		print('Loop set: ' .. loop_start .. '-' .. loop_end)
	end

	self:set_grid(auto)
end

function BufferSeq:set_grid(component)
	if self.mode == nil then return end
	local grid = self.grid
	local auto = self:get_component()
	local step_length = self:get_step_length()
	local BLINK = 1
	local VALUE = (1 << 1)
	local LOOP_END = (1 << 2)
	local STEP = (1 << 3)
	local OUTSIDE = (1 << 4)
	local SCRUB = (1 << 5)

	grid:for_each(function(s, x, y, i)
		local pad = 0

		if self.blink_state then pad = pad | BLINK end

		local lane = self.selected_lane

		-- Determine the global step index for this LED pad based on the display offset
		local global_step = i + self.step_offset
		local current_step = math.floor(auto.step / step_length) + 1
		local seq_value

		-- Check if this pad is in the scrub range
		if self.scrub_active then
			local pad_start = (global_step - 1) * step_length
			local pad_end = global_step * step_length - 1
			if pad_start >= self.scrub_start_tick and pad_end <= self.scrub_end_tick then pad = pad | SCRUB end
		end

		-- Iterate over the tick range corresponding to the global step
		for j = (global_step - 1) * step_length, global_step * step_length - 1 do
			if auto.seq[j] and auto.seq[j][lane] then
				local events = auto.seq[j][lane]
				if events and #events > 0 then
					seq_value = #events
					break
				end
			end
		end

		if seq_value then pad = pad | VALUE end

		local loop_start = auto.seq_start
		local loop_end = auto.seq_start + auto.seq_length - 1
		local loop_start_index = math.floor(loop_start / step_length) + 1
		local loop_end_index = math.floor(loop_end / step_length) + 1

		if global_step == loop_start_index or global_step == loop_end_index then pad = pad | LOOP_END end

		if current_step == global_step and App.playing then pad = pad | STEP end

		if global_step > loop_end_index then pad = pad | OUTSIDE end

		local color = 0

		-- Scrub highlight (bright cyan/white)
		if pad & SCRUB > 0 then
			if pad & VALUE > 0 then
				color = { 0, 127, 127 } -- Bright cyan for scrub with content
			else
				color = { 30, 60, 60 } -- Dim cyan for scrub without content
			end
		elseif pad & (OUTSIDE | VALUE) == (OUTSIDE | VALUE) and pad & BLINK == 0 then
			color = grid.rainbow_off[(seq_value - 1) % 16 + 1]
		elseif pad & (BLINK | VALUE | STEP) == 0 or pad == BLINK then
			color = 0 -- empty
		elseif pad & STEP > 0 and pad & (BLINK | VALUE) == 0 or pad == (BLINK | STEP) then
			color = { 5, 5, 5 } -- LOW White for playhead
		elseif pad & VALUE > 0 and pad & (BLINK | STEP) == 0 or pad == (BLINK | VALUE) then
			-- Color based on event density (more events = brighter)
			local brightness = math.min(seq_value * 20, 127)
			color = { 0, brightness, brightness / 2 } -- Teal gradient
		elseif pad & VALUE > 0 and pad & STEP > 0 then
			color = { 0, 127, 64 } -- Bright teal for playhead on content
		elseif pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE > 0 then
			color = { 6, 0, 0 }
		elseif pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE == 0 then
			color = 0
		elseif pad & LOOP_END > 0 then
			color = { 5, 5, 5 }
		end

		s.led[x][y] = color
	end)
	grid:refresh('BufferSeq:set_grid')
end

function BufferSeq:transport_event(auto, data) self:set_grid(auto) end

function BufferSeq:alt_event(data)
	if data.state and self.mode.alt then
		self.index = nil
		self.mode:cancel_context()
		self:start_blink()
		local auto = self:get_component()
		self:set_grid(auto)
		local cleanup_holder = {}
		cleanup_holder.fn = self:on('alt_reset', function()
			self:end_blink()
			local auto = self:get_component()
			self:set_grid(auto)
			if cleanup_holder.fn then
				cleanup_holder.fn()
				cleanup_holder.fn = nil
			end
		end)
	elseif data.state then
		self:end_blink()
		self.index = nil
		local auto = self:get_component()
		self:set_grid(auto)
	end
end

function BufferSeq:row_event(data)
	if data.state then
		-- Stop any active scrub when changing tracks
		if self.scrub_active then
			self:stop_scrub()
			self.held_pads = {}
		end
		self.track = data.row
		-- Recalculate display for new track's buffer_step_length
		self:recalculate_display()
		-- Refresh grid to show new track's data
		local auto = self:get_component()
		if auto then self:set_grid(auto) end
	end
end

function BufferSeq:disable_event()
	-- Clean up scrub state when component is disabled
	if self.scrub_active then
		self:stop_scrub()
		self.held_pads = {}
	end
end

return BufferSeq
