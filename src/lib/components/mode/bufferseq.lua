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
	-- display_step_length controls how many ticks each grid pad represents
	-- This is separate from auto.buffer_step_length which is static for performance
	-- Initialize from auto component if available, otherwise use default
	self.display_step_length = o.display_step_length or nil -- Will be set in enable_event
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
	-- after display_step_length is initialized in enable_event

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
	-- Initialize display_step_length from auto component if not already set
	if not self.display_step_length then
		local auto = self:get_component()
		if auto and auto.buffer_step_length then
			self.display_step_length = auto.buffer_step_length
		else
			self.display_step_length = 6 -- fallback default (matches auto default)
		end
	end
	-- Initialize display calculations now that we can access the component
	self:recalculate_display()
end

-- Get current display_step_length (for grid visualization)
-- This is separate from auto.buffer_step_length which remains static
function BufferSeq:get_step_length()
	return self.display_step_length or 6 -- fallback default
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
	local current_step_length = self.display_step_length or 6
	local current_display_offset = self.display_offset * current_step_length

	if current_step_length < max_step_length then
		local new_length
		if current_step_length == 1 then
			new_length = 3
		else
			new_length = current_step_length * 2
		end

		self.display_step_length = new_length
		self:recalculate_display(current_display_offset)
		local auto = self:get_component()
		if auto then self:set_grid(auto) end
	end
end

function BufferSeq:decrease_step_length()
	local current_step_length = self.display_step_length or 6
	local current_display_offset = self.display_offset * current_step_length

	local new_length
	if current_step_length > min_step_length then
		new_length = current_step_length / 2
	elseif current_step_length <= min_step_length then
		new_length = 1
	end

	if new_length then
		self.display_step_length = new_length
		self:recalculate_display(current_display_offset)
		local auto = self:get_component()
		if auto then self:set_grid(auto) end
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
	local start_tick = (pad_index - 1) * step_length + 1
	local end_tick = pad_index * step_length
	return start_tick, end_tick
end

-- Start scrub playback from a pad
function BufferSeq:start_scrub(pad_index)
	local auto = self:get_component()
	local start_tick, end_tick = self:pad_to_tick_range(pad_index)

	-- Save loop boundaries (auto.tick continues updating automatically)
	self.scrub_saved_seq_start = auto.seq_start
	self.scrub_saved_seq_length = auto.seq_length

	-- Set scrub range
	self.scrub_start_tick = start_tick
	self.scrub_end_tick = end_tick
	self.scrub_active = true

	-- Start scrub playback
	auto:start_scrub(start_tick, end_tick, App.buffer_scrub_mode == 'loop')

	print('Scrub started: ' .. start_tick .. '-' .. end_tick .. ' (' .. App.buffer_scrub_mode .. ')')
end

-- Recalculate scrub range from all currently held pads
-- This ensures the loop is always based on currently held pads, not additive
function BufferSeq:recalculate_scrub_from_held_pads()
	local auto = self:get_component()

	-- Find min and max pad indices from held pads
	local min_pad = nil
	local max_pad = nil

	for pad_index, _ in pairs(self.held_pads) do
		if min_pad == nil or pad_index < min_pad then min_pad = pad_index end
		if max_pad == nil or pad_index > max_pad then max_pad = pad_index end
	end

	-- If no pads are held, stop scrub
	if min_pad == nil or max_pad == nil then
		self:stop_scrub()
		return
	end

	-- Calculate tick range from min to max pad
	local start_tick, _ = self:pad_to_tick_range(min_pad)
	local _, end_tick = self:pad_to_tick_range(max_pad)

	-- Update scrub range
	if self.scrub_active then
		-- Update existing scrub with new range
		self.scrub_start_tick = start_tick
		self.scrub_end_tick = end_tick
		auto:update_scrub(start_tick, end_tick)
		print('Scrub recalculated: ' .. start_tick .. '-' .. end_tick)
	else
		-- Start new scrub with full range (min to max)
		-- Save loop boundaries (auto.tick continues updating automatically)
		self.scrub_saved_seq_start = auto.seq_start
		self.scrub_saved_seq_length = auto.seq_length

		-- Set scrub range
		self.scrub_start_tick = start_tick
		self.scrub_end_tick = end_tick
		self.scrub_active = true

		-- Start scrub playback (will loop if App.buffer_scrub_mode is 'loop')
		auto:start_scrub(start_tick, end_tick, App.buffer_scrub_mode == 'loop')

		print('Scrub started: ' .. start_tick .. '-' .. end_tick .. ' (' .. App.buffer_scrub_mode .. ')')
	end
end

-- Jump buffer playback to a specific tick (play-through mode)
function BufferSeq:jump_to_tick(tick)
	local auto = self:get_component()

	-- If in scrub mode, set scrub_tick; otherwise set auto.tick
	if auto.scrub_mode then
		auto.scrub_tick = tick
		print('Scrub playback jumped to tick: ' .. tick)
	else
		auto.tick = tick
		print('Buffer playback jumped to tick: ' .. tick)
	end
end

-- Resync buffer playback with app tick (play-through mode)
function BufferSeq:resync_with_app()
	local auto = self:get_component()

	-- Calculate loop-aware position from App.tick
	-- App.tick is a global counter, but auto.tick must respect loop boundaries
	-- Convert App.tick to position within loop: (App.tick % seq_length) + seq_start
	auto.tick = (App.tick % auto.seq_length) + auto.seq_start

	print('Buffer playback resynced with app tick: ' .. App.tick .. ' -> auto.tick: ' .. auto.tick)
end

-- Stop scrub playback and restore normal playback
function BufferSeq:stop_scrub()
	if not self.scrub_active then return end

	local auto = self:get_component()

	-- Stop scrub and restore previous state
	-- Note: auto.tick is already at the correct position (it's been updating in the background)
	auto:stop_scrub(nil, self.scrub_saved_seq_start, self.scrub_saved_seq_length)

	self.scrub_active = false
	self.scrub_start_tick = nil
	self.scrub_end_tick = nil
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

	-- Handle pad press (start/update scrub)
	-- Only handle pad presses when not in alt mode (alt mode is for loop setting)
	if data.type == 'pad' and not self.mode.alt then
		-- Track held pad
		if data.state then
			self.held_pads[pad_index] = true
		else
			self.held_pads[pad_index] = nil
		end

		-- Loop mode: use standard scrub behavior
		self:recalculate_scrub_from_held_pads()
	end

	-- Handle long press for loop point setting (alt mode)
	-- This works the same as presetseq: long press two pads to set loop boundaries
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
	local auto = self:get_component() -- 'component' is the Auto component
	local BLINK = 1
	local VALUE = (1 << 1)
	local LOOP_END = (1 << 2)
	local STEP = (1 << 3)
	local OUTSIDE = (1 << 4)

	grid:for_each(function(s, x, y, i)
		local pad = 0

		if self.blink_state then pad = pad | BLINK end

		local lane = self.selected_lane

		-- Determine the global step index for this LED pad based on the display offset
		local global_step = i + self.step_offset
		local current_step = math.floor(auto.tick / self.step_length) + 1
		local seq_value

		-- Iterate over the tick range corresponding to the global step
		for j = (global_step - 1) * self.step_length, global_step * self.step_length - 1 do
			if auto.seq[j] and auto.seq[j][lane] then
				if lane == 'buffer' then
					-- Buffer lane contains array of events
					local events = auto.seq[j][lane]
					if events and #events > 0 then
						-- Use event count as a pseudo-value for color variation
						seq_value = #events
						break
					end
				else
					seq_value = auto.seq[j][lane].value
					break
				end
			end
		end

		if seq_value then pad = pad | VALUE end

		local loop_start = auto.seq_start
		local loop_end = auto.seq_start + auto.seq_length - 1
		local loop_start_index = math.floor(loop_start / self.step_length) + 1
		local loop_end_index = math.floor(loop_end / self.step_length) + 1

		if global_step == loop_start_index or global_step == loop_end_index then pad = pad | LOOP_END end

		if current_step == global_step and App.playing then pad = pad | STEP end

		if global_step > loop_end_index then pad = pad | OUTSIDE end

		local color = 123

		if pad & (OUTSIDE | VALUE) == (OUTSIDE | VALUE) and pad & BLINK == 0 then
			color = grid.rainbow_off[(seq_value - 1) % 16 + 1] -- Draw steps with values outside the loop
		elseif pad & (BLINK | VALUE | STEP) == 0 or pad == BLINK then
			color = 0 -- empty
		elseif pad & STEP > 0 and pad & (BLINK | VALUE) == 0 or pad == (BLINK | STEP) then
			-- LOW White
			color = { 5, 5, 5 }
		elseif pad & VALUE > 0 and pad & (BLINK | STEP) == 0 or pad == (BLINK | VALUE) then
			-- LOW Color
			color = grid.rainbow_off[(seq_value - 1) % 16 + 1]
		elseif pad & VALUE > 0 and pad & STEP > 0 then
			color = grid.rainbow_on[(seq_value - 1) % 16 + 1]
		elseif pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE > 0 then
			-- Value steps outside the loop during blink
			color = { 6, 0, 0 }
		elseif pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE == 0 then
			-- Blink empty steps outside the loop
			color = 0
		elseif pad & LOOP_END > 0 then
			-- Loop end points
			color = { 5, 5, 5 }
		end

		s.led[x][y] = color
	end)
	grid:refresh('BufferSeq:set_grid')
end

function BufferSeq:transport_event(auto, data)
	-- Play-through mode doesn't need special transport handling
	-- The buffer just plays from wherever it was jumped to

	self:set_grid(auto)
end

function BufferSeq:alt_event(data)
	if data.state and self.mode.alt then
		self.index = nil
		self.mode:cancel_context()
		self:start_blink()
		-- Clear any held pads and stop scrub when entering alt mode
		if self.scrub_active then
			self:stop_scrub()
			self.held_pads = {}
		end
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
		-- Initialize display_step_length for new track (from auto component)
		local auto = self:get_component()
		if auto and auto.buffer_step_length then self.display_step_length = auto.buffer_step_length end
		-- Recalculate display for new track
		self:recalculate_display()
		-- Refresh grid to show new track's data
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
