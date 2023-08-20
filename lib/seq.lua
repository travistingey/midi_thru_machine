local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
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
    
	o.clip_grid = o.clip_grid
	o.seq_grid = o.seq_grid

    o.value = o.value or {}
    o.bank = o.bank or {}
	o.current_bank = o.current_bank or 0
	o.next_bank = o.next_bank or 0
	o.last_bank = o.last_bank or 0
	o.length = o.length or 96
    o.tick = o.tick or 0
    o.step = o.step or o.length
	o.quantize = o.quantize or 96
    o.div = o.div or 6
	
	o.page = o.page or 1
	o.current_note = o.current_note or 36
	o.recording = false
	o.armed		= false
	
	o.arm = {}

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

-- Reduces seq value to unique events per step
function Seq:reduce_values()
	local new_value = {}
		
	for step = 1, self.length do
		local step_value = self:get_step(step)

		for i,v in ipairs(step_value) do
			new_value[#new_value + 1] = v
		end
	end

	self.value = new_value
end

-- Save values to bank
function Seq:save_bank(id)
	local was = #self.value
		self.value = self.buffer
		self:reduce_values()
		self.recording = false
		self.overdub = false
		self.bounce = false
		self.bank[id] = self.value or {}
		print('Save bank ' .. id)
	
end

-- Load bank to values
function Seq:load_bank(id)
	self.value = self.bank[id] or {}
	print('Load bank ' .. id)
end

-- start recording incoming Midi into Seq
function Seq:record()
	self.recording = true
	if not self.overdub and not self.bounce then
	  self.value = {}
	end

	if self.overdub then
		self.buffer = self.value
	else
		self.buffer = {}
	end
	
	local n = self.clip_grid:index_to_grid(self.next_bank)
	self.clip_grid.led[n.x][n.y] = 10
	print('Recording bank ' .. self.next_bank)
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
		
		if self.armed then
			self:arm_event()
		end
	elseif data.type == 'stop' then
		self.recording = false
		self.armed = false

		for i,c in pairs(self.note_on) do
			-- send off
			local off = {
				type = 'note_off',
				note = c.note,
				vel = c.vel,
				ch = c.ch
			}
			self.track:send(off)
		end
		self.note_on = {}
	elseif data.type == 'clock' then
		self.tick = self.tick + 1
		local next_step = (self.tick - 1 ) % self.length + 1
		local last_step = self.step
		self.step = next_step

		-- Enter new step. c = current step, l = last step

		
		-- clock > seq > midi
		if next_step > last_step or next_step == 1 and last_step == self.length then
			
			if self.enabled then 

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
							
							if self.recording and self.bounce then
								if not (c.note and self.track.mute.state[c.note]) then
									self.buffer[#self.buffer + 1] = c
								end
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

				self:on_step(current)
				
				-- Handle arm events
				if (self.armed and self.tick % self.quantize == 0) then
					self:arm_event()
				end
			end
		end
	end	

	self:set_seq_grid()

	return data
end

-- Handle arm events
function Seq:arm_event()
	local c = self.clip_grid:index_to_grid(self.current_bank)
					
	if c then
		if self.bank[self.current_bank] == nil then
			self.clip_grid.led[c.x][c.y] = 0
		else
			self.clip_grid.led[c.x][c.y] = 1
		end
	end

	local actions = {}

	if self.armed then
		if type(self.armed) == 'table' then
			actions = self.armed
		else
			actions = {self.armed}
		end
	end

	for i,action in ipairs(actions) do
		if action == 'record' then
			self:record()
		elseif action == 'bounce' then
		  self.bounce = true
		  self:record()
		elseif action == 'overdub' then
		  self.overdub = true
		  self:record()
		elseif action == 'save' then
			self:save_bank(self.next_bank)
		elseif action == 'load' then
			self:load_bank(self.next_bank)
			self:set_seq_grid()
		elseif action == 'cancel' then
			self:clear()
		end
	end
	
	self.current_bank = self.next_bank
	self.next_bank = 0
	self:set_clip_grid()
	self.armed = false
end

-- Handle MIDI events in process chain
function Seq:midi_event(data)
	if data.type == 'note_on' then
		self.note_on[data.note] = data
	elseif data.type == 'note_off' and self.note_on[data.note] ~= nil then
		self.note_on[data.note] = nil  
	end

	if self.recording then

		if data.note and self.track.mute.state[data.note] then
			goto continue
		end

		data.tick = self.tick
		data.step = (self.tick - 1) % self.length + 1
		data.offset = clock.get_beats() - App.last_time

		local val = {}

		for i,v in pairs(data) do
			val[i] = v
		end
    
    if not self.bounce then
		   self.value[#self.value + 1] = val
    end
	
		self.buffer[#self.buffer + 1] = val

		::continue::
	end

	
	return data
end

function Seq:seq_grid_event(data)
	
	--handle function pads
	if data.type ~= 'pad' then
		print(data.type ..' seq')
	end

	self.seq_grid:refresh()
end


function Seq:set_seq_grid()
	
	local wrap = 8
	local page_count = math.ceil( math.ceil(self.length/self.div) / wrap)

	local grid = self.seq_grid
	local seq = self

	if grid.active then
		grid:for_each(function(s,x,y)
			local page = math.ceil( math.ceil(seq.step/seq.div) / wrap)

			grid.led[x][y] = 0
			
		end)

		for i,v in ipairs(self.value) do
			if v.type == 'note_on' then
				local page = math.ceil( math.ceil(v.step/self.div) / wrap)
				
				if self.page == page then 
					local x = math.ceil(v.step / self.div) - (page - 1) * wrap
					local y = v.note + 1
					grid.led[x][y] = 1
				end
			end
		end

		grid:refresh()
	end
end

-- Set the clip grid LEDs
function Seq:set_clip_grid()
	self.clip_grid:for_each(function(s,x,y,i)

		if(self.bank[i])then
			s.led[x][y] = 1
		else
			s.led[x][y] = 0
		end

		if i == self.current_bank then
			if self.recording then
				s.led[x][y] = 5
			elseif (self.bank[i]) then
				s.led[x][y] = 3
			else
				s.led[x][y] = 0
			end
		end

		local actions = {}

		if self.armed then
			if type(self.armed) == 'table' then
				actions = self.armed
			else
				actions = {self.armed}
			end
		end

		for _,action in ipairs(actions) do
			if i == self.next_bank then
				if action == 'record' or action == 'save' then
					s.led[x][y] = {7,true}
				elseif  action == 'overdub' then
					s.led[x][y] = {83,true}

				elseif  action == 'bounce' then
					s.led[x][y] = {45,true}
				else
					s.led[x][y] = {1,true}
				end
			end
		end

	end)

	if self.clip_grid.active then
		self.clip_grid:refresh()
	end
end

-- Recording clip
function Seq:clip_grid_event(data)

	if data.type == 'pad' then

		local grid = self.clip_grid
		local index = grid:grid_to_index(data)

		local last = self.next_bank
		local last_bank = self.bank[last]
		
		self.next_bank = index

		local same = (self.current_bank == self.next_bank)  -- button press was the same as loaded bank
		local empty= (self.bank[self.next_bank] == nil) -- next bank is empty
		local last_empty = (last_bank == nil) -- current bank is full
		
		local recording = (self.recording) -- currently recording
		local armed = (self.armed) -- currently armed

		local c = self.clip_grid:index_to_grid(self.current_bank)
		local l = self.clip_grid:index_to_grid(last)
		local n = self.clip_grid:index_to_grid(self.next_bank)

		if data.state then
			print('current: ' .. self.current_bank .. ', next: ' .. self.next_bank )
			if not armed and not recording then
				print('1 STATE: not armed and not recording')
				if empty then
					print('pad was empty')
					self.armed = 'record'
					
					if App.alt then
					   self.armed = 'bounce'
					   App.alt_pad:reset()
					 else
					   
					 end
					print('arm record')
				elseif not same then
					print('pad has bank')
					-- assumes we're just playing
					self.armed = 'load'
					print('arm load')
					
					if App.alt then
					  self.armed = 'overdub'
					  App.alt_pad:reset()
					end
				else
					print('clear')
				  if App.alt then
				    self.armed = 'overdub'
				    App.alt_pad:reset()
				  else
					  self.armed = 'cancel'
					end
				end

			elseif armed and not recording	then
				print('2 STATE: armed and not recording')
        
        	if App.alt then
					  if empty then
					    self.armed = 'bounce'
					    App.alt_pad:reset()
					  else
					    self.armed='overdub'
					  end
				  
				    App.alt_pad:reset()
			
				elseif same then
					print('same cancel arm')
					-- cancel arm
					
					self.armed = false
					

				elseif self.current_bank == 0 then
					self:clear()
					self.armed = false
				elseif not same and empty then
					print('not same and empty')
					-- arm record for new pad
					self.armed = 'record'
					
					print('arm record')

				else
					-- arm load
					self.armed = 'load'
					print('arm load')
				end
			elseif not armed and recording then
				print('3 STATE: not armed and recording')
				if same then
					print('same')
					-- arm save
					if App.alt then
					  self:clear()
					  self.recording = false
					  self.bank[self.current_bank] = nil
					  App.alt_pad:reset()
				  end
					self.armed = 'save'
					print('arm save')
				elseif not same and empty then
					self.armed = {'save','record'}
				  if App.alt then
				    self.armed ={'save','bounce'}
				    App.alt_pad:reset()
				  end
				else
					print('not (not same and empty)')
					self.armed = {'save','load'}
					print('arm save then load')
			       if App.alt then
				    self.armed ={'save','overdub'}
				    App.alt_pad:reset()
				  end
				end
			end

			if not App.playing then
				self.current_bank = index
			end
		
			self:set_clip_grid()

		end

		grid:refresh()
	end
end


-- Reset the sequencer values
function Seq:clear()
	self.value = {}
	self.next_bank = 0
end

-- Returns a table of values for a specified step
function Seq:get_step(step, div)
	div = div or 1
	local step_value = {}
	local value = {}
	if type(self.value) == 'table' then
		for i,v in ipairs(self.value) do
			
			if (math.ceil(v.tick / div) - 1) % self.length + 1 == step then

				step_value[ v.type .. '-' .. v.note] = v
				
			end
		end

		for i,v in pairs(step_value) do
			value[#value + 1] = v
		end
	end
	return value
end



return Seq