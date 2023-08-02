local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')


-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.

local Seq = TrackComponent:new()
Seq.__base = TrackComponent
Seq.name = 'seq'

function Seq:set(o)
	self.__base.set(self, o) -- call the base set method first   
		
	o.id = o.id or 1
    o.grid = o.grid

    o.value = o.value or {}
    o.bank = o.bank or {}
	o.length = o.length or 96
    o.tick = o.tick or 0
    o.step = o.step or 1
    o.div = o.div or 1
	o.recording = false
	o.arm = false

	o.on_step = o.on_step or function(s,value)  end
    
	o.note_on = {}

	if(o.enabled == nil) then
		o.enabled = true
	else
		o.enabled = false
	end

    o:set_length(o.length)
    o:load_bank(1)

	return o
end



-- Save values to bank
function Seq:save_bank(id)
	self.bank[id] = self.value or {}
end

-- Load bank to values
function Seq:load_bank(id)
	self.value = self.bank[id] or {}
end

-- Set Length
function Seq:set_length(length)
	self.length = length
end

-- Handle transport events in process chain
function Seq:transport_event(data)
	-- Tick based sequencer
	if data.type == 'start' then
		self.note_on = {}	
		self.tick = 0
		self.step = self.length
	elseif data.type == 'clock' then
		self.tick = self.tick + 1
		local next_step = (math.floor(self.tick / self.div) - 1) % self.length + 1
		local last_step = self.step
		self.step = next_step

		-- Enter new step. c = current step, l = last step

		-- clock > seq > midi
		if next_step > last_step or next_step == 1 and last_step == self.length then
			if self.enabled then 

				if self.arm then
					print(self.step)
				end

				local current = self:get_step(next_step)

				if #current > 0 then

					table.sort(current, function(a, b)
						return a.offset < b.offset
					end)

					-- Calculate delta between each offset and add it as a new property
					for i = 2, #current do
						current[i].delta = current[i].offset - current[i - 1].offset
					end
					
					current[1].delta = current[1].offset
					
					clock.run(function()
						for i,c in ipairs(current) do
							if c.delta > 0 then
								clock.sync(c.delta)
							end
							
							-- manage note on/off
							if c.type == 'note_on' and  self.note_on[c.note] == nil then
								self.note_on[c.note] = c
								self.track:send(c)	
							elseif c.type == 'note_off' and self.note_on[c.note] ~= nil then
								self.note_on[c.note] = nil
								self.track:send(c)	
							end
						end
					end)

				end

				if self.recording and last_step == self.length then
					for i,c in pairs(self.note_on) do
						-- send off
						local off = c
						off.type = 'note_off'
						if self.recording then
							self.value[#self.value + 1] = off
						end
						self.track:send(off)
					end
				end

				self:on_step(current)
			end
		end
	end	

	return data
end


-- Handle MIDI events in process chain
function Seq:midi_event(data)
	if data.type == 'note_on' then
		if self.note_on[data.note] ~= nil then
			
			-- send off	
			local off = self.note_on[data.note]
			off.type = 'note_off'

			if self.recording then
				self.value[#self.value + 1] = off
			end

			self.track:send(off)
		end

		self.note_on[data.note] = data
	elseif data.type == 'note_off' and self.note_on[data.note] ~= nil then
		self.note_on[data.note] = nil  
	end

	if self.recording then
		data.tick = self.tick
		data.offset = clock.get_beats() - App.last_time

		local val = {}

		for i,v in pairs(data) do
			val[i] = v
		end

		self.value[#self.value + 1] = val
	end

	return data
end

function Seq.grid_event(s,data)
    tab.print(data)
    
end


-- Reset the sequencer values
function Seq:clear()
	self.value = {}
end

-- Returns a table of values for a specified step
function Seq:get_step(step)
	local step_value = {}
	

	for i,v in ipairs(self.value) do
		if (math.floor(v.tick / self.div) - 1) % self.length + 1 == step then
			if v.note ~= nil then
				step_value[ v.type .. '-' .. v.note] = v
			end
		end
	end
	
	local value = {}
	for i,v in pairs(step_value) do
		value[#value + 1] = v
	end

	return value
end

return Seq