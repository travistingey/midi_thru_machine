-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local PresetGrid = ModeComponent:new()

local DRUM_CHANNEL = 10
local SEQ_1_CHANNEL = 1
local SEQ_2_CHANNEL = 2

local TYPES = {'trigger','launch','empty'}

PresetGrid.__base = ModeComponent
PresetGrid.name = 'Note Grid'

function PresetGrid:set(o)
  self.__base.set(self, o) -- call the base set method first   
  self.select = o.select or 1
  self.component = 'input'

  self.grid = Grid:new({
    name = 'PresetGrid ' .. o.track,
    grid_start = {x=1,y=4},
    grid_end = {x=4,y=1},
    display_start = o.display_start or {x=1,y=1},
    display_end = o.display_end or {x=4,y=4},
    offset = o.offset or {x=4,y=4},
    midi = App.midi_grid
  })

  self.grid:refresh()

end

function PresetGrid:grid_event (component, data)
  
  local grid = self.grid
  if data.state and data.type == 'pad' then
    self.select = self.grid:grid_to_index(data)
    
    App.midi_in:program_change (self.select - 1, DRUM_CHANNEL)
    App.midi_in:program_change (self.select - 1, SEQ_1_CHANNEL)
    App.midi_in:program_change (self.select - 1, SEQ_2_CHANNEL)
  end
  self:set_grid()
end

function PresetGrid:transport_event(component, data)
tab.print(data)
end

function PresetGrid:set_grid (component) 
    local grid = self.grid
      grid:for_each(function(s,x,y,i)
        if i == self.select then
          s.led[x][y] = Grid.rainbow_on[i]
        else
          s.led[x][y] = 0
        end
      end)
      grid:refresh('PresetGrid:set_grid')
end

return PresetGrid