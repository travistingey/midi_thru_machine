local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')

-- Output Class
-- last component in a Track's process chain that handles output to devices
local Output = TrackComponent:new()
Output.__base = TrackComponent
Output.name = 'output'

function Output:set(o)
	self.__base.set(self, o) -- call the base set method first    
	self.channel = o.channel or 0
	self.note_on = {}
end

Output.options = {'midi','crow'}
Output.params = {'crow_out','slew'} -- Update this list to dynamically show/hide Track params based on Input type

Output.types = {}

Output.types['midi'] = {
	props = {},
	midi_event = function(s,data, track)
		if data ~= nil and s.channel > 0 then
			local send = {}

			for i,v in pairs(data) do
				send[i] = v
			end
			
			send.ch = s.channel
			track:handle_note(data,nil,'output')
			s:handle_note(data)
			App.midi_out:send(send)
			
			return data
		end
	end
}

Output.types['crow'] = {
	props = {},
	midi_event = function(s,data, track)
		if data ~= nil and data.note ~= nil then
			local volts = (data.note - track.note_range_lower) / 12
			local voct = 1
			local gate = 2

			if s.channel == 1 then
				voct = 1
				gate = 2
			elseif s.channel == 2 then
				voct = 3
				gate = 4
			end

			crow.output[voct].action = '{to(dyn{note = '.. volts .. '},dyn{slew = ' .. track.slew .. '})}'
			crow.output[voct].dyn.note = volts    
			crow.send('output[' .. voct .. ']()')

			if data.type == 'note_on' then
				crow.output[gate].volts = 5
			elseif data.type == 'note_off' then
				crow.output[gate].volts = 0
			end

		end
		track:handle_note(data)
		s:handle_note(data)
 		return data
	end

}

function Output:handle_note(data) 
	if data ~= nil then
		if data.type == 'note_on' then    
			if self.note_on[data.note] ~= nil then
				-- the same note_on event came but wasn't processed
				local off = {
					type = 'note_off',
					note = data.note,
					vel = data.vel,
					ch = self.channel,
				}
				
				self.note_on[data.note] = data

				if self.type == 'midi' then
					App.midi_out:send(off)
				elseif self.type == 'crow' then
					if self.channel == 1 then
						crow.output[2].volts = 0
					elseif self.channel == 2 then
						crow.output[4].volts = 0
					end
				end
			end

			data.id = data.note -- id is equal to the incoming note to track note off events for quantized notes
			self.note_on[data.id] = data

		elseif data.type == 'note_off' then
			local off = data
			if self.note_on[data.note] ~= nil then
				self.note_on[data.note] = nil
			end
		end

	end
end

function Output:kill()

	for n,data in pairs(self.note_on) do
		local off = {
			type = 'note_off',
			note = data.note,
			vel = data.vel,
			ch = self.channel,
		}
		
		self.note_on[data.note] = data

		if self.type == 'midi' then
			App.midi_out:send(off)
		elseif self.type == 'crow' then
			if self.channel == 1 then
				crow.output[2].volts = 0
			elseif self.channel == 2 then
				crow.output[4].volts = 0
			end
		end
	end

end

return Output