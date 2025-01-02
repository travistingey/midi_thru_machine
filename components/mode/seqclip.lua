
local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local SeqClip = ModeComponent:new()

SeqClip.__base = ModeComponent
SeqClip.name = 'Seq Clip'

function SeqClip:set(o)
	self.__base.set(self, o) -- call the base set method first   

   o.component = 'seq'
   o.register = {'on_arm'} -- list events outside of transport, midi and grid events

    o.grid = Grid:new({
      name = 'Seq clips',
      grid_start = o.grid_start or {x=1,y=1},
      grid_end = o.grid_end or  {x=16,y=1},
      display_start = o.display_start or {x=1,y=1},
      display_end = o.display_end or {x=8,y=1},
      offset = o.offset or {x=0,y=0},
      midi = App.midi_grid
  })

  o.page = 1
end

function SeqClip:transport_event(seq, data)
  if data.type == 'start' or data.type == 'stop' then
    self:set_grid(seq)
  end
end

function SeqClip:grid_event (seq, data) 
  local grid = self.grid
  local page_count = 2
  
  if data.type == 'left' then
    
    if self.page > 1 then
      self.page = self.page - 1
      grid:left(8)
    end
  elseif data.type == 'right' then
    if self.page < page_count then
      self.page = self.page + 1
      grid:right(8)
    end
  elseif data.type == 'pad' then

		
		local index = grid:grid_to_index(data)

		local last = seq.next_bank
		local last_bank = seq.bank[last]
		
		seq.next_bank = index

		
		local lookup = {
			[1]		=	{'load', 'overdub'},
			[2]		=	{'load', 'overdub'},
			[4]		=	{{'save','load'}, {'save','overdub'}},
			[5]		=	{'load','overdub'},
			[6]		=	{'load','overdub'},
			[8]		=	{ {'save', 'load'},{'save','overdub'}},
			[9]		=	{'record','bounce'},
			[10]	=	{'record','bounce'},
			[12]	=	{{'save','record'},{'save','bounce'}},
			[13]	=	{'record','bounce'},
			[14]	=	{'record','bounce'},
			[16]	=	{{'save','record'},{'save','bounce'}},
			[17]	=	{'clear','overdub'},
			[18]	=	{'clear','overdub'},
			[20]	=	{'save','delete'},
			[21]	=	{'cancel', 'delete'},
			[22]	=	{'cancel', 'delete'},
			[24]	=	{'cancel', 'delete'},
			[25]	=	{'record','bounce'},
			[26]	=	{'record','bounce'},
			[28]	=	{'save', 'delete'},
			[29]	=	{'cancel', 'cancel'},
			[30]	=	{'cancel', 'delete'},
			[32]	=	{'cancel', 'delete'}
		}
				
		if data.state then

			local score = 0 

			if App.playing then score = score + (1<<0) end
			if seq.recording then score = score + (1<<1) end
			if seq.armed then score = score + (1<<2) end
			if (seq.bank[index] == nil) then score = score + (1<<3) end
			if (last == index) or (seq.current_bank == index) then score = score + (1<<4) end
			
			
			if lookup[score + 1] ~= nil then
				if self.mode.alt == true then
					seq.armed = lookup[score + 1][2]
				else
					seq.armed = lookup[score + 1][1]
				end
			end

			self.mode.alt_pad:reset()
			
			if seq.armed == 'cancel' then
				seq.next_bank = 0
				seq.armed = false
			elseif seq.armed == 'delete' then
				seq.armed = false
				seq:clear(seq.current_bank)
			end

			if not App.playing and seq.armed ~= 'record' and seq.armed ~= 'bounce' then
				seq:arm_event()
			end
 		
 			self:set_grid(seq)

		end
	end
end

function SeqClip:set_grid (seq)
    local grid = self.grid
    if seq and seq.track.active then
      
  	  
  	  grid:for_each(function(s,x,y,i)
  			-- if(seq.bank[i])then
  			-- 	s.led[x][y] = 1
  			-- else
  			-- 	s.led[x][y] = {5,5,5}
  			-- end
  
  			if i == seq.current_bank then
  				if seq.recording then
  					s.led[x][y] = {3,true}
  				elseif (seq.bank[i]) then
  					s.led[x][y] = Grid.rainbow_on[(i - 1) % 16 + 1 ]
  				else
  					s.led[x][y] = {5,5,5}
  				end
  			end
  
  			local actions = {}
  
  			if seq.armed then
  				if type(seq.armed) == 'table' then
  					actions = seq.armed
  				else
  					actions = {seq.armed}
  				end
  			end
  
  			for _,action in ipairs(actions) do
  				if i == seq.next_bank then
  					if action == 'load' then
  						s.led[x][y] = {3,true}
  					else
  						s.led[x][y] = {4,true}
  					end
  				end
  			end
  
		end)
	else
		grid:reset()
    end
		
		grid:refresh('set grid')
	  
end 

function SeqClip:on_arm(seq)
  self:set_grid(seq)    
end

return SeqClip