-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local PresetSeq = ModeComponent:new()

local DRUM_CHANNEL = 10
local SEQ_1_CHANNEL = 1
local SEQ_2_CHANNEL = 2

PresetSeq.__base = ModeComponent
PresetSeq.name = 'Note Grid'

function PresetSeq:set(o)
  self.__base.set(self, o) -- call the base set method first   
  self.select = o.select or 1
  self.step = 1
  self.component = 'input'

  self.grid = Grid:new({
    name = 'PresetSeq ' .. o.track,
    grid_start = {x=1,y=4},
    grid_end = {x=8,y=1},
    display_start = o.display_start or {x=1,y=1},
    display_end = o.display_end or {x=8,y=4},
    offset = o.offset or {x=0,y=4},
    midi = App.midi_grid
  })

  self.grid:refresh()

  self.seq = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}

end

function PresetSeq:grid_event (component, data)
  
  local grid = self.grid
  if data.state and data.type == 'pad' then
    local index = self.grid:grid_to_index(data)
    
    if self.seq[index] then
      self.seq[index] = nil
    else
      self.seq[index] = self.select
    end
    
  end
  self:set_grid()
end

function PresetSeq:run(value)
  if value then
    print('run')
    App.midi_in:program_change (value - 1, DRUM_CHANNEL)
    App.midi_in:program_change (value - 1, SEQ_1_CHANNEL)
    App.midi_in:program_change (value - 1, SEQ_2_CHANNEL)
  end
end

function PresetSeq:transport_event(component, data)

  if data.type == 'start' then
    self:run(self.seq[1])
    self.step = 1
  elseif data.type == 'clock' then
    local current = math.ceil((App.tick + 1) / 96)

    if current ~= self.step then
      self.step = current

      local value = self.seq[current]
      if self.seq[(current - 2) % #self.seq + 1 ] ~= value then
        self:run(value)
      end
    end
  end

  self:set_grid()
  
end

function PresetSeq:set_grid (component) 
  local current = self.step

    local grid = self.grid
      grid:for_each(function(s,x,y,i)
        if self.seq[i] then
          if i == current then
            s.led[x][y] = self.grid.rainbow_on[self.seq[i]]
          else
            s.led[x][y] = self.grid.rainbow_off[self.seq[i]]
          end
        elseif i == current then
          s.led[x][y] = 1
        else
          s.led[x][y] = 0
        end
      end)
      grid:refresh('PresetSeq:set_grid')
end

return PresetSeq