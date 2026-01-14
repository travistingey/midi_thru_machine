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
	self.pending_scrub_pads = {} -- Track which pads are pending for scrub

	-- Grid refresh optimization: track last rendered step to avoid refreshing every tick
	self.last_rendered_step = nil

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
	-- Initialize display_step_length independently (not synced with buffer_step_length)
	-- If not already set, use a sensible default for grid visualization
	local buffer = self:get_component()
	if not self.display_step_length then
		-- Default to 1 bar (App.ppqn * 4) for grid display
		-- This is independent of buffer.buffer_step_length which controls buffer swapping
		self.display_step_length = App.ppqn * 4
	end
	table.insert(
		self.cleanup_functions,
		buffer:on('clear_buffer', function(data)
			self.last_rendered_step = nil -- Force refresh on buffer clear
			self:set_grid(buffer)
		end)
	)

	-- Listen for scrub started event from buffer (for sync)
	table.insert(
		self.cleanup_functions,
		buffer:on('scrub_started', function(data)
			-- Update bufferseq state when scrub starts via sync
			if not self.scrub_active then
				self.scrub_saved_seq_start = buffer.seq_start
				self.scrub_saved_seq_length = buffer.seq_length
				self.scrub_start_tick = data.start_tick
				self.scrub_end_tick = data.end_tick
				self.scrub_active = true
			end
		end)
	)

	-- Listen for track armed state changes to update row pads
	-- Set up listeners for all tracks
	local function setup_armed_listeners()
		for track_id = 1, 8 do
			local track = App.track[track_id]
			if track then
				table.insert(
					self.cleanup_functions,
					track:on('armed', function(armed)
						-- Update row pads when any track's armed status changes
						if self.mode and self.mode.enabled then self:update_row_pads() end
					end)
				)
			end
		end
	end
	setup_armed_listeners()

	-- Initialize display calculations now that we can access the component
	self:recalculate_display()

	-- Update row pads when component enables
	self:update_row_pads()
end

-- Get current display_step_length (for grid visualization)
-- This is separate from buffer.buffer_step_length which remains static
function BufferSeq:get_step_length()
	return self.display_step_length or (App.ppqn * 4) -- fallback default (1 bar)
end

-- Get rainbow color index based on measure only
-- Groups colors into 4 groups: 1-4, 5-8, 9-12, 13-16
-- Each measure (4 beats) uses one color group
-- Uses first color in each group (measure-based only, not event-count based)
function BufferSeq:get_rainbow_color_index(step_tick, seq_value)
	-- Calculate which measure (1-4) this step is in
	-- 1 measure = 4 beats = App.ppqn * 4
	local measure = math.floor(step_tick / (App.ppqn * 4)) % 16
	-- measure is 0-15, convert to 1-16
	measure = measure + 1

	-- Return first color in group (measure-based only)
	return measure
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

	-- If no pads are held, stop scrub and clear pending
	if min_pad == nil or max_pad == nil then
		self:stop_scrub()
		buffer:clear_pending_scrub()
		self.pending_scrub_pads = {}
		return
	end

	-- Calculate tick range from min to max pad
	local start_tick, _ = self:pad_to_tick_range(min_pad)
	local _, end_tick = self:pad_to_tick_range(max_pad)
	local display_step_length = self:get_step_length()

	-- Create pad check function
	local pad_check_fn = function()
		-- Verify pads are still held
		if not next(self.held_pads) then return false end

		-- Recalculate to ensure range still matches
		local check_min = nil
		local check_max = nil
		for pad_idx, _ in pairs(self.held_pads) do
			if check_min == nil or pad_idx < check_min then check_min = pad_idx end
			if check_max == nil or pad_idx > check_max then check_max = pad_idx end
		end

		if check_min and check_max then
			local check_start, _ = self:pad_to_tick_range(check_min)
			local _, check_end = self:pad_to_tick_range(check_max)
			return check_start == start_tick and check_end == end_tick
		end
		return false
	end

	-- Check if sync is enabled and we should wait
	if buffer.buffer_sync_length and buffer:should_wait_for_sync(display_step_length) then
		-- If scrub is already active, update it immediately (no sync for updates)
		if self.scrub_active then
			-- Update existing scrub with new range
			self.scrub_start_tick = start_tick
			self.scrub_end_tick = end_tick
			buffer:update_scrub(start_tick, end_tick)
			print('Scrub recalculated: ' .. start_tick .. '-' .. end_tick)
		else
			-- Queue new scrub action (this will replace any existing pending scrub)
			buffer:queue_scrub_action(start_tick, end_tick, App.buffer_scrub_mode == 'loop', display_step_length, pad_check_fn)

			-- Track pending pads
			self.pending_scrub_pads = {}
			for pad_idx, _ in pairs(self.held_pads) do
				self.pending_scrub_pads[pad_idx] = true
			end

			local next_sync_tick = buffer:get_next_sync_tick(display_step_length)
			print('Scrub queued for sync at tick: ' .. next_sync_tick)
		end
		return
	end

	-- No sync or already on boundary - execute immediately
	if self.scrub_active then
		-- Update existing scrub with new range
		self.scrub_start_tick = start_tick
		self.scrub_end_tick = end_tick
		buffer:update_scrub(start_tick, end_tick)
		print('Scrub recalculated: ' .. start_tick .. '-' .. end_tick)
	else
		-- Start new scrub with full range (min to max)
		-- Save loop boundaries
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
			-- Clear pending scrub if pad is released and no pads are held
			if not next(self.held_pads) then
				buffer:clear_pending_scrub()
				self.pending_scrub_pads = {}
			end
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

		-- Check if sync is enabled
		if buffer.buffer_sync_length and buffer:should_wait_for_sync(step_length) then
			buffer:queue_loop_action(loop_start, loop_end, step_length)
			local next_sync_tick = buffer:get_next_sync_tick(step_length)
			print('Loop queued for sync at tick: ' .. next_sync_tick)
		else
			buffer:set_loop(loop_start, loop_end)
			print('Loop set: ' .. loop_start .. '-' .. loop_end)
		end
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

		-- Optimized: Only check ticks that actually exist in buffer_read (sparse table)
		-- Just find first event in step range - don't count events
		-- Color is based on measure (step_tick), not event count
		local step_start_tick = (global_step - 1) * step_length
		local step_end_tick = global_step * step_length - 1
		for tick, events in pairs(buffer.buffer_read) do
			-- Only check ticks within this step's range
			if tick >= step_start_tick and tick <= step_end_tick then
				if events and #events > 0 then
					-- Found first event - just mark as having value (don't count)
					seq_value = 1
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

	-- Update last rendered step for optimization (so transport_event knows we just refreshed)
	if buffer and buffer.playing then
		local step_length = self:get_step_length()
		self.last_rendered_step = math.floor((buffer.tick - 1) / step_length) + 1
	else
		-- Not playing, so reset tracking
		self.last_rendered_step = nil
	end
end

function BufferSeq:transport_event(buffer, data)
	-- Optimized grid refresh: only refresh on DISPLAY step boundaries, not every tick
	-- Uses display_step_length (for grid visualization) NOT buffer_step_length (for buffer swapping)
	-- This dramatically reduces grid refresh frequency (e.g., from 120/sec to ~15/sec at 300 BPM with display_step_length=8)

	-- Always refresh on start/stop events
	if data.type == 'start' or data.type == 'stop' then
		self.last_rendered_step = nil -- Force refresh
		self:set_grid(buffer)
		return
	end

	-- For clock events, only refresh when DISPLAY step changes (based on display_step_length)
	if data.type == 'clock' and buffer.playing then
		-- Use display_step_length for grid refresh boundaries (independent of buffer_step_length)
		local display_step_length = self:get_step_length()
		-- Calculate current display step index (1-based for display)
		-- This uses display_step_length, which may differ from buffer.buffer_step_length
		local current_display_step = math.floor((buffer.tick - 1) / display_step_length) + 1

		-- Only refresh if display step changed
		if self.last_rendered_step ~= current_display_step then
			self.last_rendered_step = current_display_step
			self:set_grid(buffer)
		end
	end
end

function BufferSeq:arrow_event(data)
	if not data.state then return end

	local buffer = self:get_component()
	local track = buffer.track

	if self.mode.alt then
		-- Alt + Right: Toggle buffer playback for active track
		if data.type == 'right' then
			if buffer then
				local current_playback = track.buffer.buffer_playback or false
				local new_playback = not current_playback
				-- Use Registry to set the parameter (this will trigger the set_action)
				local Registry = require('Foobar/lib/utilities/registry')
				Registry.set('track_' .. track.id .. '_buffer_playback', new_playback and 1 or 0, 'alt_toggle')

				if new_playback then Registry.set('track_' .. track.id .. '_armed', 0, 'playback_on') end

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
			if buffer then
				buffer:clear_buffer()
				Registry.set('track_' .. track.id .. '_buffer_playback', 0, 'clear_buffer')
				print('Buffer cleared for track ' .. track.id)
				-- Refresh grid display
				self:set_grid(buffer)
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
			if buffer then self:set_grid(buffer) end

			print('Buffer offset: ' .. self.display_offset)

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
		-- Ensure we're showing the current track, not defaulting to first track
		if self.track then App.current_track = self.track end
		local buffer = self:get_component()
		self:set_grid(buffer)
		-- Update row pads to reflect current state
		self:update_row_pads()
		local cleanup_holder = {}
		cleanup_holder.fn = self:on('alt_reset', function()
			self:end_blink()
			local buffer = self:get_component()
			self:set_grid(buffer)
			self:update_row_pads()
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
		-- Update row pads when alt mode deactivates
		self:update_row_pads()
	end
end

function BufferSeq:row_event(data)
	if data.state then
		-- If alt mode is active, arm/disarm the track instead of switching tracks
		if self.mode.alt then
			local track = App.track[data.row]
			if track then
				local Registry = require('Foobar/lib/utilities/registry')
				local was_armed = track.armed
				-- Toggle armed state
				local new_armed_state = was_armed and 0 or 1
				Registry.set('track_' .. track.id .. '_armed', new_armed_state, 'alt_row_tap')
				print('Track ' .. track.id .. ' armed: ' .. (new_armed_state == 1 and 'on' or 'off'))
				-- Update row pads to reflect the change
				self:update_row_pads()
			end
			-- Reset alt mode after arming
			self.mode.alt = false
			if self.mode.alt_pad then
				self.mode.alt_pad.led[9][1] = 0
				self.mode.alt_pad:refresh()
			end
			self:emit('alt_reset')
			return
		end

		-- Stop any active scrub when changing tracks
		if self.scrub_active then
			self:stop_scrub()
			self.held_pads = {}
		end
		self.track = data.row
		App.current_track = data.row
		-- Initialize display_step_length for new track (independent of buffer_step_length)
		-- If not already set, use default - don't sync with buffer.buffer_step_length
		if not self.display_step_length then
			self.display_step_length = App.ppqn * 4 -- Default to 1 bar
		end
		-- Recalculate display for new track
		self:recalculate_display()
		-- Refresh grid to show new track's data
		local buffer = self:get_component()
		if buffer then self:set_grid(buffer) end
		-- Update row pads after track change
		self:update_row_pads()
	end
end

function BufferSeq:disable_event()
	-- Clean up scrub state when component is disabled
	if self.scrub_active then
		self:stop_scrub()
		self.held_pads = {}
	end
end

-- Update row pads to show current track and armed status
-- Armed tracks: rainbow_off[1] when not selected, rainbow_on[1] when selected
-- Current track: always shows with brightness 1 (white)
function BufferSeq:update_row_pads()
	if not self.mode or not self.mode.row_pads then return end

	local Grid = require('Foobar/lib/grid')
	local current_track = App.current_track or 1

	-- Reset all row pads first
	self.mode.row_pads:reset()

	-- Update row pads for all tracks
	for track_id = 1, 8 do
		local track = App.track[track_id]
		if track then
			local row_y = 9 - track_id
			if track.armed then
				-- Armed track: use rainbow colors
				if track_id == current_track then
					-- Selected and armed: bright red (rainbow_on[1])
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_on[1]
				else
					-- Armed but not selected: dim red (rainbow_off[1])
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_off[1]
				end
			elseif track_id == current_track then
				-- Current track but not armed: white (brightness 1)
				self.mode.row_pads.led[9][row_y] = 1
			end
		end
	end

	-- Refresh both grid and display
	self.mode.row_pads:refresh('BufferSeq:update_row_pads')
	App.screen_dirty = true
end

return BufferSeq
