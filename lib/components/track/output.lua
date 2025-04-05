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
			
			send.ch = track.midi_out
			track.output_device:send(send)

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
			print('TODO!!! This whole crow business is broken Line 56, Output.lua')
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
			App.crow:send({action = action, dyn = dyn, ch = voct})

			if data.index then
				local step = 5/11
				App.crow:send({volts = (data.index-1) * step + step / 2, ch = 3})
			end

			if data.type == 'note_on' then
				App.crow:send({volts = 5, ch = gate})
			elseif data.type == 'note_off' then
				App.crow:send({volts = 0, ch = gate})
			end
			
		end

	end

}

return Output