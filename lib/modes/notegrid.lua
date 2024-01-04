
local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local NoteGrid = ModeComponent:new()
NoteGrid.__base = ModeComponent
NoteGrid.name = 'Mode Name'

function NoteGrid:set(o)
  self.__base.set(self, o) -- call the base set method first   

  o.component = 'input'
  o.register = {'on_load'} -- list events outside of transport, midi and grid events

  -- Record
  local note_start = {x=1,y=10}
  local note_end = {x=4,y=13}
  local record_start = {x=1,y=18}
  local record_end = {x=4,y=21}


  o.grid = Grid:new({
    name = 'NoteGrid ' .. o.track,
    grid_start = {x=1,y=1},
    grid_end = {x=4,y=32},
    display_start = o.display_start or record_start,
    display_end = o.display_end or record_end,
    offset = o.offset or {x=4,y=0},
    midi = App.midi_grid
  })

end

function NoteGrid:transport_event (component, data) end
function NoteGrid:midi_event (component, data) end
function NoteGrid:grid_event (component, data)
  local track = App.track[self.track]
  local grid = self.grid
  

  if(data.type == 'pad' and data.state) then
    local on = {
      type = 'note_on',
      note = grid:grid_to_index(data) - 1,
      vel = 100,
      ch = track.midi_out
    }
    tab.print(on)
    track:send_input(on)
  elseif (data.type == 'pad') then
    local off = {
      type = 'note_off',
      note = grid:grid_to_index(data) - 1,
      vel = 100,
      ch = track.midi_out
    }
    tab.print(off)
    track:send_input(off)
  end
  
  
  local note = grid:grid_to_index(data) - 1

end

function NoteGrid:set_grid (component) 
    local grid = self.grid
    
  	  grid:for_each(function(s,x,y,i)
  		s.led[x][y] = Grid.rainbow_on[(i - 1) % 16 + 1 ]
      end)

      grid:refresh('NoteGrid:set_grid')

end

function NoteGrid:set_display (component) end
function NoteGrid:handle_button (component, e, d) end
function NoteGrid:handle_enc (component, e, d) end

return NoteGrid