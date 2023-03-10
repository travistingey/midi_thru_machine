-- Keys 

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
    o.div = o.div or 12
    o.select_step = 1
    o.select_action = 1
	o.type = o.type or 1
    o.index_map = {
		[9] = {note = 0, scale = 1, x=1, y=7, name = 'C' },
		[2] = {note = 1, scale = 1, x=2, y=8, name = 'C#'  },
		[10] = {note = 2, scale = 1, x=2, y=7, name = 'D' },
		[3] = {note = 3, scale = 1, x=3, y=8, name = 'D#' },
		[11] = {note = 4, scale = 1, x=3, y=7, name = 'E' },
		[12] = {note = 5, scale = 1, x=4, y=7, name = 'F' },
		[5] = {note = 6, scale = 1, x=5, y=8,  name = 'F#' },
		[13] = {note = 7, scale = 1, x=5, y=7,  name = 'G' },
		[6] = {note = 8, scale = 1, x=6, y=8,  name = 'G#' },
		[14] = {note = 9, scale = 1, x=6, y=7, name = 'A' },
		[7] = {note = 10, scale = 1, x=7, y=8,  name = 'A#' },
		[15] = {note = 11, scale = 1, x=7, y=7, name = 'B' },
		[16] = {note = 0, scale = 1, x=8, y=7, name = 'C' },
		
		[25] = {note = 0, scale = 2, x=1,y=5 , name = 'C' },
		[18] = {note = 1, scale = 2, x=2,y=6, name = 'C#'  },
		[26] = {note = 2, scale = 2, x=2,y=5, name = 'D' },
		[19] = {note = 3, scale = 2, x=3,y=6, name = 'D#' },
		[27] = {note = 4, scale = 2, x=3,y=5, name = 'E' },
		[28] = {note = 5, scale = 2, x=4,y=5, name = 'F' },
		[21] = {note = 6, scale = 2, x=5,y=6, name = 'F#' },
		[29] = {note = 7, scale = 2, x=5,y=5, name = 'G' },
		[22] = {note = 8, scale = 2, x=6,y=6, name = 'G#' },
		[30] = {note = 9, scale = 2, x=6,y=5, name = 'A' },
		[23] = {note = 10, scale = 2, x=7,y=6, name = 'A#' },
		[31] = {note = 11, scale = 2, x=7,y=5, name = 'B' },
		[32] = {note = 0, scale = 2, x=8,y=5, name = 'C' }
	}

	o.note_map = {
		[0] = { scale_1 = {x=1,y=7}, scale_2 = {x=1,y=5}, name = 'C' },
		[1] = { scale_1 = {x=2,y=8}, scale_2 = {x=2,y=6}, name = 'C#'  },
		[2] = { scale_1 = {x=2,y=7}, scale_2 = {x=2,y=5}, name = 'D' },
		[3] = { scale_1 = {x=3,y=8}, scale_2 = {x=3,y=6}, name = 'D#' },
		[4] = { scale_1 = {x=3,y=7}, scale_2 = {x=3,y=5}, name = 'E' },
		[5] = { scale_1 = {x=4,y=7}, scale_2 = {x=4,y=5}, name = 'F' },
		[6] = { scale_1 = {x=5,y=8}, scale_2 = {x=5,y=6}, name = 'F#' },
		[7] = { scale_1 = {x=5,y=7}, scale_2 = {x=5,y=5}, name = 'G' },
		[8] = { scale_1 = {x=6,y=8}, scale_2 = {x=6,y=6}, name = 'G#' },
		[9] = { scale_1 = {x=6,y=7}, scale_2 = {x=6,y=5}, name = 'A' },
		[10] = { scale_1 = {x=7,y=8}, scale_2 = {x=7,y=6}, name = 'A#' },
		[11] = { scale_1 = {x=7,y=7}, scale_2 = {x=7,y=5}, name = 'B' },
		[12] = { scale_1 = {x=8,y=7}, scale_2 = {x=8,y=5}, name = 'C' }
	}

    o.actions = o.actions or 16
    o.action = o.action or function(value)  end
    o.display = o.display or false
	o.on_grid = o.on_grid
	o.on_transport = o.on_transport
	o.data = o.data or {}
	
	
	if(o.enabled == nil) then
		o.enabled = true
	end
	

	return o
end

function Keys:alt_event(state)
	self:set_grid()
end

function Keys:set_grid()
	if self.display then
		local alt = self.grid.toggled[9][1]

        for x = math.min(self.grid_start.x,self.grid_end.x), math.max(self.grid_start.x,self.grid_end.x) do
            for y = math.min(self.grid_start.y,self.grid_end.y), math.max(self.grid_start.y,self.grid_end.y) do
				self.grid.led[x][y] = 0
			end
		end

		local s1 =  bits_to_intervals(Scale[1].bits)
		local s2 =  bits_to_intervals(Scale[2].bits)
		
		for i, v in pairs(self.note_map) do
			local one = v['scale_1']
			local two = v['scale_2']
			self.grid.led[one.x][one.y] = {5,5,5}
			self.grid.led[two.x][two.y] = {5,5,5}
		end
		
		for i, v in pairs(s1) do
			
			local n = math.fmod(24 + v + Scale[1].root,12)
			local c = self.note_map[n]
			if (n == math.fmod(Scale[1].root,12) ) then
				self.grid.led[c['scale_1'].x][c['scale_1'].y] = rainbow_on[math.fmod(Preset.select,#rainbow_on + 1)]
				if n == 0 then
					self.grid.led[8][7] = rainbow_on[math.fmod(Preset.select,#rainbow_on + 1)]
				end
			else
				self.grid.led[c['scale_1'].x][c['scale_1'].y] = rainbow_off[math.fmod(Preset.select,#rainbow_off + 1)]
				if n == 0 then
					self.grid.led[8][7] = rainbow_off[math.fmod(Preset.select,#rainbow_off + 1)]
				end
			end
		end

		for i, v in pairs(s2) do
			
			local n = math.fmod(24 + v + Scale[2].root,12)
			local c = self.note_map[n]
			if (n == math.fmod(Scale[2].root,12) ) then
				self.grid.led[c['scale_2'].x][c['scale_2'].y] = rainbow_on[math.fmod(Preset.select,#rainbow_on + 1)]
				if n == 0 then
					self.grid.led[8][5] = rainbow_on[math.fmod(Preset.select,#rainbow_on + 1)]
				end
			else
				self.grid.led[c['scale_2'].x][c['scale_2'].y] = rainbow_off[math.fmod(Preset.select,#rainbow_off + 1)]
				if n == 0 then
					self.grid.led[8][5] = rainbow_off[math.fmod(Preset.select,#rainbow_off + 1)]
				end
			end
		end
		
	end
end


function Keys:transport_event(data)
	if self.on_transport ~= nil and self.enabled then
		self:on_transport(data)
	end
end


function Keys:grid_event(data)
    if self.display then
    	local x = data.x
    	local y = data.y
    	local alt = self.grid.toggled[9][1]
    
    	local index = MidiGrid.grid_to_index({x = x, y = y}, self.grid_start, self.grid_end)
    	
		if(index and data.state and self.index_map[index])then
    		local note = self.index_map[index]
			
			if(alt) then
			    
			if note.scale == 1 then
				local scale = shift_scale(Scale[note.scale].bits, note.note - Scale[note.scale].root)
				Scale[note.scale].root = note.note
				set_scale(scale, note.scale)
				else
					Scale[2].root = note.note
				end
				screen_dirty = true
			else
				
				if ( note.scale == 1 ) then
					set_scale(Scale[1].bits ~ (1 << (math.fmod(24 + note.note - Scale[1].root,12))),1)
				elseif(note.scale == 2) then
					set_scale(Scale[2].bits ~ (1 << (math.fmod(24 + note.note - Scale[2].root,12))),2)
				end
				
			end
			self:set_grid()
    		self.grid:redraw()
		end
    end
end

return Keys