-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local PresetGrid = ModeComponent:new()


PresetGrid.__base = ModeComponent
PresetGrid.name = 'Preset Grid'

function PresetGrid:set(o)
  self.__base.set(self, o) -- call the base set method first   
  self.select = o.select or 1
  self.component = 'scale'

  self.bank = o.bank or {}
  self.set = o.set or function(i) print('PresetGrid set ' .. i) end
  self.grid = Grid:new({
    name = 'PresetGrid ' .. o.id,
    grid_start = o.grid_start or {x=1,y=4},
    grid_end = o.grid_end or {x=4,y=1},
    display_start = o.display_start or {x=1,y=1},
    display_end = o.display_end or {x=4,y=4},
    offset = o.offset or {x=4,y=4},
    midi = App.midi_grid
  })

  self.alt_context = o.alt_context or {}
  self.alt_screen = o.alt_screen or function() end

  self.grid:refresh()

end


function PresetGrid:subscribe(number, func)
  if not self.bank[number] then
      self.bank[number] = {}
  end
  table.insert(self.bank[number], func)
end


function PresetGrid:unsubscribe(number, func)
  if self.bank[number] then
      for i, subscriber in ipairs(self.bank[number]) do
          if subscriber == func then
              table.remove(self.bank[number], i)
              break
          end
      end
  end
end

function PresetGrid:trigger(number)
  if self.bank[number] then
    for _, func in ipairs(self.bank[number]) do
        func()
    end
  end
end

function PresetGrid:grid_event (component, data)
  
  local grid = self.grid
  if data.state and data.type == 'pad' then
    self.select = self.grid:grid_to_index(data)
    
    if self.mode.alt and data.state then
      if self.on_alt ~= nil then
        self:on_alt(component)
      end

      self.mode:handle_context(self.alt_context, self.alt_screen)
    else
      self:trigger(self.select)
    end

  end
  self:set_grid()
end

function PresetGrid:transport_event(component, data)
end

function PresetGrid:set_grid (component) 
    local grid = self.grid
      grid:for_each(function(s,x,y,i)
        if i == self.select then
          s.led[x][y] = Grid.rainbow_on[i]
        else
          s.led[x][y] = 1
        end
      end)
      grid:refresh('PresetGrid:set_grid')
end

return PresetGrid