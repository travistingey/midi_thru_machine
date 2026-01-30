local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local UI = require(path_name .. 'ui')
local Registry = require('Foobar/lib/utilities/registry')
local flags = require(path_name .. 'utilities/flags')

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
	self.scrub_saved_buffer_start = nil
	self.held_pads = {} -- Track currently held pads for multi-pad selection

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

	-- Listen for scrub started event from clip (for sync)
	local track = buffer.track
	local clip = track and track.clip or nil
	if clip then
		table.insert(
			self.cleanup_functions,
			clip:on('scrub_started', function(data)
				-- Update bufferseq state when scrub starts via sync
				if not self.scrub_active then
					self.scrub_saved_buffer_start = buffer.buffer_start
					self.scrub_start_tick = data.start_tick
					self.scrub_end_tick = data.end_tick
					self.scrub_active = true
					-- Refresh grid to show scrub range
					self:set_grid(buffer)
				end
			end)
		)

		-- Listen for scrub stopped event from clip (for sync)
		table.insert(
			self.cleanup_functions,
			clip:on('scrub_stopped', function(data)
				-- Update bufferseq state when scrub stops via sync
				self.scrub_active = false
				self.scrub_start_tick = nil
				self.scrub_end_tick = nil
				self.scrub_saved_buffer_start = nil
				-- Refresh grid to clear scrub range
				self:set_grid(buffer)
			end)
		)
	end

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

	-- Save buffer start (buffer.tick continues updating automatically)
	self.scrub_saved_buffer_start = buffer.buffer_start

	-- Set scrub range
	self.scrub_start_tick = start_tick
	self.scrub_end_tick = end_tick
	self.scrub_active = true

	-- Start scrub playback
	local track = buffer.track
	local clip = track and track.clip or nil
	if clip then clip:start_scrub(start_tick, end_tick, App.buffer_scrub_mode == 'loop') end
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

	-- If no pads are held, queue synced scrub stop
	if min_pad == nil or max_pad == nil then
		local track = buffer.track
		local clip = track and track.clip or nil
		if clip then
			clip:clear_pending_scrub()
			-- Queue synced scrub stop (minimum 1/16th note sync)
			if self.scrub_active then
				local min_sync_length = App.ppqn / 4 -- 1/16th note minimum
				local scrub_sync_length = math.max(self:get_step_length(), min_sync_length)
				clip:queue_scrub_stop(scrub_sync_length)
				if flags.debug_scrub then
					local next_sync_tick = clip:get_next_sync_tick(scrub_sync_length)
					print('Scrub stop queued for sync at tick: ' .. next_sync_tick)
				end
			end
		end
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

	-- Get clip component for scrub operations
	local track = buffer.track
	local clip = track and track.clip or nil

	-- Calculate sync length for scrub operations
	-- Use display_step_length as the sync boundary, with minimum of 1/16th note
	local min_sync_length = App.ppqn / 4 -- 1/16th note minimum (24 ticks at 96 ppqn)
	local scrub_sync_length = math.max(display_step_length, min_sync_length)

	-- Always use sync for scrub start (minimum 1/16th note)
	-- This ensures scrubbing is synchronized to the beat
	if clip then
		-- If scrub is already active, update it immediately (no sync for updates)
		if self.scrub_active then
			-- Update existing scrub with new range
			self.scrub_start_tick = start_tick
			self.scrub_end_tick = end_tick
			clip:update_scrub(start_tick, end_tick)
			if flags.debug_scrub then
				print('Scrub recalculated: ' .. start_tick .. '-' .. end_tick)
			end
		else
			-- Queue new scrub action with display_step_length as sync boundary
			clip:queue_scrub_action(start_tick, end_tick, App.buffer_scrub_mode == 'loop', pad_check_fn, scrub_sync_length)
			if flags.debug_scrub then
				local next_sync_tick = clip:get_next_sync_tick(scrub_sync_length)
				print('Scrub queued for sync at tick: ' .. next_sync_tick .. ' (sync_length: ' .. scrub_sync_length .. ')')
			end
		end
	end
end

-- Jump buffer playback to a specific tick (play-through mode)
function BufferSeq:jump_to_tick(tick)
	local buffer = self:get_component()
	local track = buffer.track
	local clip = track and track.clip or nil

	-- If in scrub mode, set scrub_tick; otherwise set clip.tick
	if clip and clip.scrub_mode then
		clip.scrub_tick = tick
		if flags.debug_scrub then
			print('Scrub playback jumped to tick: ' .. tick)
		end
	elseif clip then
		clip.tick = tick
		if flags.debug_clip then
			print('Clip playback jumped to tick: ' .. tick)
		end
	end
end

-- Resync buffer playback with app tick (play-through mode)
function BufferSeq:resync_with_app()
	local buffer = self:get_component()
	local track = buffer.track
	local clip = track and track.clip or nil

	if clip then
		-- Calculate loop-aware position from App.tick
		-- App.tick is a global counter, but clip.tick must respect loop boundaries
		-- Convert App.tick to position within loop: (App.tick % buffer_length) + buffer_start
		clip.tick = ((App.tick - buffer.buffer_start) % buffer.buffer_length) + buffer.buffer_start

		if flags.debug_clip then
			print('Clip playback resynced with app tick: ' .. App.tick .. ' -> clip.tick: ' .. clip.tick)
		end
	end
end

-- Stop scrub playback and restore normal playback
function BufferSeq:stop_scrub()
	if not self.scrub_active then return end

	local buffer = self:get_component()
	local track = buffer.track
	local clip = track and track.clip or nil

	-- Stop scrub and restore previous state
	-- Note: clip.tick is already at the correct position (it's been updating in the background)
	if clip then
		-- Clear any pending scrub stop action
		clip.sync_manager:clear('scrub_stop')
		clip:stop_scrub()
	end

	self.scrub_active = false
	self.scrub_start_tick = nil
	self.scrub_end_tick = nil
	self.scrub_saved_buffer_start = nil

	if flags.debug_scrub then
		print('Scrub stopped')
	end
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

	-- Handle loop point setting (alt mode)
	-- Gesture: Tap alt, then hold two pads simultaneously to set loop start and end points
	if data.type == 'pad' and data.state and data.pad_down and #data.pad_down == 2 and self.mode.alt then
		-- Ensure buffer component exists
		if not buffer then
			print('Cannot set loop: buffer component not available')
			return
		end

		local pad_1 = self.grid:grid_to_index(data) + self.step_offset
		local pad_2 = self.grid:grid_to_index(data.pad_down[1]) + self.step_offset
		local selection_start = math.min(pad_1, pad_2)
		local selection_end = math.max(pad_1, pad_2)

		local step_length = self:get_step_length()
		-- Calculate loop boundaries using 1-based indexing (matching pad_to_tick_range)
		-- pad 1 = ticks 1 to step_length, pad 2 = ticks step_length+1 to 2*step_length, etc.
		local loop_start = (selection_start - 1) * step_length + 1
		local loop_end = selection_end * step_length

		-- Set playback loop points in Clip component (freezes playback to this range)
		local track = buffer.track
		local clip = track and track.clip or nil
		if not clip then
			print('Cannot set loop: clip component not available')
			return
		end

		local loop_length = loop_end - loop_start + 1

		-- Set playback loop and freeze immediately
		clip:set_playback_loop(loop_start, loop_length)
		clip:freeze_buffer()
		if flags.debug_clip then
			print('Loop frozen: ' .. loop_start .. '-' .. loop_end)
		end
	end

	-- Handle pad press (start/update scrub)
	-- Only handle pad presses when not in alt mode (alt mode is for loop setting)
	if data.type == 'pad' and not self.mode.alt then
		-- Track held pad
		if data.state then
			self.held_pads[pad_index] = true
		else
			self.held_pads[pad_index] = nil
			-- If pad is released and no pads are held, immediately stop scrub and resume playback
			if not next(self.held_pads) then
				local track = buffer.track
				local clip = track and track.clip or nil
				-- Clear any pending queued scrub actions
				if clip then clip:clear_pending_scrub() end
			end
		end

		-- Loop mode: use standard scrub behavior
		self:recalculate_scrub_from_held_pads()
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
	local track = buffer.track
	local clip = track and track.clip or nil
	local scrub_active = (clip and clip.scrub_mode) or self.scrub_active
	local scrub_start_step = nil
	local scrub_end_step = nil
	local scrub_playhead_step = nil
	local step_length = self:get_step_length()

	if scrub_active and self.scrub_start_tick and self.scrub_end_tick then
		-- Convert ticks to 1-based step indices (ticks 1-6 = step 1, ticks 7-12 = step 2, etc.)
		scrub_start_step = math.floor((self.scrub_start_tick - 1) / step_length) + 1
		scrub_end_step = math.floor((self.scrub_end_tick - 1) / step_length) + 1
		if clip and clip.scrub_tick then scrub_playhead_step = math.floor((clip.scrub_tick - 1) / step_length) + 1 end
	end

	-- Get the current playback source (live buffer, loaded clip, or frozen buffer)
	local playback_source = nil
	local playback_tick = nil
	local playback_start = buffer.buffer_start
	local playback_length = buffer.buffer_length
	local frozen_active = false -- Track if frozen buffer is active (for visual display)
	local clip_playback_step = nil -- Step index for clip playback (1-based clip ticks converted to step)
	local frozen_playback_step = nil -- Step index for frozen buffer playback

	if clip and clip.current_slot and clip.clip_bank[clip.current_slot] then
		-- Clip is playing - use clip buffer
		local clip_entry = clip.clip_bank[clip.current_slot]
		playback_source = clip_entry.buffer
		-- Clip ticks are 1-based, convert to step index for display
		-- Clips display starting at step 1, so clip.tick maps directly to step
		clip_playback_step = math.floor((clip.tick - 1) / step_length) + 1
		playback_tick = clip.tick
		-- Clips are stored with ticks starting at 1, so they display starting at step 1
		playback_start = 1
		playback_length = clip_entry.length or 0
	elseif clip and clip.buffer_frozen and clip.frozen_buffer then
		-- Frozen buffer is playing - use frozen buffer
		playback_source = clip.frozen_buffer
		-- Frozen buffer uses absolute ticks, convert to step index
		frozen_playback_step = math.floor((clip.tick - 1) / step_length) + 1
		playback_tick = clip.tick
		-- Use frozen buffer's playback loop boundaries
		playback_start = clip.playback_start or buffer.buffer_start
		playback_length = clip.playback_length or buffer.buffer_length
		frozen_active = true
	else
		-- Live buffer is playing
		playback_source = buffer.buffer
		playback_tick = buffer.tick
	end

	-- OPTIMIZATION: Zero event scanning - just show playhead and range highlighting
	-- No buffer scanning means maximum performance regardless of buffer size
	local is_actively_playing = clip and clip:is_actively_playing() or false

	grid:for_each(function(s, x, y, i)
		local pad = 0

		if self.blink_state then pad = pad | BLINK end

		-- Determine the global step index for this LED pad based on the display offset
		local global_step = i + self.step_offset
		-- Calculate the tick position of this step (absolute tick position)
		-- This is used for measure calculation, so we need the actual tick position
		-- step_tick is the START tick of this step (1-based: step 1 = tick 1, step 2 = tick step_length+1)
		-- This matches pad_to_tick_range calculation
		local step_tick = (global_step - 1) * step_length + 1

		-- No event scanning - we just show playhead and range highlighting
		-- When clip/frozen/scrub is playing, we highlight the entire range regardless of events

		-- Use appropriate loop boundaries for display
		-- For clips: show clip's loop boundaries (starting at step 1, length in steps)
		-- For frozen buffer: show frozen buffer's loop boundaries
		-- For live buffer: show buffer's loop boundaries
		-- Use (tick - 1) formula to match step calculation: step = floor((tick - 1) / step_length) + 1
		local loop_start_index, loop_end_index
		if clip and clip.current_slot and clip.clip_bank[clip.current_slot] then
			-- Clip is playing: clips start at step 1, end at step (length/step_length)
			local clip_entry = clip.clip_bank[clip.current_slot]
			local clip_length = clip_entry.length or 0
			loop_start_index = 1
			-- Convert clip length (in ticks) to step index
			-- clip_length is the last tick, so use (clip_length - 1) to get the correct step
			loop_end_index = math.floor((clip_length - 1) / step_length) + 1
		elseif frozen_active and clip and clip.playback_start and clip.playback_length then
			-- Frozen buffer: use frozen buffer's playback loop boundaries (convert ticks to steps)
			local loop_start = clip.playback_start
			local loop_end = clip.playback_start + clip.playback_length - 1
			loop_start_index = math.floor((loop_start - 1) / step_length) + 1
			loop_end_index = math.floor((loop_end - 1) / step_length) + 1
		else
			-- Live buffer: use buffer's loop boundaries (convert ticks to steps)
			local loop_start = buffer.buffer_start
			local loop_end = buffer.buffer_start + buffer.buffer_length - 1
			loop_start_index = math.floor((loop_start - 1) / step_length) + 1
			loop_end_index = math.floor((loop_end - 1) / step_length) + 1
		end

		if global_step == loop_start_index or global_step == loop_end_index then pad = pad | LOOP_END end

		-- Show recording playhead (always from buffer.tick)
		local record_step = math.floor((buffer.tick - 1) / step_length) + 1
		if record_step == global_step then pad = pad | RECORD_STEP end

		-- Show playback playhead based on playback source
		-- For clips: use clip_playback_step (1-based clip ticks converted to step)
		--   Clips are displayed starting at step 1, so clip_playback_step should match global_step
		--   when viewing the clip's range. However, if step_offset moves the view, we need to
		--   check if the current global_step corresponds to the clip's playback position.
		--   Since clips loop, we need to account for wrapping within the clip's range.
		-- For frozen buffer: use frozen_playback_step (absolute ticks converted to step)
		-- For live buffer: use buffer.tick converted to step
		if clip_playback_step then
			-- Clip is playing: show clip playback position
			-- clip_playback_step is 1-based (clip's coordinate system, step 1, 2, 3...)
			-- global_step is i + step_offset (absolute step position in buffer's coordinate system)
			-- Clips always display starting at step 1 and loop within their range
			-- The issue: when clip loops, clip_playback_step wraps to 1, but global_step continues
			-- from buffer's position, so they only match when buffer also cycles back to step 1
			-- Solution: Wrap global_step to the clip's range for comparison
			local clip_entry = clip.clip_bank[clip.current_slot]
			local clip_length = clip_entry.length or 0
			local clip_end_step = math.floor((clip_length - 1) / step_length) + 1

			-- Wrap global_step to clip's range (1 to clip_end_step) for comparison
			-- This ensures the playhead shows correctly on every loop, not just when buffer cycles back
			-- Formula: ((global_step - 1) % clip_end_step) + 1
			-- Example: if clip_end_step = 48 and global_step = 49, relative_step = 1
			--          if clip_end_step = 48 and global_step = 97, relative_step = 1
			local relative_step = ((global_step - 1) % clip_end_step) + 1

			-- Show playhead when clip_playback_step matches the wrapped relative position
			-- BUT only show it on pads within the clip's visible range (1 to clip_end_step)
			-- This prevents showing the playhead on multiple pads when the clip loops
			-- (e.g., if clip_end_step=2, only show on pads 1-2, not on pads 3-4 which wrap to 1-2)
			if clip_playback_step == relative_step and i <= clip_end_step then pad = pad | STEP end
		elseif frozen_playback_step then
			-- Frozen buffer is playing: show frozen buffer playback position
			if frozen_playback_step == global_step then pad = pad | STEP end
		elseif playback_tick then
			-- Live buffer is playing: show buffer playback position (only if different from record position)
			local playback_step = math.floor((playback_tick - 1) / step_length) + 1
			if playback_step == global_step and playback_step ~= record_step then pad = pad | STEP end
		end

		-- Handle scrub mode
		if scrub_active then
			-- Highlight scrub range steps
			if scrub_start_step and scrub_end_step and global_step >= scrub_start_step and global_step <= scrub_end_step then pad = pad | SCRUB end
			-- Show scrub playhead (always show when scrub is active, regardless of App.playing)
			-- scrub_tick is absolute (buffer coordinate space), so convert to step index
			if scrub_playhead_step and scrub_playhead_step == global_step then pad = pad | STEP end
		end

		-- Handle frozen buffer mode (similar visual treatment to scrub mode)
		if frozen_active then
			-- Highlight frozen buffer range steps (same visual as scrub)
			if global_step >= loop_start_index and global_step <= loop_end_index then pad = pad | SCRUB end
		end

		-- Handle loaded clip range highlighting (when clip is loaded)
		-- This provides visual feedback about the clip's range, similar to scrub/frozen
		-- Show range both when actively playing and when not actively playing
		if clip and clip.current_slot and clip.clip_bank[clip.current_slot] then
			-- Highlight clip range steps (same visual as scrub/frozen)
			if global_step >= loop_start_index and global_step <= loop_end_index then pad = pad | SCRUB end
		end

		-- Mark steps outside loop bounds (before loop start or after loop end)
		local is_outside = global_step < loop_start_index or global_step > loop_end_index
		if is_outside then pad = pad | OUTSIDE end

		-- Check if playback is active (buffer playback OR clip playing OR frozen buffer)
		local playback_active = false
		if clip and clip.current_slot and clip.clip_bank[clip.current_slot] then
			-- Clip is loaded and playing
			playback_active = true
		elseif frozen_active then
			-- Frozen buffer playback
			playback_active = true
		end

		-- Calculate current playback step for determining passed steps
		-- This is used to show dim white for steps that have already passed
		-- Only show dim white if: step has passed AND (pad is outside loop OR clip is not actively playing)
		local step_has_passed = false
		if App.playing then
			if scrub_playhead_step then
				-- Scrub mode: compare global_step to scrub playhead (absolute coordinates)
				step_has_passed = global_step < scrub_playhead_step
			elseif clip_playback_step then
				-- Clip playback: need to handle coordinate system differences
				-- Clips use relative coordinates (starting at step 1), global_step is absolute
				if global_step >= loop_start_index and global_step <= loop_end_index then
					-- Within clip range: compare relative positions
					local clip_entry = clip.clip_bank[clip.current_slot]
					local clip_length = clip_entry.length or 0
					local clip_end_step = math.floor((clip_length - 1) / step_length) + 1
					local relative_global_step = ((global_step - 1) % clip_end_step) + 1
					step_has_passed = relative_global_step < clip_playback_step
				else
					-- Outside clip range: can't determine if passed (clip doesn't extend here)
					step_has_passed = false
				end
			elseif frozen_playback_step then
				-- Frozen buffer: compare global_step to frozen playback position (absolute)
				step_has_passed = global_step < frozen_playback_step
			elseif playback_tick then
				-- Live buffer: compare global_step to playback position (absolute)
				local playback_step = math.floor((playback_tick - 1) / step_length) + 1
				step_has_passed = global_step < playback_step
			else
				-- Fallback to record step if no playback position
				step_has_passed = global_step < record_step
			end
		end

		local color = 123

		-- Use rainbow colors to show measure boundaries (no event scanning)
		-- Calculate rainbow color index based on step_tick (measure position)
		local color_index = self:get_rainbow_color_index(step_tick, nil)

		-- Handle blink mode first (like presetseq)
		if pad & (BLINK | OUTSIDE) == (BLINK | OUTSIDE) then
			-- Blink steps outside the loop
			if self.blink_state then
				color = { 5, 5, 5 }
			else
				color = 0
			end
		-- Handle passed steps with dim white (only if outside loop OR not actively playing)
		elseif step_has_passed and (is_outside or not is_actively_playing) then
			-- Show passed steps in dim white
			color = { 5, 5, 5 }
		-- Handle out-of-bounds steps (when not blinking and not passed)
		elseif is_outside then
			color = 0
		-- When playback is OFF
		elseif not playback_active then
			-- Show playback playhead (scrub/clip/frozen) with rainbow color (if set)
			if pad & STEP > 0 then
				color = Grid.rainbow_on[color_index]
			-- Show recording playhead with rainbow color
			elseif pad & RECORD_STEP > 0 then
				color = Grid.rainbow_on[color_index]
			-- Highlight range if scrub/frozen/clip is active (even if not playing) with rainbow colors
			elseif pad & SCRUB > 0 then
				color = Grid.rainbow_off[color_index]
			else
				color = 0
			end
		-- When playback is ON
		else
			-- Show playhead (playback position) with bright rainbow color
			if pad & STEP > 0 then
				color = Grid.rainbow_on[color_index]
			-- Show recording playhead with bright rainbow color (if different from playback)
			elseif pad & RECORD_STEP > 0 then
				color = Grid.rainbow_on[color_index]
			-- Highlight range (scrub/frozen/clip) with dim rainbow color
			elseif pad & SCRUB > 0 then
				color = Grid.rainbow_off[color_index]
			else
				color = 0
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
					-- Alt mode active but blink not started yet
					color = { 5, 5, 5 }
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
		-- Check all playback sources: clip.tick, scrub_tick, frozen buffer, or buffer.tick
		local track = buffer.track
		local clip = track and track.clip or nil
		local current_tick = buffer.tick
		local current_display_step = math.floor((current_tick - 1) / display_step_length) + 1

		-- Prioritize scrub playback position for refresh
		if clip and clip.scrub_mode and clip.scrub_tick then
			current_tick = clip.scrub_tick
			current_display_step = math.floor((current_tick - 1) / display_step_length) + 1
		-- Then check clip playback position
		elseif clip and clip.current_slot and clip.clip_bank[clip.current_slot] then
			-- Clip ticks are 1-based, convert to step for comparison
			current_display_step = math.floor((clip.tick - 1) / display_step_length) + 1
		-- Then check frozen buffer playback position
		elseif clip and clip.buffer_frozen and clip.tick then
			current_tick = clip.tick
			current_display_step = math.floor((current_tick - 1) / display_step_length) + 1
		end

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
		-- Alt + Left: Clear buffer
		if data.type == 'left' then
			if buffer then
				buffer:clear_buffer()
				print('Buffer cleared for track ' .. track.id)
				-- Refresh grid display
				self:set_grid(buffer)
			end
			-- Reset alt mode
			self.mode:reset_alt()
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
	end
end

function BufferSeq:alt_event(data)
	if data.state and self.mode.alt then
		-- Alt mode activated
		local buffer = self:get_component()
		local track = buffer and buffer.track or nil
		local clip = track and track.clip or nil

		-- If we're already in scrub mode, freeze the current scrub boundaries seamlessly
		if self.scrub_active and clip and self.scrub_start_tick and self.scrub_end_tick then
			local loop_start = self.scrub_start_tick
			local loop_length = self.scrub_end_tick - self.scrub_start_tick + 1

			-- Freeze immediately
			clip:set_playback_loop(loop_start, loop_length)
			clip:freeze_buffer()
			if flags.debug_scrub then
				print('Scrub frozen to loop: ' .. loop_start .. '-' .. self.scrub_end_tick)
			end

			-- Stop scrub mode (playback now comes from frozen_buffer)
			self:stop_scrub()
			self.held_pads = {}
		else
			-- Normal alt mode activation - start blinking to show loop end points
			self.index = nil
			self.mode:cancel_context()
			self:start_blink()
			-- Clear any held pads and stop scrub when entering alt mode
			if self.scrub_active then
				self:stop_scrub()
				self.held_pads = {}
			end
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

-- Update row pads to show current track
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
			if track_id == current_track then
				-- Current track: white (brightness 1)
				self.mode.row_pads.led[9][row_y] = 1
			end
		end
	end

	-- Refresh both grid and display
	self.mode.row_pads:refresh('BufferSeq:update_row_pads')
	App.screen_dirty = true
end

return BufferSeq
