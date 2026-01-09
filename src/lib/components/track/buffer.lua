local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')

-- Buffer component handles recording and playback of MIDI events
-- Separated from Auto component for clear separation of concerns:
-- Buffer = Recording/Playback, Auto = Automation

local Buffer = {}
Buffer.name = 'buffer'
Buffer.__index = Buffer
setmetatable(Buffer, { __index = TrackComponent })

function Buffer:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
	o:set(o)
	return o
end

function Buffer:set(o)
	self.id = o.id or 1

	-- Buffer's own timing state (independent from Auto)
	self.tick = o.tick or 0 -- Buffer's own playback position in ticks
	self.seq_start = o.seq_start or 1
	self.seq_length = App.ppqn * 16 -- Default 4 bars
	self.playing = false
	self.enabled = true

	-- Buffer step length (in ticks) - defines duration of one "step"
	self.buffer_step_length = o.buffer_step_length or 6

	-- Buffer playback settings (defaults - will be overridden by params)
	self.buffer_playback = o.buffer_playback or false -- Default off for silent recording

	-- Double buffer architecture for recording/playback separation
	-- buffer_write: Always record to this buffer
	-- buffer_read: Always playback from this buffer
	-- Swap happens at step boundaries (not loop boundaries) for immediate feedback
	self.buffer_write = {} -- Buffer being recorded to
	self.buffer_read = {} -- Buffer being played back
	self.last_step_index = nil -- Track step transitions for swap timing

	-- Migrate existing buffer data if present (backward compatibility)
	-- This handles migration from old auto.seq[tick].buffer structure
	if o.buffer_write then
		self.buffer_write = o.buffer_write
	end
	if o.buffer_read then
		self.buffer_read = o.buffer_read
	end

	-- Overwrite mode tracking: tracks which steps have been cleared in current loop iteration
	-- Key: step_index (step number within loop), Value: true
	self.overwrite_cleared_steps = {}

	-- Scrub playback state
	self.scrub_mode = false
	self.scrub_tick = nil -- Separate tick counter for scrub mode playback
	self.scrub_start = nil
	self.scrub_end = nil
	self.scrub_length = nil
	self.scrub_loop = false
end

-- Helper: Get current step index (0-based) from current tick
function Buffer:get_current_step_index()
	return math.floor(self.tick / self.buffer_step_length)
end

-- Helper: Convert tick to step index (0-based)
function Buffer:tick_to_step_index(tick)
	return math.floor(tick / self.buffer_step_length)
end

-- Helper: Convert step index to tick range (returns start_tick, end_tick inclusive)
function Buffer:step_index_to_tick_range(step_index)
	local start_tick = step_index * self.buffer_step_length
	local end_tick = start_tick + self.buffer_step_length - 1
	return start_tick, end_tick
end

-- Helper: Convert step index to start tick
function Buffer:step_index_to_start_tick(step_index)
	return step_index * self.buffer_step_length
end

-- Swap buffer step: Copy buffer_write to buffer_read for a single step
-- Called on step transitions to provide immediate feedback (within one step)
-- Only swaps ticks within both step boundaries and loop boundaries
function Buffer:swap_buffer_step(step_index)
	if not self.track.armed then return end
	local start_tick, end_tick = self:step_index_to_tick_range(step_index)

	-- Clamp to loop boundaries
	local loop_start = self.seq_start
	local loop_end = self.seq_start + self.seq_length - 1
	start_tick = math.max(start_tick, loop_start)
	end_tick = math.min(end_tick, loop_end)

	-- Clear old read data for this step
	for tick = start_tick, end_tick do
		self.buffer_read[tick] = nil
	end

	-- Copy write to read for this step (shallow copy - tables share event references)
	for tick = start_tick, end_tick do
		if self.buffer_write[tick] then
			self.buffer_read[tick] = self.buffer_write[tick]
		end
	end
end

-- Record a MIDI event to the buffer write lane at the current tick
-- Events wrap around within the buffer loop boundaries (seq_start to seq_start + seq_length)
-- Overwrite mode clearing is handled in transport_event when entering new steps
-- Records to buffer_write only - buffer_read is updated via step-based swapping
function Buffer:record_buffer(midi_event)
	if not self.track.armed then return end

	if midi_event.tick == self.tick then return end

	-- Wrap tick within the buffer loop boundaries
	local relative_tick = self.tick - self.seq_start
	local tick = self.seq_start + (relative_tick % self.seq_length)

	-- Initialize buffer_write table for this tick if needed
	if not self.buffer_write[tick] then
		self.buffer_write[tick] = {}
	end

	midi_event.buffer_sent = nil
	midi_event.tick = self.tick

	-- Store the event (multiple events can exist at same tick)
	table.insert(self.buffer_write[tick], midi_event)
end

-- Clear buffer events for a single tick (used for overwrite mode)
-- Only clears buffer_write (not buffer_read, which continues playing)
function Buffer:clear_buffer_tick(tick)
	if self.buffer_write[tick] then
		self.buffer_write[tick] = nil
	end
end

-- Clear buffer events for an entire step range (all ticks in a step)
-- Used for overwrite mode when entering a new step
-- Only clears buffer_write (not buffer_read, which continues playing)
function Buffer:clear_buffer_step(step_index)
	-- Calculate the step boundaries within the loop
	local step_start = self.seq_start + (step_index * self.buffer_step_length)
	local step_end = math.min(step_start + self.buffer_step_length - 1, self.seq_start + self.seq_length - 1)

	-- Clear all ticks in this step range from write buffer
	for tick = step_start, step_end do
		if self.buffer_write[tick] then
			self.buffer_write[tick] = nil
		end
	end
end

-- Clear both buffer_write and buffer_read
function Buffer:clear_buffer()
	self.buffer_write = {}
	self.buffer_read = {}
end

function Buffer:set_loop(loop_start, loop_end)
	self.seq_start = loop_start
	self.seq_length = loop_end - loop_start + 1
	-- Reset overwrite tracking when loop boundaries change
	self.overwrite_cleared_steps = {}
end

-- Transport Event Handling
function Buffer:transport_event(data)
	if data.type == 'start' then
		self.playing = true
		self.tick = 0
		-- Clear any lingering buffer notes from previous playback
		self:kill_notes()
		-- Reset overwrite tracking for new playback
		self.overwrite_cleared_steps = {}
	elseif data.type == 'stop' then
		self.playing = false
		self.tick = 0
		-- Kill all active buffer notes to prevent stuck notes
		self:kill_notes()
	elseif data.type == 'clock' and self.playing then
		-- Detect step transitions for buffer swapping
		local current_step_index = self:tick_to_step_index(self.tick)

		-- Swap on step exit (when entering new step, swap the completed step)
		if self.last_step_index and current_step_index ~= self.last_step_index then
			if not self.scrub_mode then
				self:swap_buffer_step(self.last_step_index)
			elseif self.last_step_index < self:tick_to_step_index(self.scrub_start) or
			       self.last_step_index > self:tick_to_step_index(self.scrub_end) then
				self:swap_buffer_step(self.last_step_index)
			end
		end

		-- Update last_step_index for next iteration
		self.last_step_index = current_step_index

		-- Offset run ticks ahead of current tick
		local run_offset = 1

		-- Calculate the next tick for normal playback
		local next_tick = self.tick + run_offset

		-- Always update buffer.tick based on normal playback rules (even during scrub mode)
		-- This ensures playback can seamlessly resume when scrub stops
		if next_tick >= self.seq_start + self.seq_length then
			-- Handle buffer recording modes at loop boundary
			if self.track.armed then
				-- One-shot mode: disarm track after completing loop
				if not App.buffer_loop then
					self.track.armed = false
					Registry.set('track_' .. self.track.id .. '_armed', 0, 'buffer_oneshot')
				end
			end

			-- Reset overwrite tracking for new loop iteration
			-- This allows overwrite mode to clear events again on the next loop
			self.overwrite_cleared_steps = {}

			-- Emit loop boundary event
			self:emit('loop_boundary')

			next_tick = self.seq_start
			self.tick = self.seq_start
		else
			self.tick = self.tick + 1
		end

		-- Handle overwrite mode step clearing after handling loop boundary
		-- In overwrite mode, when entering a new step and track is armed, clear that step
		if not App.buffer_overdub and not self.buffer_playback then
			-- Calculate which step index we're entering (within the loop)
			local relative_next_tick = next_tick - self.seq_start
			-- Ensure we're within bounds (should always be after loop boundary handling)
			if relative_next_tick >= 0 and relative_next_tick < self.seq_length then
				local step_index = math.floor(relative_next_tick / self.buffer_step_length)

				-- Clear the step if we haven't cleared it in this loop iteration
				if not self.overwrite_cleared_steps[step_index] then
					self:clear_buffer_step(step_index)
					self.overwrite_cleared_steps[step_index] = true
				end
			end
		end

		-- Handle scrub mode separately from normal playback
		if self.scrub_mode then
			-- Update scrub_tick for scrub playback
			local next_scrub_tick = (self.scrub_tick or self.scrub_start) + run_offset

			if self.scrub_loop and next_scrub_tick > self.scrub_end then
				-- Loop back to scrub start
				self:kill_notes()
				next_scrub_tick = self.scrub_start
				self.scrub_tick = self.scrub_start
			elseif not self.scrub_loop and next_scrub_tick > self.seq_start + self.seq_length then
				-- Play-thru mode, plays through full buffer
				self:kill_notes()
				self.scrub_tick = self.seq_start
			else
				self.scrub_tick = next_scrub_tick
			end

			-- Only run buffer events during scrub (from buffer_read, using scrub_tick)
			if self.buffer_read[self.scrub_tick] then
				self:run_buffer(self.buffer_read[self.scrub_tick])
			end
		else
			if not self.buffer_playback then
				self.track:emit('mute_input', false)
			end

			if self.buffer_read[next_tick] then
				self:run_buffer(self.buffer_read[next_tick])
			end
		end
	end

	return data
end

-- Playback buffer events directly to output (bypasses processing chain)
-- Respects per-track buffer_playback param, scrub mode settings
function Buffer:run_buffer(events)
	if not self.track.output_device then return end

	-- Check if buffer playback is enabled for this track (via param)
	-- OR if scrub mode is active (grid-triggered playback)
	local playback_enabled = false

	if self.scrub_mode or self.buffer_playback then
		-- Scrub mode always allows playback (grid-triggered)
		self.track:emit('mute_input', true)
		playback_enabled = true
	elseif App.buffer_overdub and self.track.armed then
		self.track:emit('mute_input', false)
		playback_enabled = true
	end

	if not playback_enabled then return end

	for _, event in ipairs(events) do
		local ch = event.ch or self.track.midi_out

		local midi_msg = {}

		for k, v in pairs(event) do
			midi_msg[k] = v
		end

		midi_msg.buffer_sent = App.tick

		self.track:send_input(midi_msg)
	end
end

-- Send note_off for all active buffer notes (prevents stuck notes)
function Buffer:kill_notes()
	if not self.track.output_device then return end
	self.track.output_device:kill()
end

-- Scrub playback: temporarily play a range of the buffer
-- loop_mode: true = loop the range, false = play through once then stop
function Buffer:start_scrub(start_tick, end_tick, loop_mode)
	-- Kill any currently playing buffer notes before scrub
	self:kill_notes()

	-- Store scrub state
	self.scrub_mode = true
	self.scrub_loop = loop_mode
	self.scrub_start = start_tick
	self.scrub_end = end_tick
	self.scrub_length = end_tick - start_tick + 1

	-- Jump to scrub start position
	self.scrub_tick = start_tick
end

-- Update scrub range (for multi-pad selection)
-- If current tick is outside new range, jump to stay within boundaries
function Buffer:update_scrub(start_tick, end_tick)
	if not self.scrub_mode then return end

	-- Kill notes to prevent stuck notes when range changes
	self:kill_notes()

	-- Update scrub boundaries
	self.scrub_start = start_tick
	self.scrub_end = end_tick
	self.scrub_length = end_tick - start_tick + 1

	-- If current scrub_tick is now outside the new scrub range, jump to scrub start
	if not self.scrub_tick or self.scrub_tick < start_tick or self.scrub_tick > end_tick then
		self.scrub_tick = start_tick
	end
end

-- Stop scrub and restore normal playback
function Buffer:stop_scrub(saved_tick, saved_seq_start, saved_seq_length)
	self.track:emit('mute_input', false)
	if not self.scrub_mode then return end

	-- Kill any scrub notes
	self:kill_notes()

	-- Restore previous state
	self.scrub_mode = false
	self.scrub_loop = false
	self.scrub_start = nil
	self.scrub_end = nil
	self.scrub_length = nil
	self.scrub_tick = nil

	-- Restore loop points if they were changed
	-- Note: buffer.tick is already at the correct position (it's been updating in the background)
	if saved_seq_start then
		self.seq_start = saved_seq_start
	end
	if saved_seq_length then
		self.seq_length = saved_seq_length
	end
end

return Buffer
