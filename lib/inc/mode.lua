local path_name = 'Foobar/lib/'
local App = require(path_name .. 'app')

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
            App.grid.led[9][9] = MidiGrid.rainbow_on[index]
            App.grid:redraw()
        end
        
    end
},{
	name = 'Drum Effects',
	type = 2,
	class = Seq,
	actions = 4,
	action = function(s,d)
       if(d == 1) then
            App.midi_in:cc(9,6,16)
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
        local alt = App:get_alt()
        
        if (index ~= false and data.state and alt) then
           print('set drum effects bank ' .. index)
           s.bank = index 
        end
	end,
	on_alt = function(s,alt)
		local current = MidiGrid.index_to_grid(s.bank, Mute.grid_start, Mute.grid_end)
        
        for i = 1, 16 do
            local  c = MidiGrid.index_to_grid(i, Mute.grid_start, Mute.grid_end) 
            App.grid.led[c.x][c.y] = 0
        end
        
		if(alt) then
			App.grid.led[current.x][current.y] = MidiGrid.rainbow_on[s.bank]
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
		self[i].on_midi = self.types[t].on_midi
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
	App.grid.led[5][9] = 3
	
	self:set_mode(1)
end

function Mode:set_mode(d)
	App:set('mode',d)
	for i = 1, 4 do
		if i == App.mode then
			self[i].display = true
		else
			self[i].display = false
		end
	end

	App.grid.led[App.mode + 4][9] = 3
	self[App.mode]:set_grid()
	self[App.mode].select_action = App.preset
	self[App.mode].grid.led[9][9] = MidiGrid.rainbow_on[App.preset]
	Mode:set_grid()
end

function Mode:grid_event(data)
	local x = data.x
	local y = data.y
	local alt = App:get_alt()

	-- Mode Select
	if x > 4 and y == 9 and data.state then
		local m = x - 4
		
		if(alt) then 
			self[m].enabled = (not self[m].enabled)
			App:set_alt(false)
		else
			
			self:set_mode(m)
		end
		
		self:set_grid()
	end
	
	if self[App.mode].on_grid ~= nil then
	    self[App.mode]:on_grid(data)
	end

end

function Mode:set_grid()
	for i = 5, 8 do 
		local m = i - 4
		if App.mode == m and self[m].enabled then
			App.grid.led[i][9] = 3
		elseif self[m].enabled then
			App.grid.led[i][9] = 0
		elseif App.mode == m then
			App.grid.led[i][9] = {5, true}
		else
			App.grid.led[i][9] = {7, true}
		end
	end
	App.grid:redraw()
end
