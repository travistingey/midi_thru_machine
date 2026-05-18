local Tracer = require('Foobar/lib/utilities/tracer')
local utilities = require('Foobar/lib/utilities')

local Registry = require('Foobar/lib/utilities/registry')
local path_name = 'Foobar/lib/components/track/'

local Auto = require(path_name .. 'auto')
local Buffer = require(path_name .. 'buffer')
local Clip = require(path_name .. 'clip')
local Input = require(path_name .. 'input')
local Scale = require(path_name .. 'scale')
local Mute = require(path_name .. 'mute')
local Output = require(path_name .. 'output')

-- Define a new class for Track
local Track = {}

-- Constructor
function Track:new(o)
	o = o or {}

	if o.id == nil then error('Track:new() missing required \'id\' parameter.') end

	setmetatable(o, self)
	self.__index = self

	o.id = o.id
	o:set(o)

	self.load_component(o, Auto)
	self.load_component(o, Input)
	self.load_component(o, Buffer)
	self.load_component(o, Clip)
	self.load_component(o, Mute)
	self.load_component(o, Output)

	-- Set buffer reference in clip after buffer is loaded
	-- Uses set_buffer() to also initialize PlaybackSource
	if o.clip and o.buffer then
		o.clip:set_buffer(o.buffer)
		-- Load clip bank metadata on track initialization
		o.clip:load_bank_metadata()
	end

	self.build_chain(o)

	return o
end

--[[ 
	Set is called initially and keeps a clean list of parameters that are instantiated.
	Track properties must match parameter values 1 to 1 in order for update to manage values.
]]
function Track:set(o)
	self.name = 'Track ' .. o.id
	self.input_device = o.input_device or App.device_manager:get(1)
	self.input_type = o.input_type or Input.options[1]
	self.mute_input = false
	self.monitor = o.monitor or 2 -- 1 = IN, 2 = AUTO, 3 = OFF

	self.output_device = o.output_device or App.device_manager:get(2)
	self.output_type = o.output_type or Output.options[1]

	self.note_on = {}

	self.enabled = false
	self.mono = o.mono or false
	self.voice = o.voice or 0
	self.chord_type = o.chord_type or 1
	self.current_preset = 1
	self.current_scale = 1
	self.event_listeners = {}
	self.triggered = o.triggered or false

	self.scale = App.scale[o.scale_select]

	local track = 'track_' .. self.id .. '_'

	Registry.add('add_group', 'Track ' .. self.id, 29)

	Registry.add('add_text', track .. 'name', 'Name', self.name)
	Registry.set_action(track .. 'name', function(d) self.name = d end)

	-- Input Devive Listeners
	local function input_event(data)
		-- Midi Events are bound by the track's Input component
		if data.type == 'note_on' then
			self.note_on[data.note] = data
		elseif data.type == 'note_off' then
			self.note_on[data.note] = nil
		elseif data.type == 'cc' then
			-- if self.midi_in > 0 and data.ch == self.midi_in then
			-- 	self:emit('cc_event', data)
			-- end
		end
	end

	self:on('mixer_event', function(data)
		if self.output_device then self.output_device:send(data) end
	end)

	App:on('transport_event', function(data)
		if self.process_transport and self.enabled then self:process_transport(data) end
	end)

	self:on('cc_event', function(data)
		if self.output_device then self.output_device:send(data) end
	end)

	self:on('midi_event', input_event)
	self:on('midi_trigger', input_event)
	self:on('mute_input', function(state) self.mute_input = state end)
	self:on('record_buffer', function(data)
		-- Buffer always records output, including output from scrubbing, clips, and frozen buffer
		-- Recording happens at buffer.tick (continuously advancing), while playback uses different
		-- tick positions (scrub tick, clip tick, etc.), so recording at buffer.tick won't cause feedback
		-- Always record to buffer when transport is playing
		if App.playing and self.buffer then self.buffer:record_buffer(data) end
	end)

	-- Device In/Out
	local midi_devices = {}
	local midi_abbrs = {}
	local port_count = math.max(App.device_manager.midi_port_count or 0, #App.device_manager.midi_device_names)
	for i = 1, port_count do
		midi_devices[i] = App.device_manager.midi_device_names[i] or 'None'
		midi_abbrs[i] = App.device_manager.midi_device_abbrs[i] or midi_devices[i]
	end
	-- Extend device_out options to include Crow as a selectable output device
	local output_devices = {}
	for i, name in ipairs(midi_devices) do
		output_devices[#output_devices + 1] = name
	end
	output_devices[#output_devices + 1] = 'Crow'

	self.device_in = 1
	-- Use abbreviations for display strings so params:string() shows short names
	Registry.add('add_option', track .. 'device_in', 'Device In', midi_abbrs)

	Registry.set_action(track .. 'device_in', function(d)
		local new_device = App.device_manager:get(d)
		if not new_device or not new_device.add_trigger then
			print('Device In set to empty slot ' .. d .. '; ignoring')
			return
		end

		self.device_in = d

		-- Remove old input device listeners
		if self.input_device then self:remove_trigger() end

		self.input_device = new_device
		self:add_trigger()
		self:load_component(Input)
		self:enable()
	end)

	self.device_out = self.device_out or 1
	-- Mirror abbreviations for output devices and append Crow
	local output_devices_abbr = {}
	for i, abbr in ipairs(midi_abbrs) do
		output_devices_abbr[#output_devices_abbr + 1] = abbr
	end
	output_devices_abbr[#output_devices_abbr + 1] = 'Crow'
	Registry.add('add_option', track .. 'device_out', 'Device Out', output_devices_abbr, 2)
	Registry.set_action(track .. 'device_out', function(d)
		local new_device = App.device_manager:get(d)
		if output_devices[d] ~= 'Crow' and (not new_device or not new_device.send) then
			print('Device Out set to empty slot ' .. d .. '; ignoring')
			return
		end

		self.device_out = d
		if output_devices[d] == 'Crow' then
			-- Switch to Crow output type
			Registry.set(track .. 'output_type', 2, 'device_out_select') -- 2 = crow
			self.output_type = 'crow'
			-- keep output_device as-is for crow; Output component uses App.crow
		else
			-- Ensure MIDI output type and set selected MIDI device
			Registry.set(track .. 'output_type', 1, 'device_out_select') -- 1 = midi
			self.output_type = 'midi'
			self.output_device = App.device_manager:get(d)
		end
		self:load_component(Output)
		self:enable()
	end)

	-- Input Type
	Registry.add('add_option', track .. 'input_type', 'Input Type', Input.options, 1)
	Registry.set_action(track .. 'input_type', function(d)
		self:kill()
		self.input_type = Input.options[d]

		if self.input_type ~= 'midi' then
			self.triggered = true
		else
			self.triggered = false
		end

		self:load_component(Input)
		self:enable()
	end)

	-- Output Type
	self.output_type = o.output_type or Output.options[1]
	Registry.add('add_option', track .. 'output_type', 'Output Type', Output.options, 1)
	Registry.set_action(track .. 'output_type', function(d)
		self:kill()
		self.output_type = Output.options[d]
		self:load_component(Output)
		self:enable()
	end)

	-- MIDI In
	self.midi_in = o.midi_in or 0
	Registry.add('add_number', track .. 'midi_in', 'MIDI In', 0, 17, 0, function(param)
		local ch = param:get()
		if ch == 0 then
			return 'off'
		elseif ch == 17 then
			return 'all'
		else
			return ch
		end
	end)

	Registry.set_action(track .. 'midi_in', function(d)
		self:kill()

		self.midi_in = d
		self:load_component(Input)
		self:enable()
	end)

	-- MIDI Out
	self.midi_out = o.midi_out or 0
	Registry.add('add_number', track .. 'midi_out', 'MIDI Out', 0, 17, 0, function(param)
		local ch = param:get()
		if ch == 0 then
			return 'off'
		elseif ch == 17 then
			return 'all'
		else
			return ch
		end
	end)

	Registry.set_action(track .. 'midi_out', function(d)
		self:kill()
		self.midi_out = d
		self:load_component(Output)

		self:enable()
	end)

	Registry.add('add_trigger', track .. 'device_swap_trigger', 'Swap Devices')
	Registry.set_action(track .. 'device_swap_trigger', function()
		local in_device = self.input_device.id
		local in_channel = self.midi_in
		local out_device = self.output_device.id
		local out_channel = self.midi_out

		Registry.set(track .. 'device_in', out_device, 'device_in_select')
		Registry.set(track .. 'midi_in', out_channel, 'midi_in_select')
		Registry.set(track .. 'device_out', in_device, 'device_out_select')
		Registry.set(track .. 'midi_out', in_channel, 'midi_out_select')
	end)

	-- -- MIDI Thru
	-- self.midi_thru = o.midi_thru or false
	-- Registry.add('add_binary', track .. 'midi_thru','MIDI Thru','toggle', 0)
	-- Registry.set_action(track .. 'midi_thru',function(d)
	-- 	self.midi_thru = (d>0)
	-- end)

	Registry.add('add_binary', track .. 'mixer', 'Mixer', 'toggle', 0)
	Registry.set_action(track .. 'mixer', function(d)
		if App.flags.state.initializing then return end

		local mixer = App.device_manager and App.device_manager.mixer
		if not mixer then
			-- Mixer device not available (e.g. device list changed or no LCXL selected)
			if d > 0 then print('No mixer device available; ignoring mixer toggle for track ' .. self.id) end
			return
		end

		if d == 0 then
			mixer:remove_track(self)
		else
			mixer:add_track(self)
		end
	end)

	-- Arpeggio
	local arp_options = { 'up', 'down', 'up down', 'down up', 'converge', 'diverge' }
	self.arp = o.arp or arp_options[1]
	Registry.add('add_option', track .. 'arp', 'Arpeggio', arp_options, 1)
	Registry.set_action(track .. 'arp', function(d)
		App.settings[track .. 'arp'] = d
		self.arp = arp_options[d]
	end)

	local function calculate_step_values(include_trig)
		local ppqn = App.ppqn
		local step_values = {
			math.floor(ppqn / 12), -- 1/48
			math.floor(ppqn / 8), -- 1/32
			math.floor(ppqn * 2 / 24), -- 1/32t (triplet)
			math.floor(ppqn / 4), -- 1/16
			math.floor(ppqn * 2 / 12), -- 1/16t (triplet)
			math.floor(ppqn * 3 / 8), -- 1/16d (dotted)
			math.floor(ppqn / 2), -- 1/8
			math.floor(ppqn * 2 / 6), -- 1/8t (triplet)
			math.floor(ppqn * 3 / 4), -- 1/8d (dotted)
			ppqn, -- 1/4
			math.floor(ppqn * 2 / 3), -- 1/4t (triplet)
			math.floor(ppqn * 3 / 2), -- 1/4d (dotted)
			ppqn * 2, -- 1/2
			ppqn * 4, -- 1 (whole note)
			ppqn * 8, -- 2
			ppqn * 16, -- 4
			ppqn * 32, -- 8
			ppqn * 64, -- 16
		}

		if include_trig then
			local options = { 0 }
			for i = 1, #step_values do
				table.insert(options, step_values[i])
			end
			return options
		end
		return step_values
	end

	-- Step
	local step_options = { 'trig', '1/48', '1/32', '1/32t', '1/16', '1/16t', '1/16d', '1/8', '1/8t', '1/8d', '1/4', '1/4t', '1/4d', '1/2', '1', '2', '4', '8', '16' }

	self.step = o.step or 0

	Registry.add('add_option', track .. 'step_length', 'Step Length', step_options, 1)
	Registry.set_action(track .. 'step_length', function(d)
		local step_values = calculate_step_values(true)
		self:kill()
		App.settings[track .. 'step_length'] = d
		self.step_length = step_values[d]
		self.step_count = 0
	end)

	-- Reset Step
	Registry.add('add_option', track .. 'reset_step_length', 'Reset', step_options, 1)
	Registry.set_action(track .. 'reset_step_length', function(d)
		local step_values = calculate_step_values(true)
		self:kill()
		App.settings[track .. 'reset_step_length'] = d
		self.reset_step_length = step_values[d]
		self.reset_tick = 1
		self.step_count = 0
	end)

	self.reset_step_count = o.reset_step_count or 0
	self.reset_tick = o.reset_tick or 1
	Registry.add('add_number', track .. 'reset_step_count', 'Reset step', 0, 64, 0, function(param)
		local v = param:get()
		if v == 0 then
			return 'off'
		elseif v == 1 then
			return '1 step'
		else
			return v .. ' steps'
		end
	end)

	self.step_count = 0

	Registry.set_action(track .. 'reset_step_count', function(d)
		App.settings[track .. 'reset_step_count'] = d
		self.reset_step_count = d
		self.reset_tick = 1
		self.step_count = 0
	end)

	-- Chance
	local chance_spec = controlspec.UNIPOLAR:copy()
	chance_spec.default = 0.5

	self.chance = o.chance or 0.5
	Registry.add('add_control', track .. 'chance', 'Chance', chance_spec)
	Registry.set_action(track .. 'chance', function(d)
		App.settings[track .. 'chance'] = d
		self.chance = d
	end)

	-- Slew
	local slew_spec = controlspec.UNIPOLAR:copy()
	slew_spec.default = 0.0

	self.slew = o.slew or 0

	Registry.add('add_control', track .. 'slew', 'Slew', slew_spec)
	Registry.set_action(track .. 'slew', function(d)
		App.settings[track .. 'slew'] = d
		self.slew = d
	end)

	-- Scale

	Registry.add('add_number', track .. 'scale_select', 'Scale', 0, 3, 0, function(param)
		local ch = param:get()
		if ch == 0 then
			return 'off'
		else
			return ch
		end
	end)

	self.scale_interrupt = function() self.output_device:emit('interrupt', { type = 'interrupt_scale', scale = self.scale, ch = self.midi_out }) end

	Registry.set_action(track .. 'scale_select', function(d)
		App.settings[track .. 'scale_select'] = d

		self:kill()

		local last = self.scale_select

		if self.scale then
			self.scale:off('interrupt', self.scale_interrupt)
			self.scale:off('scale_changed', self.scale_interrupt)
		end

		self.scale = App.scale[d]
		self.scale_select = d

		self.scale_interrupt = function() self.output_device:emit('interrupt', { type = 'interrupt_scale', scale = self.scale, ch = self.midi_out }) end

		self.scale:on('interrupt', self.scale_interrupt)
		self.scale:on('scale_changed', self.scale_interrupt)

		self:build_chain()
	end)

	-- Clip slot: 0 = live buffer, 1..Clip.MAX_BANK_SLOTS = bank slot (preset + launch on transport start)
	Registry.add('add_number', track .. 'clip_slot', 'Clip Slot', 0, Clip.MAX_BANK_SLOTS, 0, function(param)
		local v = param:get()
		if v == 0 then return 'live' end
		return tostring(v)
	end)
	Registry.set_action(track .. 'clip_slot', function(d)
		App.settings[track .. 'clip_slot'] = d
		if App.flags.state.initializing then return end
		self:clip_slot_request(d)
	end)

	-- Trigger
	self.trigger = o.trigger or 36
	Registry.add('add_number', track .. 'trigger', 'Trigger', 0, 127, 36)
	Registry.set_action(track .. 'trigger', function(d)
		self:kill()
		self.trigger = d
	end)

	-- Step Length
	self.bitwise_length = o.bitwise_length or 16
	Registry.add('add_number', track .. 'bitwise_length', 'Bitwise Length', 1, 16, 16)
	Registry.set_action(track .. 'bitwise_length', function(d)
		App.settings[track .. 'bitwise_length'] = d
		self.bitwise_length = d
	end)

	-- Note Range
	-- Lower
	self.note_range_lower = o.note_range_lower or 0

	Registry.add('add_number', track .. 'note_range_lower', 'From Note', 0, 127, 0)
	Registry.set_action(track .. 'note_range_lower', function(d)
		App.settings[track .. 'note_range_lower'] = d
		self:kill()
		self.note_range_lower = d

		Registry.set(track .. 'note_range_upper', util.clamp(params:get(track .. 'note_range') * 12 + d, 0, 127), 'note_range_calc')
	end)

	-- Upper

	self.note_range_upper = o.note_range_upper or 127

	Registry.add('add_number', track .. 'note_range_upper', 'To Note', 0, 127, 127)
	Registry.set_action(track .. 'note_range_upper', function(d)
		self:kill()
		self.note_range_upper = d

		Registry.set(track .. 'note_range', math.ceil((d - self.note_range_lower) / 12), 'note_range_lower_calc')

		if d < self.note_range_lower then Registry.set(track .. 'note_range_lower', d, 'note_range_lower_set') end
	end)

	params:hide(track .. 'note_range_upper')

	-- Octaves (convenience parameter thats easier to set than two ranges)
	Registry.add('add_number', track .. 'note_range', 'Octaves', 1, 11, 2)
	Registry.set_action(track .. 'note_range', function(d)
		App.settings[track .. 'note_range'] = d
		Registry.set(track .. 'note_range_upper', util.clamp(d * 12 + self.note_range_lower, 0, 127), 'note_range_upper_set')
	end)

	-- Crow In

	self.crow_in = o.crow_in or 1

	Registry.add('add_number', track .. 'crow_in', 'Crow In', 1, 2, 1)
	Registry.set_action(track .. 'crow_in', function(d)
		self:kill()
		self.crow_in = d

		if self.input_type == 'crow' then self:load_component(Input) end
	end)

	-- Crow Out
	self.crow_out = o.crow_out or 1

	local crow_options = { '1 + 2', '3 + 4' }

	Registry.add('add_option', track .. 'crow_out', 'Crow Out', crow_options, 1)
	Registry.set_action(track .. 'crow_out', function(d)
		self:kill()
		self.crow_out = d
		if self.output_type == 'crow' then self.output = App.crow.output[d] end
		self:enable()
	end)

	-- Shoot program change events to input device
	Registry.add('add_number', track .. 'program_change_in', 'PC In', 0, 128, 0)
	Registry.set_action(track .. 'program_change_in', function(d)
		App.settings[track .. 'program_change_in'] = d
		if d > 0 then self.input_device:program_change(d - 1, self.midi_in) end
	end)

	-- Shoot program change events to output device
	Registry.add('add_number', track .. 'program_change_out', 'PC Out', 0, 128, 0)
	Registry.set_action(track .. 'program_change_out', function(d)
		App.settings[track .. 'program_change_out'] = d
		if d > 0 and self.output_type == 'midi' and self.output_device then self.output_device:program_change(d - 1, self.midi_out) end
	end)

	-- Voice
	-- this may also be a shit implementation but I dont know yet. mono and voice are redundant
	self.voice = o.voice or 1
	self.mono = o.mono or false
	Registry.add('add_option', track .. 'voice', 'Voice', { 'polyphonic', 'mono' }, 1)
	Registry.set_action(track .. 'voice', function(d)
		-- whether track is polyphonic or mono
		if d == 1 then
			self.mono = false
		else
			self.mono = true
		end
	end)

	-- Monitor (controls input flow: IN = always on, AUTO = on when not playing, OFF = never)
	Registry.add('add_option', track .. 'monitor', 'Monitor', { 'IN', 'AUTO', 'OFF' }, 2)
	Registry.set_action(track .. 'monitor', function(d)
		self.monitor = d
		-- Update mute_input based on monitor setting
		self:update_monitor_state()
		-- Trigger menu redraw to show updated value
		App.screen_dirty = true
	end)

	-- Helper function to update mute_input based on monitor setting and playback state
	function Track:update_monitor_state()
		if self.monitor == 1 then
			-- IN: always allow input (for overdub when clip is playing)
			self:emit('mute_input', false)
		elseif self.monitor == 2 then
			-- AUTO: allow input when clip is not actively playing
			local clip_actively_playing = self.clip:is_actively_playing() or false
			self:emit('mute_input', clip_actively_playing)
		elseif self.monitor == 3 then
			-- OFF: never allow input
			self:emit('mute_input', true)
		end
	end

	-- Playback mode (stored in Clip component)
	Registry.add('add_option', track .. 'buffer_playback_mode', 'Playback Mode', { 'Default', 'Input', 'Direct', 'Scale Only' }, 1)
	Registry.set_action(track .. 'buffer_playback_mode', function(d)
		-- Playback mode is stored in Clip component (not Buffer)
		self.clip.playback_mode = d
	end)

	-- Clip Loop (controls clip playback: true = continuous loop, false = one-shot)
	-- Buffer always loops and overwrites - loop control is for Clip playback only
	Registry.add('add_binary', track .. 'buffer_loop', 'Clip Loop', 'toggle', 1)
	Registry.set_action(track .. 'buffer_loop', function(d)
		App.settings[track .. 'buffer_loop'] = d
		local buffer_loop = (d > 0)
		self.clip.buffer_loop = buffer_loop
		-- Trigger menu redraw to show updated value
		App.screen_dirty = true
	end)
end

-- Updates current settings using an object.
-- Using the "or" trick for applying default values does not work with false values
function Track:update(o, silent)
	for prop, value in pairs(o) do
		if self[prop] ~= nil then
			self[prop] = value

			if not silent then Registry.set('track_' .. self.id .. '_' .. prop, value, 'track_property_set') end
		else
			-- This will enforce all parameters are set
			error('Attempt to update Track ' .. self.id .. ' value that doesnt exist!')
		end
	end
end

function Track:remove_trigger()
	if self.input_device then self.input_device:remove_trigger(self) end
end

function Track:add_trigger()
	if self.input_device then self.input_device:add_trigger(self) end
end

function Track:enable()
	if App.flags.state.initializing then return end

	if self.output_type == 'midi' and self.midi_out > 0 or self.output_type == 'crow' then
		self.enabled = true
		self:build_chain()
	else
		self:disable()
	end
end

function Track:disable() self.enabled = false end

-- Event listener management
function Track:on(event_name, listener)
	if not self.event_listeners[event_name] then self.event_listeners[event_name] = {} end
	table.insert(self.event_listeners[event_name], listener)

	return function() self:off(event_name, listener) end
end

function Track:off(event_name, listener)
	if self.event_listeners and self.event_listeners[event_name] then
		for i, l in ipairs(self.event_listeners[event_name]) do
			if l == listener then
				table.remove(self.event_listeners[event_name], i)
				break
			end
		end
	end
end

function Track:emit(event_name, ...)
	if self.event_listeners and self.event_listeners[event_name] then
		for _, listener in ipairs(self.event_listeners[event_name]) do
			listener(...)
		end
	end
end

-- Sync clip_slot param from clip state (silent — does not re-trigger launch)
function Track:sync_clip_slot_param()
	local pid = 'track_' .. self.id .. '_clip_slot'
	local slot = 0
	if self.clip and self.clip.current_slot then slot = self.clip.current_slot end
	if params:get(pid) == slot then return end
	Registry.set(pid, slot, 'clip_state_sync', nil, true)
	App.settings[pid] = slot
end

-- Apply clip_slot param: queue synced load/unload when playing, immediate when stopped
function Track:clip_slot_request(slot)
	local clip = self.clip
	if not clip then return end
	local pid = 'track_' .. self.id .. '_clip_slot'
	if slot > 0 and not clip.clip_bank[slot] then
		print('Track ' .. self.id .. ': no clip in bank slot ' .. slot)
		local revert = clip.current_slot or 0
		Registry.set(pid, revert, 'clip_slot_invalid', nil, true)
		App.settings[pid] = revert
		return
	end
	if slot > 0 and clip.current_slot == slot then return end
	if slot == 0 and not clip.current_slot and not clip.buffer_frozen then return end

	if App.playing then
		if slot == 0 then
			clip:queue_clip_slot_unload()
		else
			clip:queue_clip_slot_load(slot)
		end
	else
		if slot == 0 then
			clip:unload_clip()
		else
			clip:load_clip_from_bank(slot)
		end
		self:sync_clip_slot_param()
	end
end

-- Save current track paramaeters as the current preset
function Track:save(o)
	local track = 'track_' .. self.id .. '_'

	for prop, value in pairs(o) do
		if self[prop] ~= nil then Registry.set(track .. prop, value, 'track_prop_update') end
	end
end

function Track:load_component(component)
	local option = self[component.name .. '_type']
	local type = nil

	if component.types ~= nil then type = component.types[option] end

	local props = {
		track = self,
		id = self.id,
		type = option,
	}

	if type ~= nil then
		-- Assign type-specific properties
		for _, prop in ipairs(type.props) do
			props[prop] = self[prop]
		end
	end

	-- Instantiate the component
	self[component.name] = component:new(props)
end

-- Returns a function that takes an ordered component list and chains the output to input based on list order
function Track:chain_components(components, process_name)
	local track = self
	return function(s, input)
		if track.enabled then
			-- Translate internal process names to user‑facing chain types so
			-- cfg.chains can match { 'midi', 'transport', … }.
			local chain_type
			if process_name == 'process_midi' then
				chain_type = 'midi'
			elseif process_name == 'process_transport' then
				chain_type = 'transport'
			else
				chain_type = process_name
			end
			local chain_tracer = Tracer.chain(self.id, chain_type)
			-- Add correlation ID for flow tracking
			input = Tracer.add_correlation_id(input)
			chain_tracer:log_flow('chain_start', input)

			local output = input
			for i, trackcomponent in ipairs(components) do
				if trackcomponent[process_name] then
					local prev_output = output
					output = trackcomponent[process_name](trackcomponent, output, track)
					chain_tracer:log_flow(trackcomponent.name, prev_output, output)
					if output == nil then
						chain_tracer:log_flow('chain_terminated', prev_output)
						return
					end
				end
			end
			chain_tracer:log_flow('chain_complete', input, output)
			return output
		end
	end
end

-- Builds multiple component chains in single call.
function Track:build_chain()
	local full_chain = { self.auto, self.buffer, self.clip, self.input, self.scale, self.mute, self.output }

	local send = { self.mute, self.output }

	self.process_transport = self:chain_components(full_chain, 'process_transport')
	self.process_midi = self:chain_components(full_chain, 'process_midi')

	self.send = self:chain_components(send, 'process_midi')
	self.send_input = self:chain_components({ self.scale, self.mute, self.output }, 'process_midi')
	self.send_scale = self:chain_components({ self.scale }, 'process_midi')
	self.send_output = self:chain_components({ self.output }, 'process_midi')
end

-----------
function Track:kill()
	if self.output_device then self.output_device:emit('kill', { type = 'kill' }) end
	self.note_on = {}
end

return Track
