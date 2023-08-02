local Grid = {}
local utilities = require('Foobar/lib/utilities')

Grid.rainbow_on = {{127,0,0},{127,15,0},{127,45,0},{127,100,0},{75,127,0},{40,127,0},{0,127,0},{0,127,27},{0,127,127},{0,45,127},{0,0,127},{10,0,127},{27,0,127},{55,0,127},{127,0,75},{127,0,15}}
Grid.rainbow_off = {}

-- Creating the rainbow_off table by dividing the Grid.rainbow_on values by 4
for i = 1, 16 do
	Grid.rainbow_off[i] = {math.floor(Grid.rainbow_on[i][1]/4),math.floor(Grid.rainbow_on[i][2]/4),math.floor(Grid.rainbow_on[i][3]/4)}
end


function Grid:new (o)
	o = o or {}

	setmetatable(o, self)
	self.__index = self

	o.event = o.event or function(data) end

	o.grid_start = o.grid_start or {x = 1,y = 1}
	o.grid_end = o.grid_end or {x = 9,y = 9}
	
	o.display_start = o.display_start or {x=1,y=1}
	o.display_end = o.display_end or {x=9,y=9}
	o.offset = o.offset or {x=0,y=0}

	o.bounds = {
		width = math.abs(o.grid_end.x - o.grid_start.x) + 1,
		height = math.abs(o.grid_end.y - o.grid_start.y) + 1,
		max_x = math.max(o.grid_start.x,o.grid_end.x),
		max_y = math.max(o.grid_start.y,o.grid_end.y),
		min_x = math.min(o.grid_start.x,o.grid_end.x),
		min_y = math.min(o.grid_start.y,o.grid_end.y)
	}

	if o.led == nil then
        o.led = {}
        for i = 1, o.bounds.width do
            o.led[i] = {}
        end
    end

	if o.toggled == nil then
        o.toggled = {}
        for i = 1, o.bounds.width do
            o.toggled[i] = {}
        end
    end
	
	o.subgrids = {}

	o:reset()
	return o
end

function Grid:subgrid(grid_start,grid_end,event)
	-- Create a new instance of Grid
	local subgrid = Grid:new({
		midi = self.midi,
		grid_start = grid_start, 
		grid_end = grid_end,
		led = self.led,  -- sharing the same map with parent grid
		toggled = self.toggled,      -- sharing the same toggled status with parent grid
		down = self.down             -- sharing the same down status with parent grid
	})

	event = event or function(data) end

	subgrid.event = function(s,data)
		if s:in_bounds(data) then
			event(s,data)
		end
	end

	-- Adding the newly created subgrid to the parent grid's subgrids table
	table.insert(self.subgrids, subgrid)

	-- Return the created subgrid instance
	return subgrid

end

function Grid:process (d)
	local msg = midi.to_msg(d)
	local data = {}
	local x,y

	
	if(msg.type == 'note_on' or msg.type == 'note_off' or msg.type == 'cc') then 
		if(msg.type == 'note_on' or msg.type == 'note_off') then
	
			x = math.fmod(msg.note,10)
			y =  math.floor(msg.note/10)
			
			data.state = (msg.type == 'note_on')

		elseif (msg.type == 'cc') then
			x = math.fmod(msg.cc,10)
			y =  math.floor(msg.cc/10)
			data.state = (msg.val == 127)
		end
		
		local minX = math.min(self.display_start.x,self.display_end.x)
		local minY = math.min(self.display_start.y,self.display_end.y)

		local maxX = math.max(self.display_start.x,self.display_end.x)
		local maxY = math.max(self.display_start.y,self.display_end.y)

		local gridWidth = maxX - minX + 1
		local gridHeight = maxX - minX + 1
		
		if x <= self.offset.x or y <= self.offset.y or x > gridWidth + self.offset.x or y > gridHeight + self.offset.y then
			return
		end

		data.x = x
		data.y = y
		
		
		if(x == 9 and y > 1) then
			data.type = 'row'
			data.row = ( 9 - data.y )
		elseif (x == 1 and y == 9) then data.type = 'up'
		elseif (x == 2 and y == 9) then data.type = 'down'
		elseif (x == 3 and y == 9) then data.type = 'left'
		elseif (x == 4 and y == 9) then data.type = 'right'
		elseif (x >= 5 and x <= 8 and y == 9) then
			data.type = 'mode'
			data.mode = (data.x - 4)
		elseif(x == 9 and y == 1) then
			data.type = 'alt'
		else
			data.type = 'pad'
		end
		--Set states
				
		
		
		local minX = math.min(self.display_start.x,self.display_end.x)
		local minY = math.min(self.display_start.y,self.display_end.y)

		data.x = minX + data.x - 1 - self.offset.x
		data.y = minY + data.y - 1 - self.offset.y

		if data.state then
			self.toggled[data.x][data.y] = (not self.toggled[data.x][data.y])
		end
		
		data.toggled = self.toggled[data.x][data.y]

		
		--Event Handler
		self:event(data)

		local subgrids = self.subgrids
		if #subgrids > 0 then
			for i = 1, #subgrids do
				self.subgrids[i]:event(data)
			end
		end
	end
end

function Grid:for_each(func)
	local i = 1
	for x = self.grid_start.x, self.grid_end.x do
		for y = self.grid_start.y, self.grid_end.y do
			func(self,x,y,i)
			i = i + 1
		end
	end
end

function Grid:reset()
	self:for_each(function(s,x,y)
		s.toggled[x][y] = false
		s.led[x][y] = 0
	end)
	self:refresh()
end

function Grid:set(x,y,z,offset)
	offset = offset or {x=0,y=0}
	local minX = math.min(self.display_start.x,self.display_end.x)
	local minY = math.min(self.display_start.y,self.display_end.y)

	x = x - minX + 1 + offset.x
	y = y - minY + 1 + offset.y
	
	return self:set_raw(x,y,z)
end

function Grid:set_raw(x,y,z)
	local target = math.fmod(x,10) + 10 * y
	local message = {}

	if(type(z) == 'table')then
		if #z == 3 then
			-- length of 3, RGB
			message = utilities.concat_table(message,{3,target})
			message = utilities.concat_table(message,z)    
	
		elseif z[2] == true and #z == 2  then
			-- length of 2, second value is true
			message = utilities.concat_table(message,{2,target})
			message = utilities.concat_table(message,{z[1]})
		
		elseif #z == 2 then
			-- length of 2
			message = utilities.concat_table(message,{1,target})
			message = utilities.concat_table(message,z)
			
		else
			-- length of 1 
			message = utilities.concat_table(message,{0,target})
			message = utilities.concat_table(message,z)
			
		end
	else
		-- send single value to led
		message = utilities.concat_table(message,{0,target})
		message = utilities.concat_table(message,{z})
		
	end


	return message
end

function Grid:refresh()
	local message = {240,0,32,41,2,13,3}

	local minX = math.min(self.display_start.x,self.display_end.x)
	local minY = math.min(self.display_start.y,self.display_end.y)

	local maxX = math.max(self.display_start.x,self.display_end.x)
	local maxY = math.max(self.display_start.y,self.display_end.y)

	local gridWidth = maxX - minX + 1
	local gridHeight = maxX - minX + 1

	for x = self.display_start.x, self.display_end.x do
		for y = self.display_start.y, self.display_end.y do
			
			-- for grid values
			local grid_x = x - self.display_start.x + 1 + self.offset.x
			local grid_y = y - self.display_start.y + 1 + self.offset.y

			if grid_x <= self.offset.x or grid_y <= self.offset.y or grid_x > 9 or grid_y > 9 or grid_x > gridWidth + self.offset.x or grid_y > gridHeight + self.offset.y then
				goto continue
			end

			if (self.led[x][y] == nil) then
				local m = self:set_raw(grid_x,grid_y,0)
				message = utilities.concat_table(message,m)
			else
				local m = self:set_raw(grid_x,grid_y,self.led[x][y])
				message = utilities.concat_table(message, m )
			end

			::continue::
		end
	end
	
	message = utilities.concat_table(message,{247})
	self.midi:send(message)
end

function Grid:clear()
	local message = {240,0,32,41,2,13,3}
	for x = 1, 9 do
		for y = 1, 9 do
			local m = self:set_raw(x,y,0)
			message = utilities.concat_table(message,m)
		end
	end
	
	message = utilities.concat_table(message,{247})
	self.midi:send(message)
end

function Grid:in_bounds(pos)
return ( pos.x >= self.bounds.min_x and pos.x <= self.bounds.max_x and pos.y >= self.bounds.min_y and pos.y <= self.bounds.max_y )
end

function Grid:grid_to_index(pos)
	local b = self.bounds

	if self:in_bounds(pos) then
		return math.abs(pos.y - self.grid_start.y) * b.width + math.abs(pos.x - self.grid_start.x) + 1
	else
		-- out of bounds
		return false
	end
end


function Grid:index_to_grid(index)
	local b = self.bounds
	local x,y

	if self.grid_start.x > self.grid_end.x then
		x = b.width - math.fmod(index - 1,b.width) + b.min_x - 1
	else
		x = math.fmod(index - 1,b.width) + b.min_x
	end

	if self.grid_start.y > self.grid_end.y then
		y = b.height - math.floor((index - 1)/b.width) + b.min_y - 1
	else
		y = math.floor((index - 1)/b.width) + b.min_y
	end

	if(y > b.max_y) then 
		return false
	else
		return {x=x,y=y}
	end
end

return Grid