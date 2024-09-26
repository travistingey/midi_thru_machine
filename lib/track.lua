local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'components/input')
local Seq = require(path_name .. 'components/seq')
local Scale = require(path_name .. 'components/scale')
local Mute = require(path_name .. 'components/mute')
local Output = require(path_name .. 'components/output')
local Grid = require(path_name .. 'grid')

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
	self.set(o,o) -- Set static variables
	
	self.load_component(o, Input)
	self.load_component(o, Seq)
	self.load_component(o, Mute)

	if o.scale_select > 0 then
		o.scale = App.scale[o.scale_select]
	else
		self.load_component(o,Scale)
	end

	if o.output_type == 'midi' and o.midi_out > 0 then
		o.output = App.output[o.midi_out]
	elseif o.output_type == 'crow' then
		o.output = App.crow.output[o.crow_out]
	else
		self.load_component(o, Output)
	end


	self.build_chain(o)
	
	return o
end

--[[ 
	Set is called initially and keeps a clean list of parameters that are instantiated.
	Track properties must match parameter values 1 to 1 in order for update to manage values.
]]
function Track:set(o)
	self.note_on = {}

	self.active = o.active or false
	self.mono = o.mono or false
	self.voice = o.voice or 0
	self.chord_type = o.chord_type or 1

	local track = 'track_' .. self.id ..'_'

	params:add_group('Track '.. self.id, 21)

	params:add_text(track .. 'name', 'Name', 'Track ' .. o.id)
	-- Input Type
	self.input_type = o.input_type or Input.options[1]
	params:add_option(track .. 'input_type', 'Input Type', Input.options, 1)
	params:set_action(track .. 'input_type',function(d)
		self:kill()
		self.input_type = Input.options[d]
		self:load_component(Input)
		self:build_chain()
		self:set_active()
	end)

	-- Output Type
	self.output_type = o.output_type or Output.options[1]
	params:add_option(track .. 'output_type', 'Output Type', Output.options, 1)
	params:set_action(track .. 'output_type',function(d)
		self:kill()
		self.output_type = Output.options[d]
		
		if self.output_type == 'midi' and self.midi_out > 0 then
			self.output = App.output[self.midi_out]
		elseif self.output_type == 'crow' or self.output_type == 'chord' then
			self.output = App.crow.output[self.crow_out]
		else
			self:load_component(Output)
		end

		self:build_chain()
		self:set_active()
	end)

	-- MIDI In
	self.midi_in = o.midi_in or 0
	params:add_number(track .. 'midi_in', 'MIDI In', 0, 16, 0, function(param)
		local ch = param:get()
		if ch == 0 then 
		   return 'off'
		else
		   return ch
		end
	end)
	
	params:set_action(track .. 'midi_in', function(d) 
		self:kill()
		self.midi_in = d
		self:load_component(Input)
		self:set_active()
	end
	)

	
	-- MIDI Out
	self.midi_out = o.midi_out or 0
	params:add_number(track .. 'midi_out', 'MIDI Out', 0, 16, 0, function(param)
		local ch = param:get()
		if ch == 0 then 
		   return 'off'
		else
		   return ch
		end
	end)

	params:set_action(track .. 'midi_out', function(d) 
		self:kill()
		self.midi_out = d
		
		if self.output_type == 'midi' then
			
			if self.midi_out > 0 then
				self.output = App.output[d]
			else
				self:load_component(Output)
			end

			self:build_chain()
		end
		self:set_active()
	end)

	-- MIDI Thru
	self.midi_thru = o.midi_thru or false
	params:add_binary(track .. 'midi_thru','MIDI Thru','toggle', 0)
	params:set_action(track .. 'midi_thru',function(d)
		self.midi_thru = (d>0)
	end)

	-- Arpeggio
	local arp_options = {'up','down','up down', 'down up', 'converge', 'diverge'}
	self.arp = o.arp or arp_options[1]
	params:add_option(track .. 'arp','Arpeggio',arp_options, 1)
	params:set_action(track .. 'arp',function(d)
		self.arp = arp_options[d]
	end)


	-- Step
	local step_values =  {0,2,3,4,6,8,9,12,16,18,24,32,36,48,96,192,384,768, 1536}
	local step_options = {'midi trig','1/48','1/32', '1/32t', '1/16', '1/16t', '1/16d','1/8', '1/8t','1/8d','1/4','1/4t','1/4d','1/2','1','2','4','8','16'}
	
	self.step = o.step or step_values[1]
	
	params:add_option(track .. 'step','Step',step_options, 1)
	params:set_action(track .. 'step',function(d)
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
	
	params:add_number(track .. 'scale_select', 'Scale', 0, 4, 0,function(param)
		local ch = param:get()
		if ch == 0 then 
		   return 'off'
		else
		   return ch
		end
	end)
 
	params:set_action(track .. 'scale_select', function(d) 
		App.settings[track .. 'scale_select'] = d
		self:kill()
		local last = self.scale_select
		self.scale = App.scale[d]
		self.scale_select = d 
		
		if last ~= self.scale_select then
			self:build_chain()
		end
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
		App.settings[track .. 'note_range_upper'] = d
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
			self:build_chain()
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
			self:build_chain()
		end
		
	end)

	-- Shoot program change events
	params:add_number(track .. 'program_change', 'Program Change', 0,16,0)
	params:set_action(track .. 'program_change', function(d) 
		App.settings[track .. 'program_change'] = d
		if d > 0 then
			print(App.track[self.id].midi_in)
		    App.midi_in:program_change (d-1, App.track[self.id].midi_in)
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

function Track:set_active()
	if self.output_type == 'midi' and self.midi_out > 0  or self.output_type == 'crow' or self.input_type == 'keys' and self.midi_in > 0 then
		self.active = true
	else
		self.active = false
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

	local props = {}
	props.track = self
	props.id = self.id
	props.type = option

	if type ~= nil then
		-- Component with Types that are set via Params
		for i, prop in ipairs(type.props) do
			props[prop] = self[prop] -- Create an object with values passed down from Track
		end
	end

	self[component.name] = component:new(props)

end

-- Returns a function that takes an ordered component list and chains the output to input based on list order
function Track:chain_components(components, process_name)
	local track = self
	return function(s, input)

		if track.debug then
			print(process_name .. ' on track ' .. track.id)
		end
		
		if track.active then
			local output = input
			for i, trackcomponent in ipairs(components) do
				if trackcomponent[process_name] then
					output = trackcomponent[process_name](trackcomponent, output, track)
					if output == nil then return end
				end
			end
			return output
		end

		

	end
end

-- Builds multiple component chains in single call.
function Track:build_chain()
	--[[]]
	local pre_scale =  {self.input, self.seq, self.scale, self.mute, self.output}     
	local post_scale = {self.input, self.scale, self.seq, self.mute, self.output} 
	local test = {self.input,self.output}
	local send_input = {self.seq, self.scale, self.mute, self.output} 
	local send =  {self.mute, self.output}

	
	
	self.process_transport = self:chain_components(post_scale, 'process_transport')
	self.process_midi = self:chain_components(post_scale, 'process_midi')

	self.send = self:chain_components(send, 'process_midi')
	self.send_input = self:chain_components(send_input, 'process_midi')
	self.send_output = self:chain_components({self.output}, 'process_midi')
	self.send_event = self:chain_components(pre_scale, 'process_midi')
end

-----------
function Track:kill()
	
	if self.output then
		self.output:kill()
	end
	self.note_on = {}
end

--[[
	This will handle note_on management, with the ability to specify which chain should send OFF events for interrupts 
	The chain parameter will allow from sending from different parts of the chain
	Input would use, 'send_input', sequencer would 'send', and the any note_off to cancel an incoming 
	note would use 'send_output'
]]

function Track:handle_note(data, chain, debug) -- 'send', 'send_input', 'send_output' etc
	if data ~= nil then
		if data.type == 'note_on' then    
			
			-- Any incoming notes already on will have an off message sent
			if data.id ~= nil then
				-- This note has already been processed
				
			elseif self.note_on[data.note] ~= nil then
				-- the same note_on event came but wasn't processed
				local last =  self.note_on[data.note]
				local off = {
					type = 'note_off',
					note = last.note,
					vel = last.vel,
					ch = last.ch,
				}

				if last and last.id then
					self.note_on[last.id] = nil
				else
					self.note_on[last.note] = nil
				end

				if chain ~= nil then
					if self.debug then
						print(last.id .. ' off sent during note on')
					end
					self[chain](self, off)
				end
			end

			data.id = data.note -- id is equal to the incoming note to track note off events for quantized notes
			self.note_on[data.id] = data

		elseif data.type == 'note_off' then
			local off = data
			if self.note_on[data.note] ~= nil then
				local last =  self.note_on[data.note]
				self.note_on[data.note] = nil
				if last.id then
					self.note_on[last.id] = nil
				end
				data.note = last.note
			end
		end

	end
end


return Track