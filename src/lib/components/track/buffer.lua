local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')
local SequenceUtils = require(path_name .. 'utilities/sequence_utils')
local TimingConstants = require(path_name .. 'utilities/timing_constants')
local EventStore = require(path_name .. 'utilities/event_store')

-- Buffer component handles recording of MIDI events only
-- Separated from Auto and Clip components for clear separation of concerns:
-- Buffer = Recording only (silent, continuous recording), Clip = Playback, Auto = Automation

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
		transport_times = {},
		record_times = {},
		max_samples = 100, -- Keep last 100 samples
	}
	-- Buffer's own timing state (independent from Auto)
	self.tick = o.tick or 0 -- Buffer's recording position in ticks (continuously running)
	self.buffer_start = o.buffer_start or 1 -- Starting tick of the buffer
	self.buffer_length = o.buffer_length or TimingConstants.get_default_buffer_length() -- Static buffer length (64 bars default)
	self.playing = false
	self.enabled = true

	-- Buffer only records - Clip component handles all playback

	-- Single buffer architecture: Buffer continuously records, Clip handles playback via PlaybackSource abstraction
	-- Buffer loops back over itself at buffer_start + buffer_length
	-- EventStore provides efficient range queries and maintains sorted tick index
	self.store = EventStore.new()

	-- self.buffer points to store's internal events table
	-- This allows existing code to access buffer[tick] directly
	self.buffer = self.store.events

	-- Overwrite mode tracking: tracks which steps have been cleared in current loop iteration
	-- Key: step_index (step number within loop), Value: true
	self.overwrite_cleared_steps = {}

	-- Track open notes per channel+note while a note is held.
	-- Key: ch * 128 + note (numeric, no allocation per lookup).
	-- Value: { raw_on = tick, quantized_on = tick, vel_on = velocity }
	-- vel_on is stamped onto the closing note_off so synthetic note_ons at loop
	-- boundaries (see EventStore.fix_note_pairs_in_sparse) inherit the original
	-- attack velocity instead of the note_off release velocity (often 0 -> silent).
	self.open_notes = {}
end

-- Helper: Wrap tick within buffer boundaries
-- Returns the wrapped tick position within buffer_start to buffer_start + buffer_length - 1
function Buffer:wrap_tick(tick)
	local relative_tick = tick - self.buffer_start
	local wrapped_relative = relative_tick % self.buffer_length
	return self.buffer_start + wrapped_relative
end

-- Record a MIDI event to the buffer at the current tick
-- Events wrap around within the buffer boundaries (buffer_start to buffer_start + buffer_length - 1)
-- Overwrite mode clearing is handled in transport_event when entering new steps
-- Always records to buffer
-- @param midi_event table The MIDI event to record
function Buffer:record_buffer(midi_event)
	-- Timing tracking (conditional on flag)
	local record_start = flags.buffer_timing_stats and util.time() or nil

	-- Determine the recording tick
	local recording_tick = self.tick

	-- Always preserve the raw, unquantized tick (read-only reference)
	midi_event.raw_tick = recording_tick

	-- Compute the storage tick. For note events:
	--  - Always track open notes so we can stamp vel_on on the closing note_off
	--    (used for synthetic note_on regeneration at loop boundaries).
	--  - When record-quantize is enabled, snap note_on to grid and preserve duration.
	local tick
	local grid = App.record_quantize_grid or 0
	local is_note = midi_event.type and (midi_event.type == 'note_on' or midi_event.type == 'note_off') and midi_event.note

	if is_note then
		local ch = midi_event.ch or 1
		local key = ch * 128 + midi_event.note -- numeric key, no per-event string alloc

		if midi_event.type == 'note_on' then
			local quantized_on = recording_tick
			if grid > 0 then
				quantized_on = math.floor((recording_tick + grid / 2) / grid) * grid
				if quantized_on < 1 then quantized_on = 1 end
			end

			self.open_notes[key] = {
				raw_on = recording_tick,
				quantized_on = quantized_on,
				vel_on = midi_event.vel or 100,
			}

			tick = self:wrap_tick(quantized_on)
		else
			local open = self.open_notes[key]

			-- Stamp the original attack velocity on the note_off so synthetic
			-- note_on regenerations at loop boundaries can re-trigger at the
			-- correct dynamic. Using vel_on (not vel) keeps note_off's own vel
			-- (release velocity) untouched on the wire.
			if open and open.vel_on then midi_event.vel_on = open.vel_on end

			if grid > 0 then
				if open and type(open.raw_on) == 'number' and type(open.quantized_on) == 'number' then
					-- Preserve played duration relative to quantized start
					local duration = recording_tick - open.raw_on
					if duration < 0 then duration = 0 end
					local off_tick = open.quantized_on + duration
					if off_tick < open.quantized_on then off_tick = open.quantized_on end
					tick = self:wrap_tick(off_tick)
				else
					-- No matching note_on: quantize note_off independently
					local quantized_off = math.floor((recording_tick + grid / 2) / grid) * grid
					if quantized_off < 1 then quantized_off = 1 end
					tick = self:wrap_tick(quantized_off)
				end
			else
				tick = self:wrap_tick(recording_tick)
			end

			self.open_notes[key] = nil
		end
	else
		tick = self:wrap_tick(recording_tick)
	end

	midi_event.buffer_sent = nil
	-- Store the (possibly quantized) tick on the event for editing
	midi_event.tick = tick
	midi_event.external_tick = App.external_tick

	-- Store the event using EventStore (maintains sorted tick index)
	self.store:insert(tick, midi_event)

	-- Record timing (conditional on flag)
	if flags.buffer_timing_stats and record_start then
		local record_elapsed = (util.time() - record_start) * 1000
		table.insert(self.timing_stats.record_times, record_elapsed)
		if #self.timing_stats.record_times > self.timing_stats.max_samples then table.remove(self.timing_stats.record_times, 1) end
	end
end

-- Clear buffer events for a single tick (used for overwrite mode)
function Buffer:clear_buffer_tick(tick) self.store:delete(tick) end

-- Clear buffer events for a tick range
-- Used for overwrite mode when entering a new step
function Buffer:clear_buffer_range(start_tick, end_tick)
	-- Wrap ticks to buffer boundaries
	start_tick = self:wrap_tick(start_tick)
	end_tick = self:wrap_tick(end_tick)

	-- Handle wrap-around case
	if start_tick <= end_tick then
		-- Normal range (no wrap) - delete_range_inclusive handles both inclusive ends
		self.store:delete_range_inclusive(start_tick, end_tick)
	else
		-- Wrap-around case (start > end)
		-- Clear from start to buffer_end
		local buffer_end = self.buffer_start + self.buffer_length - 1
		self.store:delete_range_inclusive(start_tick, buffer_end)
		-- Clear from buffer_start to end
		self.store:delete_range_inclusive(self.buffer_start, end_tick)
	end
end

-- Clear entire buffer
function Buffer:clear_buffer()
	self.store:clear()
	-- Update buffer reference to new events table
	self.buffer = self.store.events
	self:emit('clear_buffer')
end

-- Transport Event Handling
function Buffer:transport_event(data)
	-- Timing tracking (conditional on flag)
	local transport_start = flags.buffer_timing_stats and util.time() or nil

	if data.type == 'start' then
		self.playing = true -- Track transport state for recording timing
		-- Start recording at buffer start
		self.tick = 0
		-- Reset overwrite tracking for new recording loop
		self.overwrite_cleared_steps = {}
	elseif data.type == 'stop' then
		self.playing = false -- Track transport state for recording timing
		-- Don't reset tick - buffer is continuously running
		-- Clear any open notes used for record-time quantization
		self.open_notes = {}
	elseif data.type == 'clock' and self.playing then
		-- Ensure tick is within buffer bounds (safety check)
		-- This handles cases where buffer start changed during recording or tick got out of sync
		if not SequenceUtils.is_tick_in_loop(self.tick, self.buffer_start, self.buffer_length) then self.tick = SequenceUtils.wrap_tick_to_loop(self.tick, self.buffer_start, self.buffer_length) end

		-- Calculate the next tick
		local next_tick = self.tick + 1

		-- Update buffer.tick based on buffer boundaries
		-- Buffer always loops - wraps at buffer_start + buffer_length
		local buffer_end = self.buffer_start + self.buffer_length - 1
		if next_tick > buffer_end then
			-- Reset overwrite tracking for new loop iteration
			-- This allows overwrite mode to clear events again on the next loop
			self.overwrite_cleared_steps = {}

			-- Emit loop boundary event
			self:emit('loop_boundary')

			next_tick = self.buffer_start
			self.tick = self.buffer_start
		else
			self.tick = self.tick + 1
		end

		-- Always overwrite: when entering a new step, clear that step
		-- Overdub behavior is achieved through monitor settings (IN = input always flows, including clip playback)
		local step_size = TimingConstants.DEFAULT_STEP_SIZE
		local step_index = TimingConstants.tick_to_buffer_step(next_tick, self.buffer_start, step_size)

		-- Clear the step if we haven't cleared it in this loop iteration
		if not self.overwrite_cleared_steps[step_index] then
			local step_start, step_end = TimingConstants.buffer_step_to_tick_range(step_index, self.buffer_start, buffer_end, step_size)
			self:clear_buffer_range(step_start, step_end)
			self.overwrite_cleared_steps[step_index] = true
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

-- ============================================================================
-- EVENT STORE ACCESS METHODS
-- These methods expose the EventStore's efficient range query capabilities
-- ============================================================================

-- Get events in a tick range (shallow copy)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return table Sparse table of tick -> events
function Buffer:get_range(start_tick, end_tick) return self.store:get_range(start_tick, end_tick) end

-- Get events in a tick range as sorted array
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return table Array of {tick=number, events=table}
function Buffer:get_range_array(start_tick, end_tick) return self.store:get_range_array(start_tick, end_tick) end

-- Iterate over events in a range (memory efficient - no copy)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return function Iterator returning tick, events
function Buffer:iter_range(start_tick, end_tick) return self.store:iter_range(start_tick, end_tick) end

-- Get events at a specific tick
-- @param tick number The tick position
-- @return table|nil Array of events or nil
function Buffer:get_events(tick) return self.store:get(tick) end

-- Check if tick has events
-- @param tick number The tick position
-- @return boolean True if events exist
function Buffer:has_events(tick) return self.store:has(tick) end

-- Get count of ticks with events
-- @return number Count of ticks
function Buffer:tick_count() return self.store:count() end

-- Get total event count
-- @return number Total number of events
function Buffer:event_count() return self.store:event_count() end

-- Get first tick with events
-- @return number|nil First tick or nil
function Buffer:first_tick() return self.store:first_tick() end

-- Get last tick with events
-- @return number|nil Last tick or nil
function Buffer:last_tick() return self.store:last_tick() end

-- Copy events from a range (for clip saving, scrub buffer, etc.)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @param tick_offset number Optional offset to apply to ticks (default 0)
-- @return EventStore New EventStore with copied events
function Buffer:copy_range(start_tick, end_tick, tick_offset) return self.store:copy_range(start_tick, end_tick, tick_offset) end

-- ============================================================================
-- EDITING METHODS
-- For clip editing functionality (insert, delete, shift, quantize, etc.)
-- ============================================================================

-- Shift events by an offset (for moving/nudging events)
-- @param from_tick number Shift events at or after this tick
-- @param offset number Amount to shift (positive = forward, negative = backward)
-- @return number Count of events shifted
function Buffer:shift_events(from_tick, offset)
	local count = self.store:shift_events(from_tick, offset)
	self:emit('events_shifted', { from_tick = from_tick, offset = offset, count = count })
	return count
end

-- Insert empty time at a position (shift events forward)
-- @param insert_tick number Position to insert time
-- @param duration number Amount of time to insert (in ticks)
-- @return number Count of events shifted
function Buffer:insert_time(insert_tick, duration)
	local count = self.store:insert_time(insert_tick, duration)
	self:emit('time_inserted', { tick = insert_tick, duration = duration, count = count })
	return count
end

-- Delete time range and shift remaining events backward
-- @param start_tick number Start of range to delete (inclusive)
-- @param end_tick number End of range to delete (exclusive)
-- @return number Count of events deleted
function Buffer:delete_time(start_tick, end_tick)
	local count = self.store:delete_time(start_tick, end_tick)
	self:emit('time_deleted', { start_tick = start_tick, end_tick = end_tick, count = count })
	return count
end

-- Quantize events to a grid
-- @param grid_size number Grid size in ticks
-- @param start_tick number Optional start of range
-- @param end_tick number Optional end of range
-- @return number Count of events moved
function Buffer:quantize(grid_size, start_tick, end_tick)
	local count = self.store:quantize(grid_size, start_tick, end_tick)
	self:emit('events_quantized', { grid_size = grid_size, count = count })
	return count
end

-- Transpose MIDI note events
-- @param semitones number Number of semitones to transpose
-- @param start_tick number Optional start of range
-- @param end_tick number Optional end of range
-- @return number Count of events transposed
function Buffer:transpose(semitones, start_tick, end_tick)
	local count = self.store:transpose(semitones, start_tick, end_tick)
	self:emit('events_transposed', { semitones = semitones, count = count })
	return count
end

-- Scale event velocities
-- @param factor number Velocity multiplier
-- @param start_tick number Optional start of range
-- @param end_tick number Optional end of range
-- @return number Count of events scaled
function Buffer:scale_velocity(factor, start_tick, end_tick)
	local count = self.store:scale_velocity(factor, start_tick, end_tick)
	self:emit('velocity_scaled', { factor = factor, count = count })
	return count
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
			'Buffer Timing Stats:\n' .. '  Transport: avg=%.3fms max=%.3fms (samples=%d)\n' .. '  Record: avg=%.3fms max=%.3fms (samples=%d)',
			avg(self.timing_stats.transport_times),
			max(self.timing_stats.transport_times),
			#self.timing_stats.transport_times,
			avg(self.timing_stats.record_times),
			max(self.timing_stats.record_times),
			#self.timing_stats.record_times
		)
	)
end

return Buffer
