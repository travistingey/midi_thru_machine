local path_name = 'Foobar/lib/'
local App = require(path_name .. 'app')
local TrackComponent = require(path_name .. 'trackcomponent')


-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.

local Seq = TrackComponent:new()
Seq.__base = TrackComponent
Seq.name = 'output'

function Seq:set (o)
    o = o or {}
   
	o.id = o.id or 1
    o.grid = o.grid
    o.div = o.div or 1

    o.value = o.value or {}
    o.length = o.length or 64
    o.tick = o.tick or 0
    o.step = o.step or 1

	o.on_transport = o.on_transport or function() end
	o.on_midi = o.on_midi or function() end
	
	if(o.enabled == nil) then
		o.enabled = true
	end
	
	if(#o.value == 0) then 
		for i = 1, 16 do
			o.value[i] = {}
		end
	end
    o:set_length(o.length)
    
	return o
end

function Seq:set_length(length)
	self.length = length
end


function Seq:transport_event(data)
	-- Tick based sequencer running on 16th notes at 24 PPQN
	if data.type == 'clock' then
		
		self.tick = util.wrap(self.tick + 1, 0, self.div * self.length - 1)

		local next_step = util.wrap(math.floor(self.tick / self.div) + 1, 1, self.length)
		local last_step = self.step
		self.step = next_step

		-- Enter new step. c = current step, l = last step
		if next_step > last_step or next_step == 1 and last_step == self.length then
		
			local last_value = self.value[last_step] or 0
			local value = self.value[next_step] or 0
			
			if self.enabled then 
			    self:action(value)
			end
		end
	end	
    
	if self.on_transport ~= nil and self.enabled then
		self:on_transport(data)
	end

	-- Note: 'Start' is called at the beginning of the sequence
	if data.type == 'start' then
		self.tick = self.div * self.length - 1
		self.step = self.length
	end

end

function Seq:midi_event(data)
	if self.on_midi ~= nil and self.enabled then
		self:on_midi(data)
	end
end

return Seq