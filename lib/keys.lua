-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.
Keys = {}

function Keys:new (o)
    o = o or {}
    
    setmetatable(o, self)
    self.__index = self
	
	o.id = o.id or 1
    o.grid = g
    o.grid_start = o.grid_start or {x = 1, y = 8}
    o.grid_end = o.grid_end or {x = 8, y = 5}
	o.bounds = o.bounds or o.grid.get_bounds(o.grid_start,o.grid_end)
    o.select_action = 1
    o.actions = o.actions or 12
    o.action = o.action or function(value) print('Step ' .. o.step .. ' : Action ' .. value) end
    o.display = o.display or false
	o.map = {}
	
	o.map[0] = { scale_one = {x = 1, y = 7}, scale_two = {x = 1, y = 5} }
	o.map[1]
	o.map[2]
	o.map[3]
	o.map[4]
	o.map[5]
	o.map[6]
	o.map[7]
	o.map[8]
	o.map[9]
	o.map[10]
	o.map[11]
	o.map[12]
	o.map[13]
	
	
	
	
	if(o.enabled == nil) then
		o.enabled = true
	end
		
    o:set_length(o.length)
    
	return o
end



function Keys:set_grid()
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
							self.grid.led[x][y] = rainbow_on[step_value]
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

		self.grid.led[9][9] = rainbow_on[self.select_action]
		
		self.grid:redraw()
	end
end


function Keys:transport_event(data)
	if self.display then
		self:set_grid()
	end
end


function Keys:grid_event(data)
    if self.display then
    	local x = data.x
    	local y = data.y
    	local alt = self.grid.toggled[9][1]
    
    	local index = MidiGrid.grid_to_index({x = x, y = y}, self.grid_start, self.grid_end)
    	
    	
    	if(index ~= false and data.state) then
    		
    	end
    	
    	self.grid:redraw()
    end
end

function Keys:alt_event(alt)
	local div = params:get('mode_' .. self.id .. '_div', div)
	local page_count = math.ceil(self.length / 32)
	if alt then
		self.grid:redraw()
	else
		self:set_grid()
		self.grid:redraw()
	end
end

return Seq