local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')
local Grid = require(path_name .. 'grid')
local musicutil = require(path_name .. 'musicutil-extended')

-- 

local Scale = TrackComponent:new()
Scale.__base = TrackComponent
Scale.name = 'scale'

function Scale:set(o)
	self.__base.set(self, o) -- call the base set method first   
	
  o.grid = o.grid
  o.root = o.root or 0
  o.bits = o.bits or 0
  o.range = o.range or 128
  
  o:set_scale(o.bits)
  -- Keyboard for 8x2 grid moving top left to bottom right
  o.index_map = { 
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
  
  o.note_map = {
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

function Scale:set_scale(bits)
	self.bits = bits
	self.intervals = musicutil.bits_to_intervals(bits)
	self.notes = {}

  local i = 0
  
	for oct=1,10 do
		for i=1,#self.intervals do
			self.notes[(oct - 1) * #self.intervals + i] = self.intervals[i] + (oct-1) * 12
		end
	end
	
end


function Scale:shift_scale_to_note(n)
	local scale = musicutil.shift_scale(self.bits, n - self.root)
	self.root = n
	self:set_scale(scale)
end


function Scale:midi_event(data, track)
    local root = self.root
    
    if data.note then
        if self.bits == 0 then
			return data
		else
			data.note = musicutil.snap_note_to_array(data.note  + root, self.notes)
			
			return data
		end
  	else
		
		  return data
    end
end


function Scale:grid_event(data)
    if data.type == 'pad' then
    
    	local index = self.grid:grid_to_index(data)
    	
		if(index and data.state and self.index_map[index])then
    		local d = self.index_map[index]
			
    		if App.alt then
    			self:shift_scale_to_note(d.note)
    			App.alt_pad:reset()
    		else
				  local bit_flag = (1 << ((24 + d.note - self.root) % 12) ) -- bit representation for note
    			self:set_scale(self.bits ~ bit_flag )
    		end
			
			for i = 1, 16 do
				if App.track[i].scale_select == self.id then
					App.track[i].output:kill()
				end
			end

			self:set_grid()
    	
		  end    
    end
end

function Scale:set_grid()

	if self.grid.active then
		local scale =  musicutil.bits_to_intervals(self.bits)
		local root = self.root
		
		for i, v in pairs(self.note_map) do
			local l = self.grid:index_to_grid(v.index)
			self.grid.led[l.x][l.y] = {5,5,5}
		end

		if #scale > 0 then
			for i, v in pairs(scale) do
				local n = (24 + v + root) % 12
				local c = self.note_map[n]
				local l = self.grid:index_to_grid(c.index)
		
				if (n == root % 12 ) then
					self.grid.led[l.x][l.y] = Grid.rainbow_on[ (self.id - 1) % #Grid.rainbow_on + 1]
					
					if n == 0 then
						l = self.grid:index_to_grid(16)
						self.grid.led[l.x][l.y] = Grid.rainbow_on[ (self.id - 1) % #Grid.rainbow_on + 1]
					end
				else
					self.grid.led[l.x][l.y] = Grid.rainbow_off[ (self.id - 1) % #Grid.rainbow_off + 1]
					
					if n == 0 then
						l = self.grid:index_to_grid(16)
						self.grid.led[l.x][l.y] = Grid.rainbow_off[ (self.id - 1) % #Grid.rainbow_off + 1]
					end
				end
			end
		end
		
		self.grid:refresh('set grid')
	end
end

return Scale