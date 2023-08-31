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
	
	o.current_bank = o.current_bank or 1
	o.next_bank = o.next_bank or 0
	o.last_bank = o.last_bank or 0
	
	o.length = o.length or 96 -- in ticks, 96 = 24 ppqn x 4
	o.buffer_length = o.length or 96

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
	
	for i = (step - 1) * div + 1, step * div do
		if self.value[i] then
			for n,event in pairs(self.value[i]) do
				for _,e in pairs(event)do
					value[#value + 1] = e
				end
			end
		end
	end
	

	return value
end

function Seq:calculate_swing(tick)
	local swing = App.swing
	local swing_div = App.swing_div
	local set  = 2 * swing_div
	local tick_time = 1 / App.ppqn
	local odd =  set * swing / swing_div-- Scaling factor for first subdivision of set
	local even = set * (1 - swing) / swing_div -- Scaling factor for first subdivision of set
	local step = (tick - 1) % set + 1 -- tick order within set
	local set_order = math.ceil(tick / set) -- current set's order

	if step <= swing_div then
		-- tick is an odd subdivision
		local t = (step - 1) * odd
		local offset = t % 1 / App.ppqn 
		tick = math.floor(t) + 1 + (set_order - 1) * set
		return {tick = tick, offset = offset}
	else
		-- tick is an even subdivision
		local t = (step - swing_div - 1) * even + (odd * swing_div)
		local offset = t % 1 / App.ppqn 
		tick = math.floor(t) + 1 + (set_order - 1) * set
		return {tick = tick, offset = offset}
	end

	
	
end

function Seq:print_values(target_note)
	for i = 1, self.length do
		if self.value[i] then
			for note,n in pairs(self.value[i]) do
				if target_note == note or target_note == nil then
					for event,e in pairs(n) do
						print(i .. ' ' .. note .. ' ' .. e.type)
					end
				end
			end
		end
	end
end

--unquantized	|-o--x-|o--x--|---o--|-x--ox|-o-x-ox|o--x-o|-x--o-|x-----|------|--ox--|--o---|---x--|ox-ox-|-----o|-----x|
--				  s		s		  s		  s   s   d  s    d     s				   s      s           s  d        s
--quantized 	|o--x--|o--x--|o---x-|ox----|o-x----|o--x--|o-x---|------|------|ox----|o-----|x-----|ox----|o-----|x-----|
 
-- Reduces seq value to unique events per step
-- This will slow down a running sequence for large tables
function Seq:quantize(div)
	local note_on = {}
	local reduced = {}
	local note_on = {}
	local length = math.ceil(self.length/div)
	
	for step = 1, length do
		
		local tick = (step-1) * div + 1
		local value = self:get_step(step, div)
		local step_on = {}

		for i,v in pairs(value)do
			-- for each step get the first on note
			if v.type == 'note_on' and not step_on[v.note] then

				--and save the new tick location and the old tick location in the note_on array
				note_on[v.note] = { old = {tick = v.tick, offset = v.offset}, new = self:calculate_swing(tick)}

				local new_tick = note_on[v.note].new.tick

				-- set values
				local new_value = {}
				for prop,val in pairs(v) do
					 new_value[prop] = val -- copy tables to prevent wierdness
				end
				
				new_value.tick =  note_on[v.note].new.tick
				new_value.offset =  note_on[v.note].new.offset

				--check to make sure the reduced stuff exists
				if reduced[new_tick]  == nil then
					reduced[new_tick] = {}
				end

				if reduced[new_tick][v.note] == nil then
					reduced[new_tick][v.note] = {}
				end

				reduced[new_tick][v.note]['note_on'] = new_value
				step_on[v.note] = true
				
			elseif v.type == 'note_off' and note_on[v.note] and note_on[v.note].off == nil then
				-- new_tick + current_tick - old_tick
				local duration = v.tick - note_on[v.note].old.tick
				local new = self:calculate_swing(note_on[v.note].new.tick + duration)
				
				-- set values
				local new_value = {}
				for prop,val in pairs(v) do
					 new_value[prop] = val -- copy tables to prevent wierdness
				end
				
				new_value.tick =  new.tick
				new_value.offset =  new.offset

				--check to make sure the reduced stuff exists
				if reduced[new.tick]  == nil then
					reduced[new.tick] = {}
				end

				if reduced[new.tick][v.note] == nil then
					reduced[new.tick][v.note] = {}
				end

				reduced[new.tick][v.note]['note_off'] = new_value
				reduced[note_on[v.note].new.tick][v.note]['note_on'].duration = duration

				note_on[v.note].off = new.tick
			end 

		end -- end value loop
	end -- end step loop

	self.value = reduced
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
function Seq:save_bank(id, save_current)
	if not save_current then
		self.value = self.buffer
	end

	if not self.overdub  not save_current then
		self.length = self.buffer_length
		self.step = self.length
	end
	

	self.recording = false
	self.overdub = false
	self.bounce = false
	
	self.bank[id] = {value = self.value, length = self.length}
	print('Save bank ' .. id .. ' on track ' .. self.track.id)
end

-- Load bank to values
function Seq:load_bank(id)
	local bank = self.bank[id] or { value = {}, length = self.quantize_step }
	self.value = bank.value
	self.length = bank.length
	self.step = bank.length
	self.tick = 0
	print('Load bank ' .. id .. ' on track ' .. self.track.id)
end

-- start recording incoming Midi into Seq
function Seq:record()
	self.recording = true
	
	-- recording a new clip in empty bank
	if not self.overdub and not self.bounce then
		self.tick = 0
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
		self.bounce_start = self.tick
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
				  
				  if c.enabled then
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
		else
			print('next_step', next_step)
			print('last_step', last_step)
			print('tick', self.tick)
			print('length', self.length)
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
	local tick = event.tick or self.tick
	local step = (tick - 1) % self.buffer_length + 1


	
	if self.bounce and tick == self.tick then
		step = (tick - self.bounce_start - 1) % self.buffer_length + 1
	end

	for prop,v in pairs(event) do
		val[prop] = v -- copy tables to prevent wierdness
	end
	
	val.enabled = true
	val.tick = tick

	if self.bounce and tick == self.tick then
		val.tick = tick - self.bounce_start
	end

	val.offset = math.floor((clock.get_beats() - App.last_time) * 100) / 100
	
	if self.buffer[step] == nil then
		self.buffer[step] = {}
	end

	if self.buffer[step][val.note] == nil then
		self.buffer[step][val.note] = {}
	end
	
	self.buffer[step][val.note][val.type] = val

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
		
		 if App.alt then
	        self.follow = not self.follow
	        App.alt_pad:reset()
	    else
		    self.page = self.page + 1
		    print('page: ' .. self.page)
		 end
	    
	end

	if data.state and data.type == 'left' and self.page > 1 then
		  if App.alt then
	        self.page = 1
	        App.alt_pad:reset()
	    else
		    self.page = self.page - 1
		  end
		  	print('page: ' .. self.page)
	end



	if data.state and data.type == 'down' then
		 if App.alt then
	        if self.div > 3 then
	        	self.div = self.div / 2
	        elseif self.div > 2 then
           		self.div = self.div - 1
	        end
			page_count = math.ceil( math.ceil(self.length/self.div) / wrap)
			if self.page > page_count then self.page = page_count end
	    elseif grid.display_end.y > grid.grid_end.y and grid.display_start.y > 1 then
    			grid.display_start.y = grid.display_start.y - 1
    			grid.display_end.y = grid.display_end.y - 1
		  end
	end

	if data.state and data.type == 'up' then
		if App.alt then
	        if self.div < 24 and self.div > 2 then
	          self.div = self.div * 2
	        elseif self.div > 1  and self.div < 24 then
            self.div = self.div + 1
	        end
			page_count = math.ceil( math.ceil(self.length/self.div) / wrap)
			if self.page > page_count then self.page = page_count end
		elseif grid.display_start.y < grid.grid_start.y then	
			grid.display_start.y = grid.display_start.y + 1
			grid.display_end.y = grid.display_end.y + 1
		end
	end
	if data.state and data.type == 'pad' then
		
		local s = data.x + (self.page - 1) * wrap
		local note = data.y - 1
		
		local on_tick = (s - 1) * self.div + 1
		local off_tick = on_tick + math.floor(self.div/2)
		local on_swing = self:calculate_swing(on_tick)
		local off_swing = self:calculate_swing(off_tick)
		
		local step = self:get_step(s, self.div)
		local empty_step = true
		local step_on = false
		local step_off = false

		for i,v in pairs(step) do
			if v.note == note then
				v.enabled = not v.enabled
				if v.type == 'note_on' then
					empty_step = false
					step_on = true
				elseif v.type == 'note_off' then
					empty_step = false
					step_off = true
				end
			end
		end

		if not empty_step then
			for i,v in ipairs(step) do
				print(step_on, step_off)
				tab.print(v)
			end
		end
		
		if empty_step then
			local on = {
				type = 'note_on',
				note = note,
				tick = on_swing.tick,
				vel = 100,
				offset = on_swing.offset,
				ch = self.track.midi_in,
				enabled = true
			}

			local off = {
				type = 'note_off',
				note = note,
				tick = off_swing.tick,
				vel = 100,
				offset = off_swing.offset,
				ch = self.track.midi_in,
				enabled = true
			}
			
			if self.value == nil then
				self.value = {}
			end

			if self.value[on.tick]  == nil then
				self.value[on.tick] = {}
			end

			if self.value[on.tick][on.note] == nil then
				self.value[on.tick][on.note] = {}
			end
			
			self.value[on.tick][on.note][on.type] = on
			
			if self.value[off.tick]  == nil then
				self.value[off.tick] = {}
			end

			if self.value[off.tick][off.note] == nil then
				self.value[off.tick][off.note] = {}
			end

			self.value[off.tick][off.note][off.type] = off

			
		end
	end
	self:set_seq_grid()
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
		
		for  s = (self.page - 1) * wrap + 1, self.page * wrap do
		  
			local x = (s-1) % wrap + 1
			
			-- draw playhead
			for y = grid.display_start.y, grid.display_end.y do
				if s == current_step then
					grid.led[x][y] = {5,5,5}
				else
					grid.led[x][y] = 0
				end
			end
			
			local step = self:get_step(s,self.div)
		
			for i,v in ipairs(step) do
				if v.type == 'note_on' then
					local page = math.ceil( math.ceil(v.tick/self.div) / wrap)
					local x = math.ceil(v.tick / self.div) - (page - 1) * wrap
					local y = v.note + 1
					local is_current = current_step == math.ceil(v.tick/self.div)

					if  is_current and v.enabled then
						grid.led[x][y] = Grid.rainbow_on[v.note % 16 + 1]
					elseif v.enabled then
						grid.led[x][y] = Grid.rainbow_off[v.note % 16 + 1]
					elseif is_current then
						grid.led[x][y] = {5,5,5}
					else
						grid.led[x][y] = 0
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
					s.led[x][y] = {4,true}
				end
			end
		end

	end)

	if self.clip_grid.active then
		self.clip_grid:refresh()
	end
end

function Seq:for_each(func)
	local val = {}
	for step,v in pairs(self.value) do
		for note,t in pairs(v) do
			for e,event in pairs(t) do
				val[#val + 1] = func(event)
			end
		end
	end

	return val
end

return Seq

