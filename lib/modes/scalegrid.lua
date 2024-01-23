local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local musicutil = require(path_name .. 'musicutil-extended')

local ScaleGrid = ModeComponent:new()
ScaleGrid.__base = ModeComponent
ScaleGrid.name = 'Mode Name'

function ScaleGrid:set(o)
	self.__base.set(self, o) -- call the base set method first   

   	self.component = 'scale'
	
    self.grid = Grid:new({
        name = 'Scale ' .. o.id,
        grid_start = {x=1,y=2},
        grid_end = {x=8,y=1},
        display_start = o.display_start or {x=1,y=1},
        display_end = o.display_end or {x=8,y=2},
        offset = o.offset or {x=0,y=0},
        midi = App.midi_grid
    })
	
	-- Keyboard for 8x2 grid moving top left to bottom right
	self.index_map = { 
		[9] = {note = 0, name = 'C' },
		[2] = {note = 1, name = 'C#'  },
		[10] = {note = 2, name = 'D' },
		[3] = {note = 3, name = 'D#' },
		[11] = {note = 4, name = 'E' },
		[12] = {note = 5, name = 'F' },
		[5] = {note = 6, name = 'F#' },
		[13] = {note = 7, name = 'G' },
		[6] = {note = 8, name = 'G#' },
		[14] = {note = 9, name = 'A' },
		[7] = {note = 10,  name = 'A#' },
		[15] = {note = 11, name = 'B' },
		[16] = {note = 0, name = 'C' }
	}
  
	self.note_map = {
		[0] = { index = 9, name = 'C' },
		[1] = { index = 2, name = 'C#' },
		[2] = { index = 10, name = 'D' },
		[3] = { index = 3, name = 'D#' },
		[4] = { index = 11, name = 'E' },
		[5] = { index = 12, name = 'F' },
		[6] = { index = 5, name = 'F#' },
		[7] = { index = 13, name = 'G' },
		[8] = { index = 6, name = 'G#' },
		[9] = { index = 14, name = 'A' },
		[10] = { index = 7, name = 'A#' },
		[11] = { index = 15, name = 'B' },
		[12] = { index = 16, name = 'C' }
	}
end

function ScaleGrid:get_component()
    return App.scale[self.id]
end

function ScaleGrid:set_scale(id)
  self:disable()
  self.id = id
  self:enable()
end

function ScaleGrid:midi_event(scale,data)
	tab.print(data)
end

function ScaleGrid:grid_event (scale, data)
   if data.type == 'pad' then
      local grid = self.grid
    	local index = grid:grid_to_index(data)
    	
		if(index and data.state and self.index_map[index])then
    		local d = self.index_map[index]
			
    		if self.mode.alt then
    			scale:shift_scale_to_note(d.note)
    			self.mode.alt_pad:reset()
    		else
				  local bit_flag = (1 << ((24 + d.note - scale.root) % 12) ) -- bit representation for note
    			scale:set_scale(scale.bits ~ bit_flag )
    		end


			for i = 1, 3 do
				App.scale[i]:follow_scale()
			end

			App.mode[App.current_mode]:enable()
			
		  end    
    end  
end 

function ScaleGrid:set_grid(scale)
	
  local grid = self.grid
  local intervals =  musicutil.bits_to_intervals(scale.bits)
		local root = scale.root
		
		for i, v in pairs(self.note_map) do
			local l = grid:index_to_grid(v.index)
			grid.led[l.x][l.y] = {5,5,5}
		end

		if #intervals > 0 then
			for i, v in pairs(intervals) do
				local n = (24 + v + root) % 12
				local c = self.note_map[n]
				local l = grid:index_to_grid(c.index)
		
				if (n == root % 12 ) then
					grid.led[l.x][l.y] = Grid.rainbow_on[ (scale.id - 1) % #Grid.rainbow_on + 1]
					
					if n == 0 then
						l = grid:index_to_grid(16)
						grid.led[l.x][l.y] = Grid.rainbow_on[ (scale.id - 1) % #Grid.rainbow_on + 1]
					end
				else
					grid.led[l.x][l.y] = Grid.rainbow_off[ (scale.id - 1) % #Grid.rainbow_off + 1]
					
					if n == 0 then
						l = grid:index_to_grid(16)
						grid.led[l.x][l.y] = Grid.rainbow_off[ (scale.id - 1) % #Grid.rainbow_off + 1]
					end
				end
			end
		end
		
		grid:refresh('set grid')
  end

return ScaleGrid