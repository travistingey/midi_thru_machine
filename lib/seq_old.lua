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
    o.div = o.div or 12
    o.select_step = 1
    o.select_action = 1
	o.type = o.type or 1
    o.map = o.map or {}
    o.bank = o.bank or 1
    o.value = o.value or {}
    o.length = o.length or 32
    o.tick = o.tick or 0
    o.step = o.step or 1
	o.page = o.page or 1
    o.actions = o.actions or 16
    o.action = o.action or function(value)  end
    o.display = o.display or false
	o.on_grid = o.on_grid
	o.on_transport = o.on_transport
	o.on_midi = o.on_midi
	o.data = o.data or {}
	
	
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

function Seq:set_grid()
	if self.display then
		local wrap = self.grid.bounds.width * self.grid.bounds.height
		local page_count = math.ceil(self.length/wrap)
		
		self.grid:for_each(function(s,x,y) s.led[x][y] = 0 end)

		for i = 1, #self.map do
			local page = math.ceil(i/wrap)

			if page == self.page then
				local x = self.map[i].x
				local y = self.map[i].y

				if i > self.length then
					self.grid.led[x][y] = 0 -- No steps / pattern is short	
				else
					local step_value = self.value[self.bank][i]
					
					if step_value and step_value > 0 then
						if i == self.step then
							self.grid.led[x][y] = MidiGrid.rainbow_on[step_value]
						else
							self.grid.led[x][y] = MidiGrid.rainbow_off[step_value]
						end
					else
						if i == self.step then
							self.grid.led[x][y] = 1
						else
							self.grid.led[x][y] = {5,5,5} -- empty step
						end
						
					end 
				end   
			end
		end

		if( not self.grid.toggled[9][1]) then
			self.grid.led[1][9] = {20,20,20}
			self.grid.led[2][9] = {20,20,20}
			
			if self.page > 1 then
				self.grid.led[3][9] = {20,20,20}
			else
				self.grid.led[3][9] = 0
			end

			if self.page < page_count then
				self.grid.led[4][9] = {20,20,20}
			else
				self.grid.led[4][9] = 0
			end
		end

		self.grid.led[9][9] = MidiGrid.rainbow_on[util.wrap(self.select_action,1,#MidiGrid.rainbow_on)]
		
		self.grid:redraw()
	end
end


function Seq:set_length(length)
	local wrap = self.grid.bounds.height * self.grid.bounds.width
	for i = 1, length do
		self.map[i] = self.grid.index_to_grid(util.wrap(i,1,wrap), self.grid.grid_start, self.grid.grid_end)
		self.map[i].page = math.ceil(i/wrap)
	end
	params:set('mode_' .. self.id .. '_length',length)
	self.length = length
end


function Seq:transport_event(data)
	-- Tick based sequencer running on 16th notes at 24 PPQN
	if data.type == 'clock' then
		
		self.tick = util.wrap(self.tick + 1, 0, self.div * self.length - 1)

		local next_step = util.wrap(math.floor(self.tick / self.div) + 1, 1, self.length)
		local last_step = self.step

		local bounds = self.grid.get_bounds(self.grid.grid_start,self.grid.grid_end)
		local wrap = bounds.height * bounds.width
		local step_page = math.ceil(next_step/wrap)
		
		self.step = next_step

		-- Enter new step. c = current step, l = last step
		if next_step > last_step or next_step == 1 and last_step == self.length then

			local l = self.map[last_step]
			local c = self.map[next_step]

			local last_value = self.value[self.bank][last_step] or 0
			local value = self.value[self.bank][next_step] or 0
			
			if self.enabled then 
			    self:action(value)
			end
			
			if self.display then
				self:set_grid()
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

function Seq:grid_event(data)
    if self.display then
    	local x = data.x
    	local y = data.y
    	local alt = self.grid.toggled[9][1]
    
    	local index = MidiGrid.grid_to_index({x = x, y = y}, self.grid.grid_start, self.grid.grid_end)
    	
    	if(x == 1 and y == 9 and data.state) then
    		-- up
			if alt then
				local div = params:get('mode_' .. self.id .. '_div',div) - 1
				if div < 1 then 
					return false
				end
				print('Increased resolution of Mode ' .. self.id)
				params:set('mode_' .. self.id .. '_div',div)

				local length = self.length * 2
				local old_value = self.value[self.bank]
				local new_value = {}
				
				for i=1, length do
					if math.fmod(i,2) == 1 then
					new_value[#new_value + 1] = old_value[math.ceil(i/2)]
					else
					new_value[#new_value + 1] = 0
					end
				end
				
				self.value[self.bank] = new_value
				self:set_length(length)

				App:set_alt(false)
				
				self:set_grid()			  
			else
				self.select_action = util.wrap(self.select_action + 1, 1, self.actions)
				self.grid.led[9][9] = MidiGrid.rainbow_on[self.select_action]
				self.grid:redraw()
			end
    	end
    	
    	if(x == 2 and y == 9 and data.state) then
    		-- down

			if alt then
				local div =  params:get('mode_' .. self.id .. '_div',div) + 1

				if div > 10 then 
					return false
				end
				print('Decreased resolution of Mode ' .. self.id)
				params:set('mode_' .. self.id .. '_div',div)

				self.div = 3 * 2^(div)
				local length = math.ceil(self.length / 2)
				
				local old_value = self.value[self.bank]
				local new_value = {}
				
				for i=1, length do
					local index = 2 * i - 1
					new_value[i] = old_value[index]
				
				end
				
				self.value[self.bank] = new_value
				self:set_length(length)

				App:set_alt(false)
				
				self:set_grid()	
			else
				self.select_action = util.wrap(self.select_action - 1, 1, self.actions)
				self.grid.led[9][9] = MidiGrid.rainbow_on[self.select_action]
				self.grid:redraw()
			end
    	end
    	
    	if(x == 3 and y == 9 and data.state) then
    		-- left
    		
    		if alt and self.length > 32 then
    			print('Remove Page')
    		    self:set_length (self.length - 32)
    			App:set_alt(false)
    		else
    		    local wrap = self.grid.bounds.height * self.grid.bounds.width 
    		    self.page = util.clamp(self.page - 1, 1, math.ceil(self.length/wrap) )
    		end
    		self:set_grid()
    	elseif(x == 4 and y == 9 and data.state) then
    		-- right
    		if alt and self.length < 127 then
    			print('Add Page') -- first fill out the first page and then copy pages thereafter 
    			if(self.length < 32) then 
    				self:set_length(32) 
    			else
    				local previous_length = self.length
    				self:set_length(math.ceil(self.length/32) * 32 + 32)
    				for i = 1, 32 do
    					self.value[self.bank][previous_length + i] = self.value[self.bank][i]
    				end
    			end
    			App:set_alt(false)
    		else
    			local wrap = self.grid.bounds.height * self.grid.bounds.width 
    			self.page = util.clamp(self.page + 1, 1, math.ceil(self.length/wrap) )
    		end
    		self:set_grid()
    	end
    
    	if(index ~= false and data.state) then
    		index = index + (self.page - 1) * (self.grid.bounds.height * self.grid.bounds.width)
    		local value = self.value[self.bank][index] or 0
    		
    		if (alt) then
    		    self:set_length(index)
                self:set_grid()
    			App:set_alt(false)
    		elseif  index <= self.length then
    		
            	if self.value[self.bank][index] ~= self.select_action then
            		-- Turn on
            		self.note_select = index
            		self.value[self.bank][index] = self.select_action
            		self.grid.led[x][y] = MidiGrid.rainbow_off[self.select_action]
            		self.select_step = index
				else
            		-- Turn off
            		self.value[self.bank][index] = 0
            		self.select_step = index
            		self.grid.led[x][y] = {5,5,5}
            	end

            end
    	end
    	
    	self.grid:redraw()
    end
end

function Seq:alt_event(alt)
	local div = params:get('mode_' .. self.id .. '_div', div)
	local page_count = math.ceil(self.length / 32)
	if alt then
		if div == 1 then
			self.grid.led[1][9] = 0
			self.grid.led[2][9] = {3,true}
		elseif div == 10 then
			self.grid.led[2][9] = 0
			self.grid.led[1][9] = {3,true}
		else
			self.grid.led[1][9] = {3,true}
			self.grid.led[2][9] = {3,true}
		end

		if page_count == 4 then
			self.grid.led[4][9] = 0
			self.grid.led[3][9] = {3,true}
		elseif page_count == 1 then
			self.grid.led[3][9] = 0
			self.grid.led[4][9] = {3,true}
		else
			self.grid.led[3][9] = {3,true}
			self.grid.led[4][9] = {3,true}
		end

		if self.on_alt ~= nil then
			self:on_alt(alt)
		end

		self.grid:redraw()
	else

		if self.on_alt ~= nil then
			self:on_alt(alt)
		end
		
		self:set_grid()
		self.grid:redraw()
	end
end

return Seq