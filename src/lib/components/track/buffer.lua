local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')

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
	-- Add at the top of buffer.lua after other local declarations
	self.timing_stats = {
		swap_times = {},
		transport_times = {},
		record_times = {},
		max_samples = 100, -- Keep last 100 samples
	}
	-- Buffer's own timing state (independent from Auto)
	self.tick = o.tick or 0 -- Buffer's own playback position in ticks
	self.seq_start = o.seq_start or 1
	self.seq_length = o.seq_length or (App.ppqn * 256) -- Default 64 bars
	self.playing = false
	self.enabled = true

	-- Buffer step length (in ticks) - defines duration of one "step"
	self.buffer_step_length = o.buffer_step_length or 6

	-- Buffer playback settings (defaults - will be overridden by params)
	self.buffer_playback = o.buffer_playback or false -- Default off for silent recording
	self.playback_mode = o.playback_mode or 1 -- Default is Input

	-- Double buffer architecture for recording/playback separation
	-- buffer_write: Always record to this buffer
	-- buffer_read: Always playback from this buffer
	-- Swap happens at step boundaries (not loop boundaries) for immediate feedback
	self.buffer_write = {} -- Buffer being recorded to
	self.buffer_read = {} -- Buffer being played back
	self.last_step_index = nil -- Track step transitions for swap timing

	-- Migrate existing buffer data if present (backward compatibility)
	-- This handles migration from old auto.seq[tick].buffer structure
	if o.buffer_write then self.buffer_write = o.buffer_write end
	if o.buffer_read then self.buffer_read = o.buffer_read end

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
function Buffer:get_current_step_index() return math.floor(self.tick / self.buffer_step_length) end

-- Helper: Convert tick to step index (0-based)
function Buffer:tick_to_step_index(tick) return math.floor(tick / self.buffer_step_length) end

-- Helper: Convert step index to tick range (returns start_tick, end_tick inclusive)
function Buffer:step_index_to_tick_range(step_index)
	local start_tick = step_index * self.buffer_step_length
	local end_tick = start_tick + self.buffer_step_length - 1
	return start_tick, end_tick
end

-- Helper: Convert step index to start tick
function Buffer:step_index_to_start_tick(step_index) return step_index * self.buffer_step_length end

-- Swap buffer step: Copy buffer_write to buffer_read for a single step
-- Called on step transitions to provide immediate feedback (within one step)
-- Only swaps ticks within both step boundaries and loop boundaries
-- Optimized to only iterate over ticks that contain data (sparse table optimization)
function Buffer:swap_buffer_step(step_index)
	if not self.track.armed then return end

	-- Timing tracking (conditional on flag)
	local start_time = flags.buffer_timing_stats and util.time() or nil
	local start_tick, end_tick = self:step_index_to_tick_range(step_index)

	-- Clamp to loop boundaries
	local loop_start = self.seq_start
	local loop_end = self.seq_start + self.seq_length - 1
	start_tick = math.max(start_tick, loop_start)
	end_tick = math.min(end_tick, loop_end)

	-- Optimized: Only iterate over ticks that actually exist in buffer_write
	-- This avoids iterating over empty ticks, which is much faster for sparse buffers
	for tick, events in pairs(self.buffer_write) do
		-- Only process ticks within our step range
		if tick >= start_tick and tick <= end_tick then
			-- Clear old read data for this tick (if it exists)
			if self.buffer_read[tick] then self.buffer_read[tick] = nil end
			-- Copy write to read (shallow copy - tables share event references)
			self.buffer_read[tick] = events
		end
	end

	-- Also clear any buffer_read ticks in this range that don't have corresponding buffer_write data
	-- This handles the case where buffer_read has data that was removed from buffer_write
	for tick, events in pairs(self.buffer_read) do
		if tick >= start_tick and tick <= end_tick then
			-- If this tick doesn't exist in buffer_write, clear it from buffer_read
			if not self.buffer_write[tick] then self.buffer_read[tick] = nil end
		end
	end

	-- Record timing (conditional on flag)
	if flags.buffer_timing_stats then
		local elapsed = (util.time() - start_time) * 1000 -- Convert to ms
		table.insert(self.timing_stats.swap_times, elapsed)
		if #self.timing_stats.swap_times > self.timing_stats.max_samples then table.remove(self.timing_stats.swap_times, 1) end
	end
end

-- Record a MIDI event to the buffer write lane at the current tick
-- Events wrap around within the buffer loop boundaries (seq_start to seq_start + seq_length)
-- Overwrite mode clearing is handled in transport_event when entering new steps
-- Records to buffer_write only - buffer_read is updated via step-based swapping
function Buffer:record_buffer(midi_event)
	if not self.track.armed then return end

	-- Timing tracking (conditional on flag)
	local record_start = flags.buffer_timing_stats and util.time() or nil

	if midi_event.tick == self.tick then return end

	-- Wrap tick within the buffer loop boundaries
	local relative_tick = self.tick - self.seq_start
	local tick = self.seq_start + (relative_tick % self.seq_length)

	-- Initialize buffer_write table for this tick if needed
	if not self.buffer_write[tick] then self.buffer_write[tick] = {} end

	midi_event.buffer_sent = nil
	midi_event.tick = self.tick

	-- Store the event (multiple events can exist at same tick)
	table.insert(self.buffer_write[tick], midi_event)

	-- Record timing (conditional on flag)
	if flags.buffer_timing_stats and record_start then
		local record_elapsed = (util.time() - record_start) * 1000
		table.insert(self.timing_stats.record_times, record_elapsed)
		if #self.timing_stats.record_times > self.timing_stats.max_samples then table.remove(self.timing_stats.record_times, 1) end
	end
end

-- Clear buffer events for a single tick (used for overwrite mode)
-- Only clears buffer_write (not buffer_read, which continues playing)
function Buffer:clear_buffer_tick(tick)
	if self.buffer_write[tick] then self.buffer_write[tick] = nil end
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
		if self.buffer_write[tick] then self.buffer_write[tick] = nil end
	end
end

-- Clear both buffer_write and buffer_read
function Buffer:clear_buffer()
	self.buffer_write = {}
	self.buffer_read = {}
	self:emit('clear_buffer')
end

function Buffer:set_loop(loop_start, loop_end)
	self.seq_start = loop_start
	self.seq_length = loop_end - loop_start + 1
	-- Reset overwrite tracking when loop boundaries change
	self.overwrite_cleared_steps = {}

	-- Ensure buffer.tick is within the new loop bounds
	-- If current tick is outside new loop bounds, set it to loop start
	-- This ensures playback always starts within the loop when loop points are set
	if self.tick < loop_start or self.tick > loop_end then self.tick = loop_start end
end

-- Transport Event Handling
function Buffer:transport_event(data)
	-- Timing tracking (conditional on flag)
	local transport_start = flags.buffer_timing_stats and util.time() or nil

	if data.type == 'start' then
		self.playing = true
		-- Start playback at loop start (not buffer start) to respect loop boundaries
		-- Unless in scrub mode, in which case scrub_tick is already set
		if not self.scrub_mode then self.tick = self.seq_start end
		-- Clear any lingering buffer notes from previous playback
		self:kill_notes()
		-- Reset overwrite tracking for new playback
		self.overwrite_cleared_steps = {}
	elseif data.type == 'stop' then
		self.playing = false
		-- Reset to loop start (not buffer start) when stopping
		if not self.scrub_mode then self.tick = self.seq_start end
		-- Kill all active buffer notes to prevent stuck notes
		self:kill_notes()
	elseif data.type == 'clock' and self.playing then
		-- Ensure tick is within loop bounds (safety check for normal playback)
		-- This handles cases where loop points changed during playback or tick got out of sync
		if not self.scrub_mode then
			if self.tick < self.seq_start or self.tick >= self.seq_start + self.seq_length then
				-- Wrap tick to be within loop bounds
				local relative_tick = (self.tick - self.seq_start) % self.seq_length
				if relative_tick < 0 then relative_tick = relative_tick + self.seq_length end
				self.tick = self.seq_start + relative_tick
			end
		end

		-- Detect step transitions for buffer swapping
		local current_step_index = self:tick_to_step_index(self.tick)

		-- Swap on step exit (when entering new step, swap the completed step)
		if self.last_step_index and current_step_index ~= self.last_step_index and self.track.armed then
			if not self.scrub_mode then
				self:swap_buffer_step(self.last_step_index)
			elseif self.last_step_index < self:tick_to_step_index(self.scrub_start) or self.last_step_index > self:tick_to_step_index(self.scrub_end) then
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
			if self.buffer_read[self.scrub_tick] then self:run_buffer(self.buffer_read[self.scrub_tick]) end
		else
			if not self.buffer_playback then self.track:emit('mute_input', false) end

			if self.buffer_read[next_tick] then self:run_buffer(self.buffer_read[next_tick]) end
		end

		-- Record transport timing (conditional on flag)
		if flags.buffer_timing_stats and transport_start then
			local transport_elapsed = (util.time() - transport_start) * 1000
			table.insert(self.timing_stats.transport_times, transport_elapsed)
			if #self.timing_stats.transport_times > self.timing_stats.max_samples then table.remove(self.timing_stats.transport_times, 1) end
		end
	end

	return data
end

-- Add diagnostic function to print stats
function Buffer:print_timing()
	local function avg(times)
		if #times == 0 then return 0 end
		local sum = 0
		for _, t in ipairs(times) do
			sum = sum + t
		end
		return sum / #times
	end

	local function max(times)
		if #times == 0 then return 0 end
		local m = 0
		for _, t in ipairs(times) do
			if t > m then m = t end
		end
		return m
	end

	print(
		string.format(
			'Buffer Timing Stats (step_length=%d):\n'
				.. '  Swap: avg=%.3fms max=%.3fms (samples=%d)\n'
				.. '  Transport: avg=%.3fms max=%.3fms (samples=%d)\n'
				.. '  Record: avg=%.3fms max=%.3fms (samples=%d)',
			self.buffer_step_length,
			avg(self.timing_stats.swap_times),
			max(self.timing_stats.swap_times),
			#self.timing_stats.swap_times,
			avg(self.timing_stats.transport_times),
			max(self.timing_stats.transport_times),
			#self.timing_stats.transport_times,
			avg(self.timing_stats.record_times),
			max(self.timing_stats.record_times),
			#self.timing_stats.record_times
		)
	)
end

-- Playback buffer events
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
		if self.playback_mode == 1 then
			self.track:send(midi_msg)
		elseif self.playback_mode == 2 then
			self.track:send_input(midi_msg)
		elseif self.playback_mode == 3 then
			self.track:send_output(midi_msg)
		elseif self.playback_mode == 4 then
			self.track:send_scale(midi_msg)
		end
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
	if not self.scrub_tick or self.scrub_tick < start_tick or self.scrub_tick > end_tick then self.scrub_tick = start_tick end
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
	if saved_seq_start then self.seq_start = saved_seq_start end
	if saved_seq_length then self.seq_length = saved_seq_length end
end

return Buffer
