
local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local SeqClip = require('Foobar/lib/components/mode/seqclip')

local AllClips = SeqClip:new() 
AllClips.name = 'All Clips'

function AllClips:set(o)
	self.__base.set(self, o) -- call the base set method first   
  o.track = 1
  
  o.component = 'seq'
  o.register = {'on_arm'} -- list events outside of transport, midi and grid events
   
  o.grid = Grid:new({
      name = 'All Clips',
      grid_start = o.grid_start or {x=1,y=4},
      grid_end = o.grid_end or {x=8,y=1},
      display_start = o.display_start or {x=1,y=1},
      display_end = o.display_end or {x=8,y=4},
      offset = o.offset or {x=0,y=4},
      midi = App.midi_grid
  })
  
end

function AllClips:grid_event (component, data)
  local alt = App.alt
          
  for i = 1, #App.track do
      -- Process grid events for all tracks
      if alt then App.alt = true end -- Need to keep the alt reset from toggling for subsequent events
      
      SeqClip.grid_event(self, App.track[i].seq, data)
  end
end

function AllClips:set_grid (seq)
	SeqClip.set_grid(self, App.track[1].seq)
end 

return AllClips