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

	o.name = o.name or 'unnamed grid'
	o.event = o.event or function(data) end
	o.active = o.active or false
	o.grid_start = o.grid_start or {x = 1,y = 1}
	o.grid_end = o.grid_end or {x = 9,y = 9}
	
	o.display_start = o.display_start or {x=1,y=1}
	o.display_end = o.display_end or {x=9,y=9}
	o.offset = o.offset or {x=0,y=0}

	o.set = o.set or function(s) end

	local min_x = math.min(o.grid_start.x,o.grid_end.x)
	local min_y = math.min(o.grid_start.y,o.grid_end.y)

	local max_x = math.max(o.grid_start.x,o.grid_end.x)
	local max_y = math.max(o.grid_start.y,o.grid_end.y)

	local grid_width = max_x - min_x + 1
	local grid_height = max_y - min_y + 1

	o.bounds = {
		width = grid_width,
		height = grid_height,
		max_x = max_x,
		max_y = max_y,
		min_x = min_x,
		min_y = min_y
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

	-- Initialize pad hold times and long press threshold
	o.pad_hold_times = {}
	o.long_press_threshold = o.long_press_threshold or 0.3  -- Adjust threshold as needed
	o.pad_down = {}

	o:reset()
	return o
end

function Grid:update_bounds()

	self.bounds = {
		width = math.max(self.grid_start.x,self.grid_end.x) - math.min(self.grid_start.x,self.grid_end.x) + 1,
		height = math.max(self.grid_start.y,self.grid_end.y) - math.min(self.grid_start.y,self.grid_end.y) + 1,
		max_x = math.max(self.grid_start.x,self.grid_end.x),
		max_y = math.max(self.grid_start.y,self.grid_end.y),
		min_x = math.min(self.grid_start.x,self.grid_end.x),
		min_y = math.min(self.grid_start.y,self.grid_end.y)
	}

	self.display_bounds = {
		width = math.max(self.display_start.x,self.display_end.x) - math.min(self.display_start.x,self.display_end.x) + 1,
		height = math.max(self.display_start.y,self.display_end.y) - math.min(self.display_start.y,self.display_end.y) + 1,
		max_x = math.max(self.display_start.x,self.display_end.x),
		max_y = math.max(self.display_start.y,self.display_end.y),
		min_x = math.min(self.display_start.x,self.display_end.x),
		min_y = math.min(self.display_start.y,self.display_end.y)
	}

end

function Grid:up(amount)
	amount = amount or 1
	print('up')
	self:update_bounds()
	if self.display_start.y < self.bounds.max_y and self.display_end.y < self.bounds.max_y then    
		self.display_start.y = self.display_start.y + amount
		self.display_end.y = self.display_end.y + amount
	else
		print('outta bounds')
	end
end

function Grid:down(amount)
	amount = amount or 1
	print('down')
	if self.display_start.y > self.bounds.min_y and self.display_end.y > self.bounds.min_y then    
		self.display_start.y = self.display_start.y - amount
		self.display_end.y = self.display_end.y - amount
	end
end

function Grid:left(amount)
	amount = amount or 1
	print('left')
	if self.display_end.x > self.grid_end.x and self.display_start.x > 1 then
		self.display_start.x = self.display_start.x - amount
		self.display_end.x = self.display_end.x - amount
	end
end

function Grid:right(amount)
	amount = amount or 1
	print('right')
	if self.display_start.x < self.grid_start.x and self.display_end.x < self.grid_end.x then    
		self.display_start.x = self.display_start.x + amount
		self.display_end.x = self.display_end.x + amount
	end
end

function Grid:subgrid(o)
	o.name = o.name or 'unnamed grid'
	o.midi = self.midi
	o.grid_start = o.grid_start or self.grid_start
	o.grid_end = o.grid_end or self.grid_end
	o.display_start = o.display_start or o.grid_start
	o.display_end = o.display_end or o.grid_end
	o.offset = {x = o.grid_start.x - 1, y = o.grid_start.y - 1}
	o.led = self.led            -- sharing the same map with parent grid
	o.toggled = self.toggled    -- sharing the same toggled status with parent grid
	o.down = self.down          -- sharing the same down status with parent grid

	local subgrid = Grid:new(o) -- Create a new instance of Grid
	local event = o.event

	subgrid.event = function(s, data)
		s:update_bounds()
		if s:in_bounds(data) then
			event(s, data)
		end
	end

	-- Adding the newly created subgrid to the parent grid's subgrids table
	table.insert(self.subgrids, subgrid)

	subgrid.active = self.active

	-- Return the created subgrid instance
	return subgrid
end

function Grid:enable()
	self.active = true
	local subgrids = self.subgrids
	if #subgrids > 0 then
		for i = 1, #subgrids do
			self.subgrids[i].active = true
		end
	end

	if self.set_grid then
		self:set_grid()
	end
end

function Grid:disable()
	self:clear()
	self.active = false
	local subgrids = self.subgrids
	if #subgrids > 0 then
		for i = 1, #subgrids do
			self.subgrids[i].active = false
		end
	end

	if self.set_grid then
		self:set_grid()
	end
end

function Grid:process(d)
	if self.active then
		local msg = midi.to_msg(d)
		local data = {}
		local x, y

		if (msg.type == 'note_on' or msg.type == 'note_off' or msg.type == 'cc') then
			if (msg.type == 'note_on' or msg.type == 'note_off') then
				x = math.fmod(msg.note, 10)
				y = math.floor(msg.note / 10)
				data.state = (msg.type == 'note_on')
			elseif (msg.type == 'cc') then
				x = math.fmod(msg.cc, 10)
				y = math.floor(msg.cc / 10)
				data.state = (msg.val == 127)
			end

			local minX = math.min(self.display_start.x, self.display_end.x)
			local minY = math.min(self.display_start.y, self.display_end.y)

			local maxX = math.max(self.display_start.x, self.display_end.x)
			local maxY = math.max(self.display_start.y, self.display_end.y)

			local gridWidth = maxX - minX + 1
			local gridHeight = maxY - minY + 1

			if x <= self.offset.x or y <= self.offset.y or x > gridWidth + self.offset.x or y > gridHeight + self.offset.y then
				return false
			end

			data.x = x
			data.y = y

			if (x == 9 and y > 1) then
				data.type = 'row'
				data.row = (9 - data.y)
			elseif (x == 1 and y == 9) then data.type = 'up'
			elseif (x == 2 and y == 9) then data.type = 'down'
			elseif (x == 3 and y == 9) then data.type = 'left'
			elseif (x == 4 and y == 9) then data.type = 'right'
			elseif (x >= 5 and x <= 8 and y == 9) then
				data.type = 'mode'
				data.mode = (data.x - 4)
			elseif (x == 9 and y == 1) then
				data.type = 'alt'
			else
				data.type = 'pad'
			end

			-- Adjust x and y based on display start and offset
			data.x = minX + data.x - 1 - self.offset.x
			data.y = minY + data.y - 1 - self.offset.y

			-- Handle pad hold times
			if data.state == true then
				-- Pad pressed down
				if self.pad_hold_times[data.x] == nil then self.pad_hold_times[data.x] = {} end
				self.pad_hold_times[data.x][data.y] = util.time()
				
				table.insert(self.pad_down, data)
				
			elseif data.state == false then

				for i,pad in ipairs(self.pad_down) do
					if pad.x == data.x and pad.y == data.y then
						table.remove(self.pad_down, i)
					end
				end

				-- Pad released
				if self.pad_hold_times[data.x] and self.pad_hold_times[data.x][data.y] then
					local hold_time = util.time() - self.pad_hold_times[data.x][data.y]
					self.pad_hold_times[data.x][data.y] = nil  -- Clear the hold time

					-- Check if hold time exceeds threshold
					if hold_time >= self.long_press_threshold then
						-- Create a new data table for the long press event
						local long_press_data = {}
						for k, v in pairs(data) do
							long_press_data[k] = v
						end
						long_press_data.type = 'pad_long'
						long_press_data.hold_time = hold_time

						long_press_data.pad_down = self.pad_down

						-- Call event with the new data
						self:event(long_press_data)

						-- Also call event on subgrids
						local subgrids = self.subgrids
						if #subgrids > 0 then
							for i = 1, #subgrids do
								self.subgrids[i]:event(long_press_data)
							end
						end
					end
				end
			end

			-- Set toggled state
			if data.state then
				self.toggled[data.x][data.y] = (not self.toggled[data.x][data.y])
			end

			data.toggled = self.toggled[data.x][data.y]

			-- Event Handler
			self:event(data)

			-- Existing subgrid handling
			local subgrids = self.subgrids
			if #subgrids > 0 then
				for i = 1, #subgrids do
					self.subgrids[i].active = true
					self.subgrids[i]:event(data)
				end
			end
		end
	end
end

function Grid:for_each(func)
	local maxX = math.max(self.grid_start.x, self.grid_end.x)
	local minX = math.min(self.grid_start.x, self.grid_end.x)

	local maxY = math.max(self.grid_start.y, self.grid_end.y)
	local minY = math.min(self.grid_start.y, self.grid_end.y)

	for x = minX, maxX do
		for y = minY, maxY do
			func(self, x, y, self:grid_to_index({x = x, y = y}))
		end
	end
end

function Grid:reset()
	self:for_each(function(s, x, y)
		s.toggled[x][y] = false
		s.led[x][y] = 0
	end)
	-- We need to implement listeners for reset
	if self.on_reset ~= nil then
		self:on_reset()
	end

	self:refresh()
end

function Grid:set(x, y, z, offset)
	offset = offset or {x = 0, y = 0}
	local minX = math.min(self.display_start.x, self.display_end.x)
	local minY = math.min(self.display_start.y, self.display_end.y)

	x = x - minX + 1 + offset.x
	y = y - minY + 1 + offset.y

	return self:set_raw(x, y, z)
end

function Grid:set_raw(x, y, z, force)
	local target = math.fmod(x, 10) + 10 * y
	local message = {}

	if (type(z) == 'table') then
		if #z == 3 then
			-- length of 3, RGB
			message = utilities.concat_table(message, {3, target})
			message = utilities.concat_table(message, z)
		elseif z[2] == true and #z == 2 then
			-- length of 2, second value is true
			message = utilities.concat_table(message, {2, target})
			message = utilities.concat_table(message, {z[1]})
		elseif #z == 2 then
			-- length of 2
			message = utilities.concat_table(message, {1, target})
			message = utilities.concat_table(message, z)
		else
			-- length of 1
			message = utilities.concat_table(message, {0, target})
			message = utilities.concat_table(message, z)
		end
	else
		-- send single value to led
		message = utilities.concat_table(message, {0, target})
		message = utilities.concat_table(message, {z})
	end

	if force then
		local send = {240, 0, 32, 41, 2, 13, 3}
		send = utilities.concat_table(send, message)
		send = utilities.concat_table(send, {247})
		self.midi:send(send)
	else
		return message
	end
end

function Grid:refresh(debug)
	if self.active then
		--[[ Use this to debug grid refreshes to make sure we're not needlessly iterating through grid tables.

		if debug ~= nil then
			print(self.name .. ' refresh from ' .. debug)
		else
			print(self.name .. ' refresh')
		end

		--]]

		local message = {240, 0, 32, 41, 2, 13, 3}

		local minX = math.min(self.display_start.x, self.display_end.x)
		local minY = math.min(self.display_start.y, self.display_end.y)

		local maxX = math.max(self.display_start.x, self.display_end.x)
		local maxY = math.max(self.display_start.y, self.display_end.y)

		local gridWidth = maxX - minX + 1
		local gridHeight = maxY - minY + 1

		for x = minX, maxX do
			for y = minY, maxY do
				-- for grid values
				local grid_x = x - minX + 1 + self.offset.x
				local grid_y = y - minY + 1 + self.offset.y

				if grid_x <= self.offset.x or grid_y <= self.offset.y or grid_x > 9 or grid_y > 9 or grid_x > gridWidth + self.offset.x or grid_y > gridHeight + self.offset.y then
					goto continue
				end

				if (self.led[x] == nil or self.led[x][y] == nil) then
					local m = self:set_raw(grid_x, grid_y, 0)
					message = utilities.concat_table(message, m)
				else
					local m = self:set_raw(grid_x, grid_y, self.led[x][y])
					message = utilities.concat_table(message, m)
				end

				::continue::
			end
		end

		message = utilities.concat_table(message, {247})
		self.midi:send(message)
	end
end

function Grid:clear()
	local message = {240, 0, 32, 41, 2, 13, 3}
	for x = self.display_start.x, self.display_end.x do
		for y = self.display_start.y, self.display_end.y do
			-- for grid values
			local x = x - self.display_start.x + 1 + self.offset.x
			local y = y - self.display_start.y + 1 + self.offset.y

			local m = self:set_raw(x, y, 0)
			message = utilities.concat_table(message, m)
		end
	end

	message = utilities.concat_table(message, {247})
	self.midi:send(message)
end

function Grid:in_bounds(pos)
	self:update_bounds()
	return (pos.x >= self.bounds.min_x and pos.x <= self.bounds.max_x and pos.y >= self.bounds.min_y and pos.y <= self.bounds.max_y)
end

function Grid:in_display(pos)
	self:update_bounds()
	return (pos.x >= self.display_bounds.min_x and pos.x <= self.display_bounds.max_x and pos.y >= self.display_bounds.min_y and pos.y <= self.display_bounds.max_y)
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
	local minX = math.min(self.grid_start.x, self.grid_end.x)
	local minY = math.min(self.grid_start.y, self.grid_end.y)

	local maxX = math.max(self.grid_start.x, self.grid_end.x)
	local maxY = math.max(self.grid_start.y, self.grid_end.y)

	local width = maxX - minX + 1
	local height = maxY - minY + 1

	local x, y

	if self.grid_start.x > self.grid_end.x then
		x = width - math.fmod(index - 1, width) + minX - 1
	else
		x = math.fmod(index - 1, width) + minX
	end

	if self.grid_start.y > self.grid_end.y then
		y = height - math.floor((index - 1) / width) + minY - 1
	else
		y = math.floor((index - 1) / width) + minY
	end

	if (y > maxY) then
		return false
	else
		return {x = x, y = y}
	end
end

return Grid