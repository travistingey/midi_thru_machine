-- Seq is a tick based sequencer class.
-- Each instance provides a grid interface for a step sequencer.
-- Sequence step values can be used to exectute arbitrary functions that are defined after instantiation.

Seq = {}

function Seq:new (o)
    o = o or {}
    
    setmetatable(o, self)
    self.__index = self


    o.grid = o.grid

    if not o.grid then
        print('Error — Seq requires an instance of MidiGrid')
        return false
    end

    o.grid_start = o.grid_start or {x = 1, y = 8}
    o.grid_end = o.grid_end or {x = 8, y = 5}
    o.div = o.div or 12,
    o.select_step = 1,
    o.select_action = 1,
    o.map = {},
    o.value = {},
    o.length = o.length or 32,
    o.tick = 1,
    o.step = 1,
    o.actions = o.actions or 8
    o.action = o.action or function(value) print('Step ' .. self.step .. ' : Action ' .. value) end

    return o
end

function self.transport_event(data)
	-- Tick based sequencer running on 16th notes at 24 PPQN
	if data.type == 'clock' then
		self.tick = util.wrap(self.tick + 1, 1, self.div * self.length)
		local next_step = util.wrap(math.floor(self.tick / self.div) + 1, 1,
									self.length)
		local last_step = self.step

		-- Enter new step. c = current step, l = last step
		if next_step > last_step or next_step == 1 and last_step == self.length then

			local l = self.map[last_step]
			local c = self.map[next_step]

			local last_value = self.value[last_step] or 0
			local value = self.value[next_step] or 0
			
			if last_value == 0 then
				self.grid.led[l.x][l.y] = 0
			else
				self.grid.led[l.x][l.y] = rainbow_off[last_value]
			end
			if value == 0 then
				self.grid.led[c.x][c.y] = 1
			else
			    -- DO Stuff 
			    print('line 281 was here for sequencer actions.')
			    
			    self.action(value)
			    
				self.grid.led[c.x][c.y] = rainbow_on[value]
			end
		end

		self.step = next_step
	end

	-- Note: 'Start' is called at the beginning of the sequence
	if data.type == 'start' then
		self.tick = 0
		self.step = 1
	end

	
end

function self.grid_event(s, data)
	local x = data.x
	local y = data.y

	local index = MidiGrid.grid_to_index({x = x, y = y}, self.grid_start, self.grid_end)
	
	if(x == 1 and y == 9 and data.state) then
		-- up
		self.select_action = util.wrap(self.select_action + 1, 1, self.actions)
		
		local current = MidiGrid.index_to_grid(self.select_step, self.grid_start, self.grid_end)
		
		self.grid.led[1][9] = rainbow_off[util.wrap(self.select_action + 1, 1, self.actions)]
		self.grid.led[2][9] = rainbow_off[util.wrap(self.select_action - 1, 1, self.actions)]
		self.grid.led[9][9] = rainbow_off[self.select_action]
		

		if self.value[self.select_step] and self.value[self.select_step] > 0 then
			self.value[self.select_step] = self.select_action
			self.grid.led[current.x][current.y] = rainbow_off[self.select_action]
		end

		self.grid:redraw()
	end
	
	if(x == 2 and y == 9 and data.state) then
		-- down
		self.select_action = util.wrap(self.select_action - 1, 1, self.actions)
		
		local current = MidiGrid.index_to_grid(self.select_step, self.grid_start, self.grid_end)
		
		self.grid.led[1][9] = rainbow_off[util.wrap(self.select_action + 1, 1, self.actions)]
		self.grid.led[2][9] = rainbow_off[util.wrap(self.select_action - 1, 1, self.actions)]
		self.grid.led[9][9] = rainbow_off[self.select_action]
		
		if self.value[self.select_step] and self.value[self.select_step] > 0 then
			self.value[self.select_step] = self.select_action
			self.grid.led[current.x][current.y] = rainbow_off[self.select_action]
		end

		self.grid:redraw()
	end
	
	-- TODO: Pagination
	if(x == 3 and y == 9 and data.state) then
		-- left
	end
	
	if(x == 4 and y == 9 and data.state) then
		-- right
	end

	if (index ~= false and data.state) then
		local value = self.value[index] or 0
		print('seq' .. index)
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
			self.grid.led[x][y] = 0
		end		
	end
	self.grid:redraw()
end