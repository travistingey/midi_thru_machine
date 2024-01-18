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
		
	self.playing = false

	o.on_step = o.on_step or function(s,value)  end
		
	o.note_on = {}

	if(o.enabled == nil) then
		o.enabled = true
	else
		o.enabled = false
	end

	-- o:load_bank(1)

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
--				  s		s		  s		  s   s   d  s	d	 s				   s	  s		   s  d		s
--quantized 	|o--x--|o--x--|o---x-|ox----|o-x----|o--x--|o-x---|------|------|ox----|o-----|x-----|ox----|o-----|x-----|
 
-- Reduces seq value to unique events per step
-- This will slow down a running sequence for large tables
function Seq:quantize(div)
	local note_on = {}
	local reduced = {}
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
	self.playing = false
	self.value = {}
	self.current_bank = 0
	self.next_bank = 0
	
	if id and id > 0 then
	  self.bank[id] = nil
	end
end

-- Save values to bank
function Seq:save_bank(id, save_current)
	local track = track

	self.playing = true
	for note,event in pairs(self.track.note_on) do
		local off = {
			note = event.note,
			type = 'note_off',
			vel = event.vel,
			ch = track.midi_out,
		}

		track:hande_note(off, 'send')
		self:record_event(off)
	end

	if not save_current then
		self.value = self.buffer
	end

	if not self.overdub  and not save_current then
		self.length = self.buffer_length
		self.step = self.length
	end

	self.recording = false
	self.overdub = false
	self.bounce = false
	
	self.bank[id] = {value = self.value, length = self.length}

	if self.on_save ~= nil then
		-- self.page = 1
		self:on_save()
	end
end

-- Load bank to values
function Seq:load_bank(id)
	self.playing = true
	local bank = self.bank[id] or { value = {}, length = self.quantize_step }
	self.value = bank.value
	self.page = 1
	self.length = bank.length
	self.step = bank.length
	self.tick = 0
	
	
	-- TODO: Tie this into seq_grid, then remove page assignment above
	if self.on_load ~= nil then
		-- self.page = 1
		self:on_load()
	end
end

-- start recording incoming Midi into Seq
function Seq:record()
	self.recording = true
	self.playing = false
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
		self.playing = true
		self.bounce_start = self.tick
		self.buffer = {}
		self.buffer_length = self.quantize_step
	end

	if self.on_record ~= nil then
		self:on_record()
	end
end


------------------------

-- MAIN EVENTS

-------------------------
-- Transport process chain
function Seq:transport_event(data, track)
	-- Tick based sequencer
	print('wjat')
	if data.type == 'start' then

		self.tick = 0
		self.step = self.length
		
		if self.armed then
			self:arm_event()
		end
	elseif data.type == 'stop' then

		for i,c in pairs(track.note_on) do
			-- send off
			local off = {
				type = 'note_off',
				note = c.note,
				vel = c.vel,
				ch = c.ch
			}

			track:handle_note(off,'send')
			track:send(off)

			if self.recording then
				self:record_event(off)
			end
		end
		
		if self.recording then
			self:save_bank(self.current_bank)
			self:load_bank(self.current_bank)
		end

		self.recording = false
		self.armed = false
		
	elseif data.type == 'clock' then
		print(self.tick)
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
							if c.type == 'note_on' and  track.note_on[c.note] == nil then

								if self.recording and self.bounce and not track.mute.state[c.note] then
									self:record_event(c)
								end

								track:handle_note(c,'send')
								track:send(c)	

							elseif c.type == 'note_off' and track.note_on[c.note] ~= nil then
								if self.recording and self.bounce then
									self:record_event(c)
								end
								
								track:handle_note(c,'send')
								track:send(c)	
							end
						end)
					end
				end
				
				self:on_step(current)
				print(self.tick,self.quantize_step)
				-- Handle arm events
				if self.tick % self.quantize_step == 0 then
					print('step')
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
 
	if self.seq_grid ~= nil then
		self:seq_set_grid()
	end

	if self.on_transport ~= nil then
		self:on_transport(data)
	end

	return data
end


-- Midi process chain
function Seq:midi_event(data, track)
	if self.recording then
		-- process note_off events when a note_on occurs OR any note_on/note_off event that isn't muted 
		
		if track.triggered then
			if not track.mute.state[track.trigger] or (data.type == 'note_off' and track.note_on[data.note] ~= nil)  then
				if self.bounce and track.midi_thru then
					self:record_event(data)
				elseif not self.bounce then
					self:record_event(data)
				end
			end
		elseif(data.type == 'note_off' and track.note_on[data.note] ~= nil) or not (data.note and track.mute.state[data.note])  then
			self:record_event(data)
		end
		
	end
 
 
	if not self.playing or track.midi_thru then
		return data
	end
end

-- Handle arm events
function Seq:arm_event()
	
	self.arm_time = clock.get_beats()

	local actions = {}
	local save_current = false

	if self.armed then
		if type(self.armed) == 'table' then
			actions = self.armed
			if actions[1] == 'save' then
				save_current = true
			end
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
			if save_current then
				self:save_bank(self.current_bank)
			else
				self:save_bank(self.next_bank)
			end
		elseif action == 'load' then
			self:load_bank(self.next_bank)
			
		elseif action == 'clear' then
			self:clear()
		end
	end
	
	self.current_bank = self.next_bank
	self.next_bank = 0

	self.armed = false
	
	if self.on_arm ~= nil then
	  self:on_arm()
	end
end

-- Recording step events into buffer
function Seq:record_event(event)
	
	local val = {}
	local tick = self.tick
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

	-- Record
	if val.note then
		if self.buffer[step][val.note] == nil then
			self.buffer[step][val.note] = {}
		end
	
		self.buffer[step][val.note][val.type] = val
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

