local Tracer = require('Foobar/lib/utilities/tracer')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/track/'
local Auto = require(path_name .. 'auto')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Scale = require(path_name .. 'scale')
local Mute = require(path_name .. 'mute')
local Output = require(path_name .. 'output')


-- Define a new class for Track
local Track = {}

-- Constructor
function Track:new(o)
	o = o or {}

	if o.id == nil then
		error("Track:new() missing required 'id' parameter.")
	end
	
	setmetatable(o, self)
	self.__index = self

	o.id = o.id
	o:set(o)

	self.load_component(o, Auto)
	self.load_component(o, Input)
	self.load_component(o, Seq)
	self.load_component(o, Mute)
	self.load_component(o, Output)

	o.scale = App.scale[o.scale_select]

	self.build_chain(o)
	
	o:on('mixer_event',function(data)
		if o.output_device  then
			o.output_device:send(data)
		end
	end)
	
	App:on('transport_event', function(data)
		if o.process_transport and o.enabled then	
			o.process_transport(o,data)
		end
	end)

	o:on('cc_event',function(data)

		if o.output_device  then
			o.output_device:send(data)
		end
	end)

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

	local track = 'track_' .. self.id ..'_'

	params:add_group('Track '.. self.id, 23)

	
	params:add_text(track .. 'name', 'Name', self.name)
	params:set_action(track .. 'name', function(d) 
		self.name = d
	end)

	-- Input Devive Listeners
	local function input_event(data)
		-- Midi Events are bound by the track's Input component
		if data.type == "note_on" then
			self.note_on[data.note] = data
		elseif data.type == "note_off" then
			self.note_on[data.note] = nil
		elseif (data.type == "cc") then
			-- if self.midi_in > 0 and data.ch == self.midi_in then
			-- 	self:emit('cc_event', data)
			-- end
		end
	end

	-- Device In/Out
	local midi_devices =  App.device_manager.midi_device_names

	self.device_in = 1
	params:add_option(track .. "device_in", "Device In", midi_devices)
	
	params:set_action(track .. 'device_in',function(d)
		self.device_in = d

		-- Remove old input device listeners
		if self.input_device then
			self:remove_trigger()
		end

		self.input_device = App.device_manager:get(d)
		self:add_trigger()
		self:load_component(Input)
		self:enable()
	end)
	
	self.device_out = d
	params:add_option(track .. "device_out", "Device Out",midi_devices,2)
	params:set_action(track .. 'device_out',function(d)
		self.device_out = d
		self.output_device = App.device_manager:get(d)
		self:load_component(Output)
		self:enable()
	end)

	-- Input Type
	local param_trace = require('Foobar/lib/utilities/param_trace')
	
	param_trace.add_with_trace('add_option', track .. 'input_type', 'Input Type', Input.options, 1)
	param_trace.set_action_with_trace(track .. 'input_type', function(d)
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
	params:add_option(track .. 'output_type', 'Output Type', Output.options, 1)
	params:set_action(track .. 'output_type',function(d)
		self:kill()
		self.output_type = Output.options[d]
		self:load_component(Output)
		self:enable()
	end)

	-- MIDI In
	self.midi_in = o.midi_in or 0
	params:add_number(track .. 'midi_in', 'MIDI In', 0, 17, 0, function(param)
		local ch = param:get()
		if ch == 0 then 
			return 'off'
		elseif ch == 17 then
			return 'all'
		else
			return ch
		end
	end)
	
	params:set_action(track .. 'midi_in', function(d) 
		self:kill()

		self.midi_in = d
		self:load_component(Input)
		self:enable()
	end
	)

	-- MIDI Out
	self.midi_out = o.midi_out or 0
	params:add_number(track .. 'midi_out', 'MIDI Out', 0, 17, 0, function(param)
		local ch = param:get()
		if ch == 0 then 
			return 'off'
		elseif ch == 17 then
			return 'all'
		else
			return ch
		end
	end)

	params:set_action(track .. 'midi_out', function(d) 
		self:kill()
		self.midi_out = d
		self:load_component(Output)
		
		self:enable()
	end)

	-- -- MIDI Thru
	-- self.midi_thru = o.midi_thru or false
	-- params:add_binary(track .. 'midi_thru','MIDI Thru','toggle', 0)
	-- params:set_action(track .. 'midi_thru',function(d)
	-- 	self.midi_thru = (d>0)
	-- end)

	 params:add_binary(track .. 'mixer', 'Mixer', 'toggle', 0)
	 params:set_action(track .. 'mixer', function(d)
		if App.flags.state.initializing then return end

		 if d == 0 then
			App.device_manager.mixer:remove_track(self)
		 else
		 	App.device_manager.mixer:add_track(self)
		 end
	 end)

	-- Arpeggio
	local arp_options = {'up','down','up down', 'down up', 'converge', 'diverge'}
	self.arp = o.arp or arp_options[1]
	params:add_option(track .. 'arp','Arpeggio',arp_options, 1)
	params:set_action(track .. 'arp',function(d)
		App.settings[track .. 'arp'] = d
		self.arp = arp_options[d]
	end)


	-- Step
	local step_values =  {0,2,3,4,6,8,9,12,16,18,24,32,36,48,96,192,384,768, 1536}
	local step_options = {'midi trig','1/48','1/32', '1/32t', '1/16', '1/16t', '1/16d','1/8', '1/8t','1/8d','1/4','1/4t','1/4d','1/2','1','2','4','8','16'}
	
	self.step = o.step or step_values[1]
	
	params:add_option(track .. 'step','Step',step_options, 1)
	params:set_action(track .. 'step',function(d)
		self:kill()
		App.settings[track .. 'step'] = d
		self.step = step_values[d]
		self.reset_tick = 1
		self.step_count = 0
	end)

	-- Reset Step
	self.reset_step = o.reset_step or 0
	self.reset_tick = o.reset_tick or 1
	params:add_number(track .. 'reset_step','Reset step',0,64,0, function(param) 
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
	
	params:set_action(track .. 'reset_step',function(d)
		App.settings[track .. 'reset_step'] = d
		self.reset_step = d
		self.reset_tick = 1
		self.step_count = 0
	end)

	-- Chance
	local chance_spec = controlspec.UNIPOLAR:copy()
	chance_spec.default = 0.5

	self.chance = o.chance or 0.5
	params:add_control(track .. 'chance', 'Chance', chance_spec)
	params:set_action(track .. 'chance', function(d) 
		App.settings[track .. 'chance'] = d
		self.chance = d
	end)

	-- Slew
	local slew_spec = controlspec.UNIPOLAR:copy()
	slew_spec.default = 0.0

	self.slew = o.slew or 0

	params:add_control(track .. 'slew', 'Slew', slew_spec)
	params:set_action(track .. 'slew', function(d) 
		App.settings[track .. 'slew'] = d
		self.slew = d
	end)
	
	-- Scale
	self.scale_select = o.scale_select or 0
	
	params:add_number(track .. 'scale_select', 'Scale', 0, 3, 0,function(param)
		local ch = param:get()
		if ch == 0 then 
		   return 'off'
		else
		   return ch
		end
	end)
	

	self.scale_interrupt = function()
		self.output_device:emit('interrupt', {type='interrupt_scale', scale=self.scale, ch=self.midi_out})
	end

	params:set_action(track .. 'scale_select', function(d) 
		App.settings[track .. 'scale_select'] = d

		self:kill()

		local last = self.scale_select
		
		if self.scale then
			self.scale:off('interrupt', self.scale_interrupt)
			self.scale:off('scale_changed', self.scale_interrupt)
		end

		self.scale = App.scale[d]
		self.scale_select = d 

		self.scale_interrupt = function()
			self.output_device:emit('interrupt', {type='interrupt_scale', scale=self.scale, ch=self.midi_out})
		end

		self.scale:on('interrupt', self.scale_interrupt)
		self.scale:on('scale_changed', self.scale_interrupt)

		self:build_chain()
	end)

	-- Trigger
	self.trigger = o.trigger or 36
	params:add_number(track .. 'trigger', 'Trigger', 0, 127, 36)
	params:set_action(track .. 'trigger', function(d) 
		self:kill()
		self.trigger = d
	end)

	-- Step Length
	self.step_length = o.step_legnth or 16
	params:add_number(track .. 'step_length', 'Step Length', 1, 16, 16)
	params:set_action(track .. 'step_length', function(d) 
		App.settings[track .. 'step_length'] = d
		self.step_length = d
	end)


	-- Note Range 
	-- Lower
	self.note_range_lower = o.note_range_lower or 0
	
	params:add_number(track .. 'note_range_lower', 'From Note', 0, 127, 0)
	params:set_action(track .. 'note_range_lower', function(d) 
		App.settings[track .. 'note_range_lower'] = d
		self:kill()
		self.note_range_lower = d

		params:set(track .. 'note_range_upper', util.clamp(params:get(track .. 'note_range') * 12 + d,0,127))			
	end)

	-- Upper

	self.note_range_upper = o.note_range_upper or 127

	params:add_number(track .. 'note_range_upper', 'To Note', 0, 127, 127)
	params:set_action(track .. 'note_range_upper', function(d) 
		self:kill()
		self.note_range_upper = d

		params:set(track .. 'note_range', math.ceil((d - self.note_range_lower) / 12))

		if d < self.note_range_lower then
			params:set(track .. 'note_range_lower', d)
		end
		
	end)
	
	params:hide(track .. 'note_range_upper')

	-- Octaves (convenience parameter thats easier to set than two ranges)
	params:add_number(track .. 'note_range', 'Octaves', 1, 11, 2)
	params:set_action(track .. 'note_range', function(d) 
		App.settings[track .. 'note_range'] = d
		params:set(track .. 'note_range_upper', util.clamp(d * 12 + self.note_range_lower,0,127))
	end)
	

	-- Crow In
	
	self.crow_in = o.crow_in or 1

	params:add_number(track .. 'crow_in', 'Crow In', 1, 2, 1)
	params:set_action(track .. 'crow_in', function(d) 
		self:kill()
		self.crow_in = d

		if self.input_type == 'crow' then
			self:load_component(Input)
		end
	end)

	-- Crow Out
	self.crow_out = o.crow_out or 1

	local crow_options = {'1 + 2', '3 + 4'}
	
	params:add_option(track .. 'crow_out', 'Crow Out', crow_options, 1)
	params:set_action(track .. 'crow_out', function(d) 		
		self:kill()
		self.crow_out = d
		if self.output_type == 'crow' then
			self.output = App.crow.output[d]
		end
		 self:enable()
	end)

	-- Shoot program change events
	params:add_number(track .. 'program_change', 'Program Change', 0,16,0)
	params:set_action(track .. 'program_change', function(d) 
		App.settings[track .. 'program_change'] = d
		if d > 0 then
		    self.input_device:program_change (d-1, self.midi_in)
		end
	end)

	-- Voice
	-- this may also be a shit implementation but I dont know yet. mono and voice are redundant
	self.voice = o.voice or 1
	self.mono = o.mono or false
	params:add_option(track .. 'voice','Voice',{'polyphonic','mono'}, 1)
	params:set_action(track .. 'voice',function(d)
		-- whether track is polyphonic or mono
		if d == 1 then
			self.mono = false
		else
			self.mono = true
		end
	end)

end

-- Updates current settings using an object.
-- Using the "or" trick for applying default values does not work with false values
function Track:update(o, silent) 
	for prop, value in pairs(o) do
		if self[prop] ~= nil then
			self[prop] = value

			if not silent then
				params:set('track_' .. self.id .. '_' .. prop, value)
			end
		else
			-- This will enforce all parameters are set
			error('Attempt to update Track '.. self.id ..' value that doesnt exist!')
		end
	end
end

function Track:remove_trigger()
	if self.input_device then
		self.input_device:remove_trigger(self)
	end
end

function Track:add_trigger()
	if self.input_device then
		self.input_device:add_trigger(self)
	end
end

function Track:enable()
	if App.flags.state.initializing then return end
	
	if self.output_type == 'midi' and self.midi_out > 0  or self.output_type == 'crow' then
		self.enabled = true
		self:build_chain()

	else
		self:disable()
	end
end

function Track:disable()
	self.enabled = false
end

-- Event listener management
function Track:on(event_name, listener)
    if not self.event_listeners[event_name] then
        self.event_listeners[event_name] = {}
    end
    table.insert(self.event_listeners[event_name], listener)

    return function()
        self:off(event_name, listener)
    end
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
	if self.event_listeners and self.event_listeners[event_name]then
        for _, listener in ipairs(self.event_listeners[event_name]) do
            listener(...)
        end
    end
end


-- Save current track paramaeters as the current preset
function Track:save(o)
	local track = 'track_' .. self.id .. '_'

	for prop, value in pairs(o) do
		if self[prop] ~= nil then
			params:set(track .. prop, value)
		end
	end
end

function Track:load_component(component)
    local option = self[component.name .. '_type']
    local type = nil


    if component.types ~= nil then
        type = component.types[option]
    end

    local props = {
        track = self,
        id = self.id,
        type = option
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
	
	local send_input = {self.scale, self.mute, self.output} 
	local chain = {self.auto, self.input, self.seq, self.scale, self.mute, self.output} 
	local send =  {self.mute, self.output}

	self.process_transport = self:chain_components(chain, 'process_transport')
	self.process_midi = self:chain_components(chain, 'process_midi')

	self.send = self:chain_components(send, 'process_midi')
	self.send_input = self:chain_components(send_input, 'process_midi')
	self.send_output = self:chain_components({self.output}, 'process_midi')
end

-----------
function Track:kill()
	if self.output_device then
		self.output_device:emit('kill',{type='kill'})
	end
	self.note_on = {}
end

return Track