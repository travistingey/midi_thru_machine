Mode = {}
Mode.types = {{
	name = 'Song Mode',
	type = 1,
	class = Seq,
	actions = 16,
	action = function(s,d)
		if(d > 0) then
			Preset.load(d)
		end
	end,
	on_grid = function(s,data)
	    
	    local x = data.x
        local y = data.y
        local index = MidiGrid.grid_to_index({x = x, y = y}, Preset.grid_start, Preset.grid_end)
        
        if (index ~= false and data.state) then
            
    	    s.select_action = index
            g.led[9][9] = rainbow_on[index]
            
            g:redraw()
        end
        
    end
},{
	name = 'Drum Effects',
	type = 2,
	class = Seq,
	actions = 4,
	action = function(s,d)
       if(d == 1) then
            transport:cc(9,26,16)
       elseif(d == 2) then
			transport:cc(9,50,16)
       elseif(d == 3) then
			transport:cc(9,75,16)
       elseif(d == 4) then
			transport:cc(9,100,16)
       else
			transport:cc(9,0,16)
       end
	end,
	on_grid = function(s,data)
	    local x = data.x
        local y = data.y
        local index = MidiGrid.grid_to_index({x = x, y = y}, Mute.grid_start, Mute.grid_end)
        local alt = get_alt()
        
        if (index ~= false and data.state and alt) then
           print('set drum effects bank ' .. index)
           s.bank = index 
        end
	end,
	on_alt = function(s,alt)
		local current = MidiGrid.index_to_grid(s.bank, Mute.grid_start, Mute.grid_end)
        
        for i = 1, 16 do
            local  c = MidiGrid.index_to_grid(i, Mute.grid_start, Mute.grid_end) 
            g.led[c.x][c.y] = 0
        end
        
		if(alt) then
			g.led[current.x][current.y] = rainbow_on[s.bank]
		else
			Mute:set_grid()
		end
	end
         
},{
	name = 'Key Mode',
	type = 3,
	class = Keys

}}

function Mode:load(data)
	
	for i = 1, 4 do
		local t = params:get('mode_' .. i .. '_type')

		if data and data[i] then
			self[i] = self.types[t].class:new(data[i])
		else
			self[i] = self.types[t].class:new()
		end

		self[i].on_grid = self.types[t].on_grid
		self[i].on_alt = self.types[t].on_alt
		self[i].on_transport = self.types[t].on_transport
		self[i].action = self.types[t].action
		self[i].actions = self.types[t].actions
		self[i].id = i
		
		if( self.types[t].actions ) then
			self[i].actions = self.types[t].actions
		end
		
		if( self.types[t].on_init ~= nil ) then
		    self.types[t].on_init(self[i])
		end
		
	end
	
	self[1].display = true
	g.led[5][9] = 3
    
	self.select = 1
	self[self.select]:set_grid()
	
	Mode:set_mode(1)
end

function Mode:set_mode(d)
	for i = 1, 4 do
		if i == self.select then
			self[i].display = true
		else
			self[i].display = false
		end
	end

	self[self.select].grid.led[self.select + 4][9] = 3
	self[self.select]:set_grid()
	self[self.select].select_action = Preset.select
	self[self.select].grid.led[9][9] = rainbow_on[Preset.select]
	Mode:set_grid()
end

function Mode:grid_event(data)
	local x = data.x
	local y = data.y
	local alt = get_alt()

	-- Mode Select
	if x > 4 and y == 9 and data.state then
		local m = x - 4
		
		if(alt) then 
			self[m].enabled = (not self[m].enabled)
			set_alt(false)
		else
			self.select = m
			self:set_mode(m)
		end
		
		self:set_grid()
	end
	
	if self[self.select].on_grid ~= nil then
	    self[self.select]:on_grid(data)
	end

end

function Mode:set_grid()
	for i = 5, 8 do 
		local m = i - 4
		if self.select == m and self[m].enabled then
			g.led[i][9] = 3
		elseif self[m].enabled then
			g.led[i][9] = 0
		elseif self.select == m then
			g.led[i][9] = {5, true}
		else
			g.led[i][9] = {7, true}
		end
	end
	g:redraw()
end