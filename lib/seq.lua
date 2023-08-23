local path_name = 'Foobar/lib/'
local utilities = require(path_name .. '/utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require(path_name .. 'trackcomponent')

-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.

local Seq = TrackComponent:new()
Seq.__base = TrackComponent
Seq.name = 'seq'

--Sets Seq properties on initialization
function Seq:set(o)
	self.__base.set(self, o) -- call the base set method first   
		
	o.id = o.id or 1
    
    -- instances of grids are defined in track during track initialization
    -- consider offloading grid implementations to sub-classes?
	o.clip_grid = o.clip_grid
	o.seq_grid = o.seq_grid

    
    
    o.value = o.value or {} -- holds active sequence of events
    o.buffer = o.buffer or {} -- holds recorded sequence of events
    o.bank = o.bank or {} -- stores value tables for reloading
	
	o.current_bank = o.current_bank or 0
	o.next_bank = o.next_bank or 0
	o.last_bank = o.last_bank or 0
	
	o.length = o.length or 96 -- in ticks, 96 = 24 ppqn x 4
    
    o.arm_time = 0
    o.tick = o.tick or 0 
    o.step = o.step or o.length
	o.quantize_step = o.quantize_step or 96
    o.div = o.div or 6
	
	o.follow = false
	o.page = o.page or 1
	o.current_note = o.current_note or 36
	
	o.armed	= false
	o.arm = {}
    
    
	o.on_step = o.on_step or function(s,value)  end
    
	o.note_on = {}

	if(o.enabled == nil) then
		o.enabled = true
	else
		o.enabled = false
	end

    o:load_bank(1)

	return o
end


-- BASE METHODS ---------------

-- Returns a table of values for a specified step
function Seq:get_step(step, div)
	div = div or 1
	local step_value = {}
	local value = {}
	if type(self.value) == 'table' then
		for i,v in pairs(self.value) do
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


-- Reduces seq value to unique events per step
-- This will slow down a running sequence for large tables
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


-- Reset the sequencer values
function Seq:clear(id)
	self.value = {}
	self.next_bank = 0
	
	if id and id > 0 then
	  self.bank[id] = nil
	end
end

-- Save values to bank
function Seq:save_bank(id)
	self.value = self.buffer
	
	if not self.overdub then
		self.length = self.buffer_length
		self.bounce = false
	end

	self.recording = false
	self.overdub = false

	self.bank[id] = {value = self.value, length = self.length} or {}
	print('Save bank ' .. id .. ' on track ' .. self.track.id)
end

-- Load bank to values
function Seq:load_bank(id)
	local bank = self.bank[id] or { value = {}, length = self.quantize_step }
	self.value = bank.value
	self.length = bank.length
	self.tick = 0
	print('Load bank ' .. id .. ' on track ' .. self.track.id)
end

-- start recording incoming Midi into Seq
function Seq:record()
	
	self.recording = true
	
	-- recording a new clip in empty bank
	if not self.overdub and not self.bounce then
	  self.value = {}
	  self.buffer = self.value -- this points to the same table
	  self.length = self.quantize_step
	  self.buffer_length = self.quantize_step
	
	-- recording over existing clip
	elseif self.overdub then
		self.buffer = self.value
		self.buffer_length = self.length
		
	-- bounces performance of one clip into a new bank
	elseif self.bounce then
		self.buffer = {}
		self.buffer_length = self.quantize_step
	end

	print('Recording bank ' .. self.next_bank)
end


-- EVENTS ---------------
-- Transport process chain
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
		if next_step > last_step or next_step == 1 and last_step == self.length then

			if self.enabled then 

				local current = self:get_step(next_step)
				
				local last_value = nil
				
				for i,c in pairs(current) do
					clock.run(function()
						
						if c.offset > 0 then
				    		clock.sync(c.offset)
						end
								
						-- manage note on/off
						-- if bouncing a track, record sequence to buffer if note is not muted
						if c.type == 'note_on' and  self.note_on[c.note] == nil then
							self.note_on[c.note] = c
							
							if self.recording and self.bounce and not self.track.mute.state[c.note] then
								self:record_event(c)
					    	end
					  
							self.track:send(c)	
						elseif c.type == 'note_off' and self.note_on[c.note] ~= nil then
							if self.recording and self.bounce then
								self:record_event(c)
							end
						  
							self.note_on[c.note] = nil
							self.track:send(c)	
						end
					
					end)
				end
				
				self:on_step(current)
				
				-- Handle arm events
				if self.tick % self.quantize_step == 0 then
					if self.armed then
						self:arm_event()
					elseif self.recording and not self.overdub  then
						self.buffer_length = self.buffer_length + self.quantize_step
						if not self.bounce then
							self.length = self.buffer_length
						end
					end				
				end
			end
		end
	end	

	self:set_seq_grid()

	return data
end

-- Midi process chain
function Seq:midi_event(data)
	
	if self.recording then
        -- process note_off events when a note_on occurs OR any note_on/note_off event that isn't muted
		if(data.type == 'note_off' and self.note_on[data.note] ~= nil) or not (data.note and self.track.mute.state[data.note])  then
			if (data.type == 'note_off' and self.note_on[data.note] ~= nil) then
				print('we caught:', data.note)
			end
			self:record_event(data)
		end
    
	end

	-- update note events
	if data.type == 'note_on' then
		self.note_on[data.note] = data
	elseif data.type == 'note_off' and self.note_on[data.note] ~= nil then
		self.note_on[data.note] = nil  
	end

	return data
end

-- Handle arm events
function Seq:arm_event()
	
	self.arm_time = clock.get_beats()
	
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

-- Recording step events into buffer
function Seq:record_event(event)

	local val = {}
	local step = (self.tick - 1) % self.buffer_length + 1
							
	for prop,v in pairs(event) do
		val[prop] = v -- copy tables to prevent wierdness
	end
	
	val.tick = self.tick
	val.step = step
	val.offset = clock.get_beats() - App.last_time
	
	self.buffer[#self.buffer + 1] = val
	
end



-- Sequencer grid interface --------------------------------------------------

-- Seq display
function Seq:seq_grid_event(data)
	local grid = self.seq_grid
	local wrap = 8
	local page_count = math.ceil( math.ceil(self.length/self.div) / wrap)

	--handle function pads
	if data.type ~= 'pad' then
		print(data.type ..' seq')
	end

	
	if data.state and data.type == 'right' and self.page < page_count then
		self.page = self.page + 1
	end

	if data.state and data.type == 'left' and self.page > 1 then
	    if App.alt then
	        self.follow = not follow
	        App.alt_pad:reset()
	    else
		    self.page = self.page - 1
		end
	end

	print('page: ' .. self.page)

	if data.state and data.type == 'down' then
		if grid.display_end.y > grid.grid_end.y and grid.display_start.y > 1 then
			grid.display_start.y = grid.display_start.y - 1
			grid.display_end.y = grid.display_end.y - 1
		end
	end

	if data.state and data.type == 'up' then
		if grid.display_start.y < grid.grid_start.y then	
			grid.display_start.y = grid.display_start.y + 1
			grid.display_end.y = grid.display_end.y + 1
		end
	end

	grid:refresh()
end

-- Set current value LEDs
function Seq:set_seq_grid()
	
	local grid = self.seq_grid
	local seq = self
	local wrap = 8
	local current_step = (math.ceil(self.tick/self.div) - 1) % math.ceil(self.length/self.div) + 1
	local page_count = math.ceil( math.ceil(self.length/self.div) / wrap)
    
	if grid.active then
	    
	    -- Follow playhead
        if self.follow then
            local pos = math.ceil( (self.tick % self.length) / self.div)
            local page = math.ceil(pos / wrap)
            
            --wait until playhead is one step past the display and change the page
            if pos % wrap == 1 then
                self.page = page
			end
  
        end
	    
	-- Set base pads
	
	
		grid:for_each(function(s,x,y)
			local page = math.ceil( math.ceil(seq.step/seq.div) / wrap)
            
            --transport
			if x == current_step - (self.page - 1) * wrap then
				grid.led[x][y] = {5,5,5}
			else
				grid.led[x][y] = 0
			end				
		end)

		-- Set arrow pads
		if self.page  == 1 then
			App.arrow_pads.led[3][9] = 0 
		else
			App.arrow_pads.led[3][9] = 1
		end
		
		if self.page  == page_count then
			App.arrow_pads.led[4][9] = 0 
		else
			App.arrow_pads.led[4][9] = 1
		end

		if grid.display_end.y == grid.grid_end.y then
			App.arrow_pads.led[2][9] = 0 
		else
			App.arrow_pads.led[2][9] = 1
		end
		
		if grid.display_start.y == grid.grid_start.y then
			App.arrow_pads.led[1][9] = 0 
		else
			App.arrow_pads.led[1][9] = 1
		end

		App.arrow_pads:refresh() -- reminder that arrow pads are a shared grid and need to be refreshed separately
	
        -- place notes from value on grid
		for i,v in ipairs(self.value) do
			if v.type == 'note_on' then
				local page = math.ceil( math.ceil(v.step/self.div) / wrap)
			
				if self.page == page then 
					local x = math.ceil(v.step / self.div) - (page - 1) * wrap
					local y = v.note + 1
					
					if current_step == math.ceil(v.step/self.div) then
					  grid.led[x][y] = Grid.rainbow_on[v.note % 16 + 1]
					else
					  grid.led[x][y] = Grid.rainbow_off[v.note % 16 + 1]
					end
				end
			end
		end


		grid:refresh()
	end
end


-- CLIP GRID ---------------------------------------------------------------------------------------------------------
-- Provides a grid with state machine logic to control the launching and recording of clips.
-- By default, actions are armed when playing to execute during a quantized step.
-- Record: Empty clips will start recording when pressed. Length is set by when the next quantized step is pressed
-- Bounce: Alt + Empty will keep the current sequence but record into the new bank.
-- Overdub: Alt + Recorded bank will record over existing steps
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
					  self:clear(self.current_bank)
					  self.recording = false
					  App.alt_pad:reset()
				  end
					self.armed = 'save'
					print('arm save')
				elseif not same and empty then
					self.armed = {'save','record'}
				  if App.alt then
				    self.armed = {'save','bounce'}
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

			if not App.playing and self.armed ~= 'record' and self.armed ~= 'bounce' then
				self:arm_event()
			end
		
			self:set_clip_grid()

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
			s.led[x][y] = {5,5,5}
		end

		if i == self.current_bank then
			if self.recording then
				s.led[x][y] = {3,true}
			elseif (self.bank[i]) then
				s.led[x][y] = Grid.rainbow_on[i]
			else
				s.led[x][y] = {5,5,5}
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
				if action == 'load' then
					s.led[x][y] = {3,true}
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




return Seq

