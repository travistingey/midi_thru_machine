local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')
local SequenceUtils = require(path_name .. 'utilities/sequence_utils')

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
	self.buffer_length = o.buffer_length or (App.ppqn * 4 * 256) -- Static buffer length (64 bars default)
	self.playing = false
	self.enabled = true

	-- Buffer only records - Clip component handles all playback

	-- Single buffer architecture: Buffer continuously records, Clip handles playback via frozen_buffer
	-- Buffer loops back over itself at buffer_start + buffer_length
	self.buffer = {} -- Single buffer for recording

	-- Migrate existing buffer data if present (backward compatibility)
	-- This handles migration from old double-buffer structure
	if o.buffer then
		self.buffer = o.buffer
	elseif o.buffer_write then
		-- Migrate from old buffer_write
		self.buffer = o.buffer_write
	end

	-- Overwrite mode tracking: tracks which steps have been cleared in current loop iteration
	-- Key: step_index (step number within loop), Value: true
	self.overwrite_cleared_steps = {}
end

-- Helper: Wrap tick within buffer boundaries
-- Returns the wrapped tick position within buffer_start to buffer_start + buffer_length - 1
function Buffer:wrap_tick(tick)
	local relative_tick = tick - self.buffer_start
	local wrapped_relative = relative_tick % self.buffer_length
	return self.buffer_start + wrapped_relative
end

-- Swap buffer step: Copy buffer_write to buffer_read for a single step
-- Called on step transitions during recording to provide immediate feedback (within one step)
-- Clip component reads from buffer_read for playback
-- Only swaps ticks within both step boundaries and loop boundaries
-- Optimized to only iterate over ticks that contain data (sparse table optimization)

-- Record a MIDI event to the buffer at the current tick
-- Events wrap around within the buffer boundaries (buffer_start to buffer_start + buffer_length - 1)
-- Overwrite mode clearing is handled in transport_event when entering new steps
-- Always records to buffer
-- @param midi_event table The MIDI event to record
-- @param event_tick number Optional: The tick when the event occurred (App.tick). If not provided, uses self.tick
function Buffer:record_buffer(midi_event, event_tick)
	-- Timing tracking (conditional on flag)
	local record_start = flags.buffer_timing_stats and util.time() or nil

	-- Determine the recording tick

	local recording_tick = self.tick

	-- Wrap tick within the buffer boundaries
	local tick = self:wrap_tick(recording_tick)
	-- Initialize buffer table for this tick if needed
	if not self.buffer[tick] then self.buffer[tick] = {} end

	midi_event.buffer_sent = nil
	midi_event.tick = recording_tick
	midi_event.external_tick = App.external_tick
	-- Store the event (multiple events can exist at same tick)
	table.insert(self.buffer[tick], midi_event)

	-- Record timing (conditional on flag)
	if flags.buffer_timing_stats and record_start then
		local record_elapsed = (util.time() - record_start) * 1000
		table.insert(self.timing_stats.record_times, record_elapsed)
		if #self.timing_stats.record_times > self.timing_stats.max_samples then table.remove(self.timing_stats.record_times, 1) end
	end
end

-- Clear buffer events for a single tick (used for overwrite mode)
function Buffer:clear_buffer_tick(tick)
	if self.buffer[tick] then self.buffer[tick] = nil end
end

-- Clear buffer events for a tick range
-- Used for overwrite mode when entering a new step
function Buffer:clear_buffer_range(start_tick, end_tick)
	-- Wrap ticks to buffer boundaries
	start_tick = self:wrap_tick(start_tick)
	end_tick = self:wrap_tick(end_tick)

	-- Handle wrap-around case
	if start_tick <= end_tick then
		-- Normal range (no wrap)
		for tick = start_tick, end_tick do
			if self.buffer[tick] then self.buffer[tick] = nil end
		end
	else
		-- Wrap-around case (start > end)
		-- Clear from start to buffer_end
		local buffer_end = self.buffer_start + self.buffer_length - 1
		for tick = start_tick, buffer_end do
			if self.buffer[tick] then self.buffer[tick] = nil end
		end
		-- Clear from buffer_start to end
		for tick = self.buffer_start, end_tick do
			if self.buffer[tick] then self.buffer[tick] = nil end
		end
	end
end

-- Clear entire buffer
function Buffer:clear_buffer()
	self.buffer = {}
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
		-- Use a simple step size (8 ticks) for overwrite clearing
		local step_size = 8 -- Hardcoded step size for overwrite clearing
		local step_index = math.floor((next_tick - self.buffer_start) / step_size) + 1

		-- Clear the step if we haven't cleared it in this loop iteration
		if not self.overwrite_cleared_steps[step_index] then
			local step_start = self.buffer_start + (step_index - 1) * step_size
			local step_end = math.min(step_start + step_size - 1, buffer_end)
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
