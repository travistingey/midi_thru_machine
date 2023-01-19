-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.

Seq = {}

function Seq:new (o)
    o = o or {}
    
    setmetatable(o, self)
    self.__index = self

    o.grid = o.grid
    o.grid_start = o.grid_start or {x = 1, y = 8}
    o.grid_end = o.grid_end or {x = 8, y = 5}
	o.bounds = o.grid.get_bounds(o.grid_start,o.grid_end)
    o.div = o.div or 12
    o.select_step = 1
    o.select_action = 1
    o.map = {}
    o.value = o.value or {}
    o.length = o.length or 32
    o.tick = 1
    o.step = 1
	o.page = 1
    o.actions = o.actions or 16
    o.action = o.action or function(value) print('Step ' .. o.step .. ' : Action ' .. value) end
    o.display = o.display or false
	
    o:set_length(o.length)
    
	return o
end



function Seq:set_grid()
	if self.display then
		local wrap = self.bounds.width * self.bounds.height
		local page_count = math.ceil(self.length/wrap)
		
        for x = math.min(self.grid_start.x,self.grid_end.x), math.max(self.grid_start.x,self.grid_end.x) do
            for y = math.min(self.grid_start.y,self.grid_end.y), math.max(self.grid_start.y,self.grid_end.y) do
				self.grid.led[x][y] = 0
			end
		end
		for i = 1, #self.map do
			local page = math.ceil(i/wrap)

			if page == self.page then
				local x = self.map[i].x
				local y = self.map[i].y

				if i > self.length then
					self.grid.led[x][y] = 0 -- No steps / pattern is short	
				else
					local step_value = self.value[i]
					
					if step_value and step_value > 0 then
						if i == self.step then
							self.grid.led[x][y] = 1
						else
							self.grid.led[x][y] = rainbow_off[step_value]
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

		self.grid.led[9][9] = rainbow_off[self.select_action]
		
		self.grid:redraw()
	end
end


function Seq:set_length(length)
	local wrap = self.bounds.height * self.bounds.width
	for i = 1, length do
		self.map[i] = self.grid.index_to_grid(util.wrap(i,1,wrap), self.grid_start, self.grid_end)
		self.map[i].page = math.ceil(i/wrap)
	end
	self.length = length
end


function Seq:transport_event(data)
	-- Tick based sequencer running on 16th notes at 24 PPQN
	if data.type == 'clock' then
		
		self.tick = util.wrap(self.tick + 1, 1, self.div * self.length)

		local next_step = util.wrap(math.floor(self.tick / self.div) + 1, 1, self.length)
		local last_step = self.step

		local bounds = self.grid.get_bounds(self.grid_start,self.grid_end)
		local wrap = bounds.height * bounds.width
		local step_page = math.ceil(next_step/wrap)
		
		self.step = next_step

		-- Enter new step. c = current step, l = last step
		if next_step > last_step or next_step == 1 and last_step == self.length then

			local l = self.map[last_step]
			local c = self.map[next_step]

			local last_value = self.value[last_step] or 0
			local value = self.value[next_step] or 0
			
			if value > 0 then 
			    self.action(value)
			end
			
			if self.display then
				self:set_grid()
        		--[[if step_page == l.page then
					
        			if  last_value == 0 then
						self.grid.led[l.x][l.y] = {5,5,5}
					else
						self.grid.led[l.x][l.y] = rainbow_off[last_value]
					end
				else
					
					self.grid.led[l.x][l.y] = 100
					
        		end
        
        		if value == 0 and step_page == self.page then
        			self.grid.led[c.x][c.y] = 1
        		elseif step_page == self.page then
        			self.grid.led[c.x][c.y] = rainbow_on[value]
        		end]]
			end
		end
	end

	-- Note: 'Start' is called at the beginning of the sequence
	if data.type == 'start' then
		self.tick = 0
		self.step = self.length
	end
	
end


function Seq:grid_event(data)
    if self.display then
    	local x = data.x
    	local y = data.y
    	local alt = self.grid.toggled[9][1]
    
    	local index = MidiGrid.grid_to_index({x = x, y = y}, self.grid_start, self.grid_end)
    	
    	if(x == 1 and y == 9 and data.state) then
    		-- up
    		self.select_action = util.wrap(self.select_action + 1, 1, self.actions)
    		self.grid.led[9][9] = rainbow_off[self.select_action]
    		self.grid:redraw()
    	end
    	
    	if(x == 2 and y == 9 and data.state) then
    		-- down
    		self.select_action = util.wrap(self.select_action - 1, 1, self.actions)
    		self.grid.led[9][9] = rainbow_off[self.select_action]
    		self.grid:redraw()
    	end
    	
    	if(x == 3 and y == 9 and data.state) then
    		-- left
    		
    		if alt and self.length > 32 then
    			print('Remove Page')
    		    self:set_length (self.length - 32)
    			self.grid.toggled[9][1] = false
    			self.grid.led[9][1] = 0
    		else
    		    local wrap = self.bounds.height * self.bounds.width 
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
    					self.value[previous_length + i] = self.value[i]
    				end
    			end
    			self.grid.toggled[9][1] = false
    			self.grid.led[9][1] = 0
    		else
    			local wrap = self.bounds.height * self.bounds.width 
    			self.page = util.clamp(self.page + 1, 1, math.ceil(self.length/wrap) )
    		end
    		self:set_grid()
    	end
    
    	if(index ~= false and data.state) then
    		index = index + (self.page - 1) * (self.bounds.height * self.bounds.width)
    		local value = self.value[index] or 0
    		
    		if (alt) then
    		    print('length increased')
    		    self:set_length(index)
                self:set_grid()
    			self.grid.toggled[9][1] = false
    			self.grid.led[9][1] = 0
    		elseif  index <= self.length then
    		
            	if value == 0 then
            		-- Turn on
            		self.note_select = index
            		self.value[index] = self.select_action
            		self.grid.led[x][y] = rainbow_off[self.select_action]
            		self.select_step = index
            		self.grid:redraw()
            	else
            		-- Turn off
            		self.value[index] = 0
            		self.select_step = index
            		self.grid.led[x][y] = {5,5,5}
            	end
            	
            	if alt then
            	    
            	end
            end
    	end
    	
    	self.grid:redraw()
    end
end

return Seq