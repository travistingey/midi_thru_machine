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
	self.seq_start = o.seq_start or 0
	self.seq_length = App.ppqn * 16
	self.tick = o.tick or 0 -- Current playback position in ticks (renamed from 'step')
	self.playing = false
	self.enabled = true

	self.active_cc = nil -- Holds active CC automation data

	self.track.current_preset = 1

	-- Buffer for live MIDI recording
	-- Note: buffer_length is kept for backwards compatibility but buffer now follows seq_length
	self.buffer_length = App.BUFFER_LENGTH or (App.ppqn * 16)

	-- Buffer step length (in ticks) - defines duration of one "step"
	-- Defaults to track's step_length converted to ticks, or 24 ticks (1 beat at 24ppqn)
	self.buffer_step_length = o.buffer_step_length or (self.track and self.track.step_length and (self.track.step_length * App.ppqn / 4) or 24)

	-- Buffer playback settings (defaults - will be overridden by params)
	self.buffer_playback = o.buffer_playback or false -- Default off for silent recording
	self.mute_input_on_playback = o.mute_input_on_playback ~= nil and o.mute_input_on_playback or true -- Default enabled

	-- Overwrite mode tracking: tracks which steps have been cleared in current loop iteration
	-- Key: step_index (step number within loop), Value: true
	self.overwrite_cleared_steps = {}

	self:on('record_event', function(data)
		local tick = self.tick
		if data.quantize then tick = math.floor(tick / data.quantize) * data.quantize end
		self:set_action(self.tick, data.type, data.value)
	end)
end

-- Helper: Get current step index (0-based) from current tick
function Auto:get_current_step_index()
	return math.floor(self.tick / self.buffer_step_length)
end

-- Helper: Convert tick to step index (0-based)
function Auto:tick_to_step_index(tick)
	return math.floor(tick / self.buffer_step_length)
end

-- Helper: Convert step index to tick range (returns start_tick, end_tick inclusive)
function Auto:step_index_to_tick_range(step_index)
	local start_tick = step_index * self.buffer_step_length
	local end_tick = start_tick + self.buffer_step_length - 1
	return start_tick, end_tick
end

-- Helper: Convert step index to start tick
function Auto:step_index_to_start_tick(step_index)
	return step_index * self.buffer_step_length
end

-- Record a MIDI event to the buffer lane at the current tick
-- Events wrap around within the auto loop boundaries (seq_start to seq_start + seq_length)
-- Overwrite mode clearing is handled in transport_event when entering new steps
function Auto:record_buffer(midi_event)
	-- Wrap tick within the auto loop boundaries
	local relative_tick = self.tick - self.seq_start
	local tick = self.seq_start + (relative_tick % self.seq_length)

	if not self.seq[tick] then self.seq[tick] = {} end
	if not self.seq[tick].buffer then self.seq[tick].buffer = {} end

	-- Store the event (multiple events can exist at same tick)
	table.insert(self.seq[tick].buffer, {
		type = midi_event.type,
		note = midi_event.note,
		vel = midi_event.vel,
		ch = midi_event.ch,
	})
end

-- Clear buffer events for a single tick (used for overwrite mode)
function Auto:clear_buffer_tick(tick)
	if self.seq[tick] and self.seq[tick].buffer then self.seq[tick].buffer = {} end
end

-- Clear buffer events for an entire step range (all ticks in a step)
-- Used for overwrite mode when entering a new step
function Auto:clear_buffer_step(step_index)
	-- Calculate the step boundaries within the loop
	local step_start = self.seq_start + (step_index * self.buffer_step_length)
	local step_end = math.min(step_start + self.buffer_step_length - 1, self.seq_start + self.seq_length - 1)

	-- Clear all ticks in this step range
	for tick = step_start, step_end do
		if self.seq[tick] and self.seq[tick].buffer then self.seq[tick].buffer = {} end
	end
end

-- Clear the buffer lane
function Auto:clear_buffer()
	for tick, lanes in pairs(self.seq) do
		if lanes.buffer then lanes.buffer = nil end
		-- Clean up empty tick entries
		if next(lanes) == nil then self.seq[tick] = nil end
	end
	print('Buffer cleared for track ' .. self.track.id)
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
		-- Offset run ticks ahead of current tick
		local run_offset = 2

		if self.tick < run_offset then
			if self.seq[self.tick] then self:run_events(self.seq[self.tick]) end
		end

		-- Calculate the next tick
		local next_tick = self.tick + run_offset

		-- Handle scrub mode separately
		if self.scrub_mode then
			if next_tick > self.scrub_end then
				if self.scrub_loop then
					-- Loop back to scrub start
					self:kill_notes()
					next_tick = self.scrub_start
					self.tick = self.scrub_start
				else
					-- Play-through mode: stay at end (will be restored when scrub stops)
					next_tick = self.scrub_end
					self.tick = self.scrub_end
				end
			else
				self.tick = self.tick + 1
			end

			-- Only run buffer events during scrub
			local actions = self.seq[next_tick]
			if actions and actions.buffer then self:run_buffer(actions.buffer) end
		else
			-- Normal playback mode
			if next_tick >= self.seq_start + self.seq_length then
				-- Handle buffer recording modes at loop boundary
				if self.track.armed then
					-- One-shot mode: disarm track after completing loop
					if not App.buffer_loop then
						self.track.armed = false
						Registry.set('track_' .. self.track.id .. '_armed', 0, 'buffer_oneshot')
						print('Track ' .. self.track.id .. ' disarmed (one-shot complete)')
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
			if not App.buffer_overdub and self.track.armed then
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

			local actions = self.seq[next_tick]

			if actions then self:run_events(actions) end
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
		elseif action_type == 'buffer' and action_data then
			self:run_buffer(action_data)
		end
	end
end

-- Playback buffer events directly to output (bypasses processing chain)
-- Respects per-track buffer_playback param, scrub mode, and App.buffer_mute_on_arm settings
function Auto:run_buffer(events)
	if not self.track.output_device then return end

	-- Check if buffer playback is enabled for this track (via param)
	-- OR if scrub mode is active (grid-triggered playback)
	local playback_enabled = false
	if self.scrub_mode then
		-- Scrub mode always allows playback (grid-triggered)
		playback_enabled = true
	elseif self.buffer_playback then
		-- Param-based automatic playback
		playback_enabled = true
	end

	if not playback_enabled then return end

	-- Check if buffer should be muted because track is armed
	if App.buffer_mute_on_arm and self.track.armed then return end

	for _, event in ipairs(events) do
		local ch = event.ch or self.track.midi_out
		local midi_msg = {
			type = event.type,
			note = event.note,
			vel = event.vel,
			ch = ch,
		}

		self.track.output_device:send(midi_msg)
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
	self.tick = start_tick
end

-- Update scrub range (for multi-pad selection)
function Auto:update_scrub(start_tick, end_tick)
	if not self.scrub_mode then return end

	-- Kill notes to prevent stuck notes when range changes
	self:kill_notes()

	self.scrub_start = start_tick
	self.scrub_end = end_tick
	self.scrub_length = end_tick - start_tick + 1
end

-- Stop scrub and restore normal playback
function Auto:stop_scrub(saved_tick, saved_seq_start, saved_seq_length)
	if not self.scrub_mode then return end

	-- Kill any scrub notes
	self:kill_notes()

	-- Restore previous state
	self.scrub_mode = false
	self.scrub_loop = false
	self.scrub_start = nil
	self.scrub_end = nil
	self.scrub_length = nil

	-- Restore playback position and loop points
	if saved_tick then self.tick = saved_tick end
	if saved_seq_start then self.seq_start = saved_seq_start end
	if saved_seq_length then self.seq_length = saved_seq_length end
end

return Auto
