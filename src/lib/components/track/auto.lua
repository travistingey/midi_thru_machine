local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')

-- Auto is short for automation!

local Auto = {}
Auto.name = 'auto'
Auto.__index = Auto
setmetatable(Auto, { __index = TrackComponent })

function Auto:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
	o:set(o)
	return o
end

function Auto:set(o)
	self.id = o.id or 1
	self.seq = o.seq or {}
	self.seq_start = o.seq_start or 1
	self.seq_length = App.ppqn * 16
	self.tick = o.tick or 0 -- Current playback position in ticks (renamed from 'step')
	self.playing = false
	self.enabled = true

	self.active_cc = nil -- Holds active CC automation data

	self.track.current_preset = 1

	-- Buffer for live MIDI recording
	-- Note: buffer_length is kept for backwards compatibility but buffer now follows seq_length
	self.buffer_length = o.buffer_length or (App.ppqn * 16)

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
	if o.seq then
		for tick, lanes in pairs(o.seq) do
			if lanes.buffer then
				-- Migrate to both read and write buffers
				self.buffer_write[tick] = lanes.buffer
				self.buffer_read[tick] = lanes.buffer
			end
		end
	end

	-- Overwrite mode tracking: tracks which steps have been cleared in current loop iteration
	-- Key: step_index (step number within loop), Value: true
	self.overwrite_cleared_steps = {}

	-- Scrub tick: separate tick counter for scrub mode playback
	-- auto.tick continues updating normally even during scrub mode
	self.scrub_tick = nil

	self:on('record_event', function(data)
		local tick = self.tick
		if data.quantize then tick = math.floor(tick / data.quantize) * data.quantize end
		self:set_action(self.tick, data.type, data.value)
	end)
end

-- Helper: Get current step index (0-based) from current tick
function Auto:get_current_step_index() return math.floor(self.tick / self.buffer_step_length) end

-- Helper: Convert tick to step index (0-based)
function Auto:tick_to_step_index(tick) return math.floor(tick / self.buffer_step_length) end

-- Helper: Convert step index to tick range (returns start_tick, end_tick inclusive)
function Auto:step_index_to_tick_range(step_index)
	local start_tick = step_index * self.buffer_step_length
	local end_tick = start_tick + self.buffer_step_length - 1
	return start_tick, end_tick
end

-- Helper: Convert step index to start tick
function Auto:step_index_to_start_tick(step_index) return step_index * self.buffer_step_length end

-- Swap buffer step: Copy buffer_write to buffer_read for a single step
-- Called on step transitions to provide immediate feedback (within one step)
-- Only swaps ticks within both step boundaries and loop boundaries
function Auto:swap_buffer_step(step_index)
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
		if self.buffer_write[tick] then self.buffer_read[tick] = self.buffer_write[tick] end
	end
end

-- -- Set buffer step length and invalidate/re-swap if changed
-- -- Called when user changes step length in bufferseq
-- function Auto:set_buffer_step_length(new_length)
-- 	local old_length = self.buffer_step_length
-- 	self.buffer_step_length = new_length

-- 	if old_length ~= new_length then
-- 		-- Invalidate and re-swap with new step boundaries
-- 		self:invalidate_and_reswap()
-- 	end
-- end

-- -- Invalidate buffer_read and re-swap all steps with current step length
-- -- Called when buffer_step_length changes
-- function Auto:invalidate_and_reswap()
-- 	-- Clear read buffer
-- 	self.buffer_read = {}

-- 	-- Re-swap all steps within current loop
-- 	local loop_start = self.seq_start
-- 	local loop_end = self.seq_start + self.seq_length - 1
-- 	local first_step = self:tick_to_step_index(loop_start)
-- 	local last_step = self:tick_to_step_index(loop_end)

-- 	for step_idx = first_step, last_step do
-- 		self:swap_buffer_step(step_idx)
-- 	end

-- 	-- Reset step tracking
-- 	self.last_step_index = nil

-- 	print('Buffer re-swapped with new step length: ' .. self.buffer_step_length .. ' ticks')
-- end

-- Record a MIDI event to the buffer write lane at the current tick
-- Events wrap around within the auto loop boundaries (seq_start to seq_start + seq_length)
-- Overwrite mode clearing is handled in transport_event when entering new steps
-- Records to buffer_write only - buffer_read is updated via step-based swapping
function Auto:record_buffer(midi_event)
	if not self.track.armed then return end

	if midi_event.tick == self.tick then return end

	-- Wrap tick within the auto loop boundaries
	local relative_tick = self.tick - self.seq_start
	local tick = self.seq_start + (relative_tick % self.seq_length)

	-- Initialize buffer_write table for this tick if needed
	if not self.buffer_write[tick] then self.buffer_write[tick] = {} end

	midi_event.buffer_sent = nil
	midi_event.tick = self.tick

	-- Store the event (multiple events can exist at same tick)
	table.insert(self.buffer_write[tick], midi_event)
end

-- Clear buffer events for a single tick (used for overwrite mode)
-- Only clears buffer_write (not buffer_read, which continues playing)
function Auto:clear_buffer_tick(tick)
	if self.buffer_write[tick] then self.buffer_write[tick] = nil end
end

-- Clear buffer events for an entire step range (all ticks in a step)
-- Used for overwrite mode when entering a new step
-- Only clears buffer_write (not buffer_read, which continues playing)
function Auto:clear_buffer_step(step_index)
	-- Calculate the step boundaries within the loop
	local step_start = self.seq_start + (step_index * self.buffer_step_length)
	local step_end = math.min(step_start + self.buffer_step_length - 1, self.seq_start + self.seq_length - 1)

	-- Clear all ticks in this step range from write buffer
	for tick = step_start, step_end do
		if self.buffer_write[tick] then self.buffer_write[tick] = nil end
	end
end

-- Clear both buffer_write and buffer_read
function Auto:clear_buffer()
	self.buffer_write = {}
	self.buffer_read = {}
end

function Auto:get_action(step, lane)
	if self.seq[step] then return self.seq[step][lane] end
end

function Auto:set_action(step, lane, value)
	local action = {}

	-- Initialize step
	if not self.seq[step] then self.seq[step] = {} end

	if type(lane) == 'table' then
		local action = lane

		-- Manage nested table of CC
		if action.type == 'cc' then
			if not self.seq[step]['cc'] then self.seq[step]['cc'] = {} end

			local entry = self.seq[step]['cc']

			if action.value == nil then
				entry[action.cc] = nil
			else
				entry[action.cc] = action
			end
		else
			-- Standard action
			self.seq[step][action.type] = lane
		end
	elseif type(lane) == 'string' then
		action.type = lane
		action.value = value

		-- Remove nil value entries
		if action.value == nil then
			self.seq[step][action.type] = nil
		else
			self.seq[step][action.type] = { type = action.type, value = value }
		end
	end
end

-- Set value if none exists. If value exists, set to nil
-- This only works for single action types
function Auto:toggle_action(step, action)
	local action_type = action.type
	local last_selection

	if self.seq[step] and self.seq[step][action_type] then
		last_selection = self.seq[step][action_type]
		self:set_action(step, action_type, nil)
	else
		last_selection = nil
		self:set_action(step, action_type, action.value)
	end

	return last_selection
end

function Auto:set_loop(loop_start, loop_end)
	self.seq_start = loop_start
	self.seq_length = loop_end - loop_start + 1
	-- Reset overwrite tracking when loop boundaries change
	self.overwrite_cleared_steps = {}
end

-- Transport Event Handling
function Auto:transport_event(data)
	if data.type == 'start' then
		self.playing = true
		self.tick = 0
		self.active_cc = nil
		-- Clear any lingering buffer notes from previous playback
		self:kill_notes()
		-- Reset overwrite tracking for new playback
		self.overwrite_cleared_steps = {}

		if self.seq[self.tick] then self:run_events(self.seq[self.tick]) end
	elseif data.type == 'stop' then
		self.playing = false
		self.tick = 0
		-- Kill all active buffer notes to prevent stuck notes
		self:kill_notes()
		if self.seq[self.tick] then self:run_events(self.seq[self.tick]) end
	elseif data.type == 'clock' and self.playing then
		self:update_cc()

		-- Detect step transitions for buffer swapping
		local current_step_index = self:tick_to_step_index(self.tick)

		-- Swap on step exit (when entering new step, swap the completed step)
		if self.last_step_index and current_step_index ~= self.last_step_index then
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

		if self.tick < run_offset then
			if self.seq[self.tick] then self:run_events(self.seq[self.tick]) end
		end

		-- Calculate the next tick for normal playback
		local next_tick = self.tick + run_offset

		-- Always update auto.tick based on normal playback rules (even during scrub mode)
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

			-- Run automation events (presets, scales, cc)
			local actions = self.seq[next_tick]
			if actions then self:run_events(actions) end

			if self.buffer_read[next_tick] then self:run_buffer(self.buffer_read[next_tick]) end
		end
	end

	return data
end

function Auto:run_events(actions)
	for action_type, action_data in pairs(actions) do
		if action_type == 'track' and action_data then
			self:run_preset(action_data)
			self:emit('preset_change', action_data)
		elseif action_type == 'scale' and action_data then
			self:run_scale(action_data)
			self:emit('scale_change', action_data)
		elseif action_type == 'cc' and action_data then
			self:run_cc(action_data)
			self:emit('cc_change', action_data)
		end
		-- Note: 'buffer' is no longer in seq[tick] - it's now in buffer_read/buffer_write
	end
end

-- Playback buffer events directly to output (bypasses processing chain)
-- Respects per-track buffer_playback param, scrub mode settings
function Auto:run_buffer(events)
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
function Auto:kill_notes()
	if not self.track.output_device then return end
	self.track.output_device:kill()
end

function Auto:run_preset(action)
	local component_props = App.preset_props.track
	local id = self.track.id

	self.track.current_preset = action.value

	if component_props then
		local props = {}
		for i, v in ipairs(component_props) do
			props[i] = 'track_' .. id .. '_' .. v
		end

		App:load_preset(action.value, props)
	end
end

function Auto:run_scale(action)
	local component_props = App.preset_props.scale
	local props = {}

	self.track.current_scale = action.value

	for id = 1, 3 do
		if component_props then
			for i, v in ipairs(component_props) do
				props[i] = 'scale_' .. id .. '_' .. v
			end
			App:load_preset(action.value, props)
		end
	end
end

function Auto:run_cc(cc_actions)
	for cc_number, action in pairs(cc_actions) do
		if action then
			-- Initialize CC automation parameters for each CC
			self.active_ccs = self.active_ccs or {}
			self.active_ccs[cc_number] = {
				curve = action.curve, -- {P0, P1, P2, P3}
				duration = action.duration,
				start_tick = self.tick,
				end_tick = self.tick + action.duration,
				midi_channel = action.midi_channel or 1,
			}
		end
	end
end

function Auto:update_cc()
	if not self.active_ccs then return end

	for cc_number, automation in pairs(self.active_ccs) do
		local current_tick = self.tick
		if current_tick <= automation.end_tick then
			local t = (current_tick - automation.start_tick) / automation.duration
			t = math.min(math.max(t, 0), 1) -- Clamp t between 0 and 1
			local value = self:bezier_transform(t, automation.curve)
			local cc_message = {
				type = 'cc',
				cc = cc_number,
				val = math.floor(value * 127),
				ch = automation.midi_channel,
			}
			-- Send the CC message
			self.track.midi_out:send(cc_message)
		else
			-- Automation completed
			self.active_ccs[cc_number] = nil
		end
	end

	-- Clean up if all automations are done
	if next(self.active_ccs) == nil then self.active_ccs = nil end
end

function Auto:bezier_transform(t, curve)
	local P0, P1, P2, P3 = curve[1], curve[2], curve[3], curve[4]
	local u = 1 - t
	local tt = t * t
	local uu = u * u
	local uuu = uu * u
	local ttt = tt * t
	local y = uuu * P0.y + 3 * uu * t * P1.y + 3 * u * tt * P2.y + ttt * P3.y
	return y -- Normalized between 0 and 1
end

-- Scrub playback: temporarily play a range of the buffer
-- loop_mode: true = loop the range, false = play through once then stop
function Auto:start_scrub(start_tick, end_tick, loop_mode)
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
function Auto:update_scrub(start_tick, end_tick)
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
function Auto:stop_scrub(saved_tick, saved_seq_start, saved_seq_length)
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
	-- Note: auto.tick is already at the correct position (it's been updating in the background)
	if saved_seq_start then self.seq_start = saved_seq_start end
	if saved_seq_length then self.seq_length = saved_seq_length end
end

return Auto
