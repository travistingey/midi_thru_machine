
local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local NoteGrid = ModeComponent:new()
NoteGrid.__base = ModeComponent
NoteGrid.name = 'Mode Name'

function NoteGrid:set(o)
  self.__base.set(self, o) -- call the base set method first   

  self.component = 'input'
  self.register = {'on_load'} -- list events outside of transport, midi and grid events

  -- Record
  
  
  
  
  local clear_start = {x=1,y=18}
  local clear_end = {x=4,y=21}
  
  local preset_start = {x=1,y=1}
  local preset_end = {x=4,y=4}

  self.select = o.select or 1


  self.grid = Grid:new({
    name = 'NoteGrid ' .. o.track,
    grid_start = {x=1,y=1},
    grid_end = {x=4,y=32},
    display_start = o.display_start or preset_start,
    display_end = o.display_end or preset_end,
    offset = o.offset or {x=4,y=0},
    midi = App.midi_grid
  })

  self.action[self.select].set(self)
end

function NoteGrid:select_action (d)
  self.select = d
  self.action[d].set(self)
end


NoteGrid.action = {
  [1] = {
    name = 'Pad',
    set = function(s)
      local note_start = {x=1,y=10}
      local note_end = {x=4,y=13}

      s.grid.display_start = note_start
      s.grid.display_end = note_end
      s.grid:refresh()

    end,
    send = function(s,data)
      local track = App.track[s.track] 
      if data.state then
        local on = {
          type = 'note_on',
          note = s.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = track.midi_out
        }
        print(on)
        track:send_input(on)
      else
        local off = {
          type = 'note_off',
          note = s.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = track.midi_out
        }
        print(off)
        track:send_input(off)
      end
    end
  },
  [2] = {
    name = 'Record',
    set = function(s)
      
      local note_start = {x=1,y=18}
      local note_end = {x=4,y=21}

      s.grid.display_start = note_start
      s.grid.display_end = note_end
      s.grid:refresh()

    end,
    send = function(s,data)
      local track = App.track[s.track] 
      if data.state then
        local on = {
          type = 'note_on',
          note = s.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = 10
        }
        track:send_input(on)
      else
        local off = {
          type = 'note_off',
          note = s.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = 10
        }
        track:send_input(off)
      end
    end
  },
    [3] = {
      name = 'Clear',
      set = function(s)
        
        local note_start = {x=1,y=22}
        local note_end = {x=4,y=25}

        s.grid.display_start = note_start
        s.grid.display_end = note_end
        s.grid:refresh()
  
      end,
      send = function(s,data)
        local track = App.track[s.track] 
        if data.state then
          local on = {
            type = 'note_on',
            note = s.grid:grid_to_index(data) - 1,
            vel = 100,
            ch = 10
          }
          track:send_input(on)
        else
          local off = {
            type = 'note_off',
            note = s.grid:grid_to_index(data) - 1,
            vel = 100,
            ch = 10
          }
          track:send_input(off)
        end
      end
    },


    [4] = {
      name = 'Drum Pattern',
      set = function(s)
        
        local note_start = {x=1,y=1}
        local note_end = {x=4,y=4}

        s.grid.display_start = note_start
        s.grid.display_end = note_end
        s.grid:refresh()
  
      end,
      send = function(s,data)
        local track = App.track[s.track] 
        if data.state then
          App.midi_in:program_change(s.grid:grid_to_index(data) - 1, 10)
        end
      end
    },
    [5] = {
      name = 'Slice Pattern',
      set = function(s)
        
        local note_start = {x=1,y=1}
        local note_end = {x=4,y=4}

        s.grid.display_start = note_start
        s.grid.display_end = note_end
        s.grid:refresh()
  
      end,
      send = function(s,data)
        local track = App.track[s.track] 
        if data.state then
          App.midi_in:program_change(s.grid:grid_to_index(data) - 1, 13)
        end
      end
    }
}


function NoteGrid:transport_event (component, data) end
function NoteGrid:midi_event (component, data) end
function NoteGrid:grid_event (component, data)
  local track = App.track[self.track]
  local grid = self.grid
  

  if(data.type == 'pad') then
    
    self.action[self.select].send(self,data)

  end
  
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