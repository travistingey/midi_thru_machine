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
	self.component = 'buffer'

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
		grid_end = o.grid_end or { x = 8, y = 8 },
		display_start = o.display_start or { x = 1, y = 1 },
		display_end = o.display_end or { x = 8, y = 4 },
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
				-- Convert tick values to integers for display (indices should be whole numbers)
				local start_tick = math.floor(self.scrub_start_tick)
				local end_tick = math.floor(self.scrub_end_tick)
				UI:draw_tag(1, 36, 'scrub', start_tick .. '-' .. end_tick)
			else
				UI:draw_tag(1, 36, 'step', self.last_event)
			end
		end
	end
end

function BufferSeq:enable_event()
	-- No preset selection needed for buffer mode
	-- Initialize display_step_length from buffer component if not already set
	local buffer = self:get_component()
	if not self.display_step_length then
		if buffer and buffer.buffer_step_length then
			self.display_step_length = buffer.buffer_step_length
		else
			-- Default to 1/8th note (App.ppqn / 2)
			self.display_step_length = App.ppqn / 2
		end
	end
	table.insert(self.cleanup_functions, buffer:on('clear_buffer', function(data) self:set_grid(buffer) end))
	-- Initialize display calculations now that we can access the component
	self:recalculate_display()
end

-- Get current display_step_length (for grid visualization)
-- This is separate from buffer.buffer_step_length which remains static
function BufferSeq:get_step_length()
	return self.display_step_length or (App.ppqn / 2) -- fallback default (1/8th note)
end

-- Get rainbow color index based on measure and seq_value
-- Groups colors into 4 groups: 1-4, 5-8, 9-12, 13-16
-- Each measure (4 beats) uses one color group
-- seq_value selects which color within the group (1-4)
function BufferSeq:get_rainbow_color_index(step_tick, seq_value)
	-- Calculate which measure (1-4) this step is in
	-- 1 measure = 4 beats = App.ppqn * 4 ticks
	local measure = math.floor(step_tick / (App.ppqn * 4)) % 4
	-- measure is 0-3, convert to 1-4
	measure = measure + 1

	-- Each measure uses 4 colors:
	-- Measure 1: colors 1-4
	-- Measure 2: colors 5-8
	-- Measure 3: colors 9-12
	-- Measure 4: colors 13-16
	local color_group_start = (measure - 1) * 4 + 1

	-- Use seq_value to select color within group (1-4)
	-- seq_value can be any number, so use modulo to get 0-3, then add 1 to get 1-4
	local color_offset = ((seq_value - 1) % 4) + 1

	-- Return color index (1-16)
	return color_group_start + color_offset - 1
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
		local buffer = self:get_component()
		if buffer then self:set_grid(buffer) end
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
		local buffer = self:get_component()
		if buffer then self:set_grid(buffer) end
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
	local buffer = self:get_component()
	local start_tick, end_tick = self:pad_to_tick_range(pad_index)

	-- Save loop boundaries (buffer.tick continues updating automatically)
	self.scrub_saved_seq_start = buffer.seq_start
	self.scrub_saved_seq_length = buffer.seq_length

	-- Set scrub range
	self.scrub_start_tick = start_tick
	self.scrub_end_tick = end_tick
	self.scrub_active = true

	-- Start scrub playback
	buffer:start_scrub(start_tick, end_tick, App.buffer_scrub_mode == 'loop')

	print('Scrub started: ' .. start_tick .. '-' .. end_tick .. ' (' .. App.buffer_scrub_mode .. ')')
end

-- Recalculate scrub range from all currently held pads
-- This ensures the loop is always based on currently held pads, not additive
function BufferSeq:recalculate_scrub_from_held_pads()
	local buffer = self:get_component()

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
		buffer:update_scrub(start_tick, end_tick)
		print('Scrub recalculated: ' .. start_tick .. '-' .. end_tick)
	else
		-- Start new scrub with full range (min to max)
		-- Save loop boundaries (buffer.tick continues updating automatically)
		self.scrub_saved_seq_start = buffer.seq_start
		self.scrub_saved_seq_length = buffer.seq_length

		-- Set scrub range
		self.scrub_start_tick = start_tick
		self.scrub_end_tick = end_tick
		self.scrub_active = true

		-- Start scrub playback (will loop if App.buffer_scrub_mode is 'loop')
		buffer:start_scrub(start_tick, end_tick, App.buffer_scrub_mode == 'loop')

		print('Scrub started: ' .. start_tick .. '-' .. end_tick .. ' (' .. App.buffer_scrub_mode .. ')')
	end
end

-- Jump buffer playback to a specific tick (play-through mode)
function BufferSeq:jump_to_tick(tick)
	local buffer = self:get_component()

	-- If in scrub mode, set scrub_tick; otherwise set buffer.tick
	if buffer.scrub_mode then
		buffer.scrub_tick = tick
		print('Scrub playback jumped to tick: ' .. tick)
	else
		buffer.tick = tick
		print('Buffer playback jumped to tick: ' .. tick)
	end
end

-- Resync buffer playback with app tick (play-through mode)
function BufferSeq:resync_with_app()
	local buffer = self:get_component()

	-- Calculate loop-aware position from App.tick
	-- App.tick is a global counter, but buffer.tick must respect loop boundaries
	-- Convert App.tick to position within loop: (App.tick % seq_length) + seq_start
	buffer.tick = (App.tick % buffer.seq_length) + buffer.seq_start

	print('Buffer playback resynced with app tick: ' .. App.tick .. ' -> buffer.tick: ' .. buffer.tick)
end

-- Stop scrub playback and restore normal playback
function BufferSeq:stop_scrub()
	if not self.scrub_active then return end

	local buffer = self:get_component()

	-- Stop scrub and restore previous state
	-- Note: buffer.tick is already at the correct position (it's been updating in the background)
	buffer:stop_scrub(nil, self.scrub_saved_seq_start, self.scrub_saved_seq_length)

	self.scrub_active = false
	self.scrub_start_tick = nil
	self.scrub_end_tick = nil
	self.scrub_saved_seq_start = nil
	self.scrub_saved_seq_length = nil

	print('Scrub stopped')
end

function BufferSeq:grid_event(component, data)
	local grid = self.grid
	local buffer = component
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
		buffer:set_loop(loop_start, loop_end)
		print('Loop set: ' .. loop_start .. '-' .. loop_end)
	end

	self:set_grid(buffer)
end

function BufferSeq:set_grid(component)
	if self.mode == nil then return end
	local grid = self.grid
	local buffer = self:get_component() -- 'component' is the Buffer component
	local BLINK = 1
	local VALUE = (1 << 1)
	local LOOP_END = (1 << 2)
	local STEP = (1 << 3)
	local OUTSIDE = (1 << 4)
	local SCRUB = (1 << 5)
	local RECORD_STEP = (1 << 6) -- Main playhead (recording position)

	-- Check if scrub mode is active
	local scrub_active = buffer.scrub_mode or self.scrub_active
	local scrub_start_step = nil
	local scrub_end_step = nil
	local scrub_playhead_step = nil
	local step_length = self:get_step_length()

	if scrub_active and self.scrub_start_tick and self.scrub_end_tick then
		-- Convert ticks to 1-based step indices (ticks 1-6 = step 1, ticks 7-12 = step 2, etc.)
		scrub_start_step = math.floor((self.scrub_start_tick - 1) / step_length) + 1
		scrub_end_step = math.floor((self.scrub_end_tick - 1) / step_length) + 1
		if buffer.scrub_tick then scrub_playhead_step = math.floor((buffer.scrub_tick - 1) / step_length) + 1 end
	end

	grid:for_each(function(s, x, y, i)
		local pad = 0

		if self.blink_state then pad = pad | BLINK end

		-- Determine the global step index for this LED pad based on the display offset
		local global_step = i + self.step_offset
		-- Calculate the tick position of this step (absolute tick position)
		-- This is used for measure calculation, so we need the actual tick position
		local step_tick = (global_step - 1) * step_length
		local seq_value

		-- Iterate over the tick range corresponding to the global step
		-- Check buffer_read for visualization (what's being played back)
		for j = (global_step - 1) * step_length, global_step * step_length - 1 do
			if buffer.buffer_read[j] then
				-- Buffer contains array of events
				local events = buffer.buffer_read[j]
				if events and #events > 0 then
					-- Use event count as a pseudo-value for color variation
					seq_value = #events
					break
				end
			end
		end

		if seq_value then pad = pad | VALUE end

		local loop_start = buffer.seq_start
		local loop_end = buffer.seq_start + buffer.seq_length - 1
		-- Convert ticks to 1-based step indices (matching presetseq calculation)
		local loop_start_index = math.floor(loop_start / step_length) + 1
		local loop_end_index = math.floor(loop_end / step_length) + 1

		if global_step == loop_start_index or global_step == loop_end_index then pad = pad | LOOP_END end

		-- Always calculate main playhead (recording position) - show even during scrub
		local current_step = math.floor((buffer.tick - 1) / step_length) + 1
		if current_step == global_step then pad = pad | RECORD_STEP end

		-- Handle scrub mode
		if scrub_active then
			-- Highlight scrub range steps
			if scrub_start_step and scrub_end_step and global_step >= scrub_start_step and global_step <= scrub_end_step then pad = pad | SCRUB end
			-- Show scrub playhead (only during playback)
			if scrub_playhead_step and global_step == scrub_playhead_step and App.playing then pad = pad | STEP end
		end

		-- Mark steps outside loop bounds (before loop start or after loop end)
		local is_outside = global_step < loop_start_index or global_step > loop_end_index
		if is_outside then pad = pad | OUTSIDE end

		-- Check if buffer playback is active
		local playback_active = buffer.buffer_playback or false

		local color = 123

		-- Handle blink mode first (like presetseq)
		if pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE > 0 then
			-- Value steps outside the loop during blink
			color = { 6, 0, 0 }
		elseif pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) and pad & VALUE == 0 then
			-- Blink empty steps outside the loop
			color = 0
		-- Handle out-of-bounds steps (when not blinking)
		elseif is_outside then
			if seq_value then
				-- Out-of-bounds with events: always {5,5,5}
				color = { 5, 5, 5 }
			else
				-- Out-of-bounds without events: always 0
				color = 0
			end
		-- When playback is OFF
		elseif not playback_active then
			-- If scrub mode is active, use rainbow colors for scrub range
			if scrub_active and pad & SCRUB > 0 then
				if pad & STEP > 0 then
					-- Scrub playhead with value (rainbow on)
					if seq_value then
						local color_index = self:get_rainbow_color_index(step_tick, seq_value)
						color = grid.rainbow_on[color_index]
					else
						color = { 5, 5, 5 }
					end
				elseif seq_value then
					-- Scrub range with value (rainbow off)
					local color_index = self:get_rainbow_color_index(step_tick, seq_value)
					color = grid.rainbow_off[color_index]
				else
					-- Scrub range without value
					color = { 5, 5, 5 }
				end
				-- Also show main playhead (recording position) with color = 1 if on this step
				if pad & RECORD_STEP > 0 then color = 1 end
			-- Outside scrub range when playback is off
			else
				-- Show main playhead with color = 1 when playback is off (for recording position)
				if pad & RECORD_STEP > 0 then
					color = 1
				elseif seq_value then
					-- Pads with events: {5,5,5}
					color = { 5, 5, 5 }
				else
					-- Empty pads: 0
					color = 0
				end
			end
		-- When playback is ON (normal rendering with rainbow colors)
		else
			-- Handle scrub mode highlighting during playback
			if scrub_active and pad & SCRUB > 0 then
				if pad & STEP > 0 then
					-- Scrub playhead with value (rainbow on)
					if seq_value then
						local color_index = self:get_rainbow_color_index(step_tick, seq_value)
						color = grid.rainbow_on[color_index]
					else
						color = { 5, 5, 5 }
					end
				elseif seq_value then
					-- Scrub range with value (rainbow off)
					local color_index = self:get_rainbow_color_index(step_tick, seq_value)
					color = grid.rainbow_off[color_index]
				else
					-- Scrub range without value
					color = { 5, 5, 5 }
				end
				-- Also show main playhead (recording position) if on this step
				-- If both playheads are on same step, prioritize scrub playhead (already set above)
				-- If main playhead is on different step, show it with rainbow colors
				if pad & RECORD_STEP > 0 and pad & STEP == 0 then
					-- Main playhead on different step from scrub playhead
					if seq_value then
						local color_index = self:get_rainbow_color_index(step_tick, seq_value)
						color = grid.rainbow_on[color_index]
					else
						color = { 5, 5, 5 }
					end
				end
			-- Normal playback rendering (not scrub, not out-of-bounds)
			elseif pad & (BLINK | VALUE | RECORD_STEP) == 0 or pad == BLINK then
				color = 0 -- empty
			elseif pad & RECORD_STEP > 0 and pad & (BLINK | VALUE) == 0 or pad == (BLINK | RECORD_STEP) then
				-- Main playhead without value
				color = { 5, 5, 5 }
			elseif pad & VALUE > 0 and pad & (BLINK | RECORD_STEP) == 0 or pad == (BLINK | VALUE) then
				-- Value without playhead (off colors)
				if seq_value then
					local color_index = self:get_rainbow_color_index(step_tick, seq_value)
					color = grid.rainbow_off[color_index]
				else
					color = 0
				end
			elseif pad & VALUE > 0 and pad & RECORD_STEP > 0 then
				-- Main playhead with value (on colors)
				if seq_value then
					local color_index = self:get_rainbow_color_index(step_tick, seq_value)
					color = grid.rainbow_on[color_index]
				else
					color = { 5, 5, 5 }
				end
			end
		end

		-- Loop end points: visible when alt mode is active, blink when blink mode is active
		if pad & LOOP_END > 0 then
			if self.mode.alt then
				-- Alt mode is active - show loop end points
				if self.blink_state ~= nil then
					-- Blink mode is active - blink the loop end points
					if self.blink_state then
						color = { 5, 5, 5 }
					else
						color = 0
					end
				else
					-- Alt mode active but blink not started yet - show with value if present
					if seq_value then
						local color_index = self:get_rainbow_color_index(step_tick, seq_value)
						color = grid.rainbow_off[color_index]
					else
						color = { 5, 5, 5 }
					end
				end
			end
			-- If alt mode is not active, don't override - let normal rendering handle it
		end

		s.led[x][y] = color
	end)
	grid:refresh('BufferSeq:set_grid')
end

function BufferSeq:transport_event(buffer, data)
	-- Play-through mode doesn't need special transport handling
	-- The buffer just plays from wherever it was jumped to

	self:set_grid(buffer)
end

function BufferSeq:arrow_event(data)
	if not data.state then return end
	if self.mode.alt then
		-- Alt + Right: Toggle buffer playback for active track
		if data.type == 'right' then
			local track = App.track[self.track or App.current_track]
			if track and track.buffer then
				local current_playback = track.buffer.buffer_playback or false
				local new_playback = not current_playback
				-- Use Registry to set the parameter (this will trigger the set_action)
				local Registry = require('Foobar/lib/utilities/registry')
				Registry.set('track_' .. track.id .. '_buffer_playback', new_playback and 1 or 0, 'alt_toggle')
				print('Buffer playback: ' .. (new_playback and 'on' or 'off'))
			end
			-- Reset alt mode
			self.mode.alt = false
			-- Reset alt pad LED
			if self.mode.alt_pad then
				self.mode.alt_pad.led[9][1] = 0
				self.mode.alt_pad:refresh()
			end
			self:emit('alt_reset')
			return
		end

		-- Alt + Left: Clear buffer
		if data.type == 'left' then
			local track = App.track[self.track or App.current_track]
			if track and track.buffer then
				track.buffer:clear_buffer()
				print('Buffer cleared for track ' .. track.id)
				-- Refresh grid display
				self:set_grid(track.buffer)
			end
			-- Reset alt mode
			self.mode.alt = false
			-- Reset alt pad LED
			if self.mode.alt_pad then
				self.mode.alt_pad.led[9][1] = 0
				self.mode.alt_pad:refresh()
			end
			self:emit('alt_reset')
			return
		end

		-- Alt + Up/Down: Jump offset by page size
		if data.type == 'up' or data.type == 'down' then
			-- Calculate page size: display_length steps (e.g., 32 for 8x4 grid in 8x8 display)
			local page_size = self.display_length
			local step_length = self:get_step_length()

			if data.type == 'up' then
				-- Jump to previous page
				self.display_offset = math.max(0, self.display_offset - page_size)
			else
				-- Jump to next page
				self.display_offset = self.display_offset + page_size
			end

			-- Recalculate display with new offset
			self:recalculate_display()

			-- Refresh grid
			local buffer = self:get_component()
			if buffer then self:set_grid(buffer) end

			print('Buffer offset: ' .. self.display_offset)

			-- Reset alt mode
			self.mode.alt = false
			-- Reset alt pad LED
			if self.mode.alt_pad then
				self.mode.alt_pad.led[9][1] = 0
				self.mode.alt_pad:refresh()
			end
			self:emit('alt_reset')
			return
		end
	elseif data.type == 'left' then
		-- Left/Right: zoom in/out (step length)
		-- Up/Down: scroll through buffer

		self:increase_step_length()
	elseif data.type == 'right' then
		self:decrease_step_length()
	elseif data.type == 'up' then
		self:decrease_display_offset()
		if self.display_offset == 0 then print('At buffer start') end
	elseif data.type == 'down' then
		self:increase_display_offset()
		print('Buffer offset: ' .. bufferseq.display_offset)
	end
end

function BufferSeq:alt_event(data)
	if data.state and self.mode.alt then
		-- Alt mode activated - start blinking to show loop end points
		self.index = nil
		self.mode:cancel_context()
		self:start_blink()
		-- Clear any held pads and stop scrub when entering alt mode
		if self.scrub_active then
			self:stop_scrub()
			self.held_pads = {}
		end
		local buffer = self:get_component()
		self:set_grid(buffer)
		local cleanup_holder = {}
		cleanup_holder.fn = self:on('alt_reset', function()
			self:end_blink()
			local buffer = self:get_component()
			self:set_grid(buffer)
			if cleanup_holder.fn then
				cleanup_holder.fn()
				cleanup_holder.fn = nil
			end
		end)
	elseif data.state then
		-- Alt mode deactivated - stop blinking
		self:end_blink()
		self.index = nil
		local buffer = self:get_component()
		self:set_grid(buffer)
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
		-- Initialize display_step_length for new track (from buffer component)
		local buffer = self:get_component()
		if buffer and buffer.buffer_step_length then self.display_step_length = buffer.buffer_step_length end
		-- Recalculate display for new track
		self:recalculate_display()
		-- Refresh grid to show new track's data
		if buffer then self:set_grid(buffer) end
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
