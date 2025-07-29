local path_name = 'Foobar/lib/'
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

-- Output Class
-- last component in a Track's process chain that handles output to devices
local Output = {}
Output.name = 'output'
Output.__index = Output
setmetatable(Output,{ __index = TrackComponent })

function Output:new(o)
    o = o or {}
    setmetatable(o, self)
    TrackComponent.set(o,o)
    o:set(o)
    return o
end

function Output:set(o)
	for i, prop in ipairs(Output.params) do
		self[prop] = o[prop]
	end
end

Output.options = {'midi','crow'}
Output.params = {'crow_out','slew'} -- Update this list to dynamically show/hide Track params based on Input type

Output.types = {}

Output.types['midi'] = {
	props = {},
	midi_event = function(s,data, track)
		if data ~= nil and track.midi_out > 0 then
			local send = {}

			for i,v in pairs(data) do
				send[i] = v
			end
			
			if not (track.midi_out == 17 and send.ch) then
				send.ch = track.midi_out
			end

			track.output_device:send(send)

			return data
		end
	end,
	-- transport_event = function(s,data,track)
	-- 	if track.output_device ~= App.midi_in then
	-- 		track.output_device:send(data)
	-- 	end
	-- end
}

Output.types['crow'] = {
	props = {},
	midi_event = function(s,data, track)
		if data ~= nil and data.note ~= nil then
			
			if data.new_note and data.type == 'note_on' then
				data.note = data.new_note
			end

			local volts = (data.note - track.note_range_lower) / 12
			local voct = 1
			local gate = 2
			
			s.channel = 1
			if s.channel == 1 then
				voct = 1
				gate = 2
			elseif s.channel == 2 then
				voct = 3
				gate = 4
			end

			local action = '{to(dyn{note = '.. volts .. '},dyn{slew = ' .. track.slew .. '})}'
			local dyn = {note = volts}


			if data.type == 'note_on' then
				App.crow:send({action = action, dyn = dyn, ch = voct})
				App.crow:send({volts = 5, ch = gate})
			elseif data.type == 'note_off' then
				App.crow:send({volts = 0, ch = gate})
			end
			
		end

	end

}

return Output