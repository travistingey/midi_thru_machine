local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local PresetGrid = ModeComponent:new()

PresetGrid.__base = ModeComponent
PresetGrid.name = 'Preset Grid'

function PresetGrid:set(o)
    self.__base.set(self, o)
    self.select = o.select or 1
    self.param_list = o.param_list or {} -- List of parameter names
    self.id = o.id
    self.grid = Grid:new({
        name = 'PresetGrid ' .. o.id,
        grid_start = o.grid_start or {x=1, y=4},
        grid_end = o.grid_end or {x=4, y=1},
        display_start = o.display_start or {x=1, y=1},
        display_end = o.display_end or {x=4, y=4},
        offset = o.offset or {x=4, y=4},
        midi = App.midi_grid
    })
    self.alt_context = o.alt_context or {}
    self.alt_screen = o.alt_screen or function() end
    self.grid:refresh()
end

function PresetGrid:save_preset(number)
    App:set_preset(number, self.param_list)
end

function PresetGrid:load_preset(number)
    App:load_preset(number, self.param_list)
end

function PresetGrid:grid_event(component, data)
    if data.state and data.type == 'pad' then
        self.select = self.grid:grid_to_index(data)
        if self.mode.alt then
          self:save_preset(self.select, self.param_list)
          print('Preset saved to ' .. self.select)
        else
          self:load_preset(self.select, self.param_list)
          print('Preset loaded from ' .. self.select)
        end
    end
    self:set_grid()
end

function PresetGrid:set_grid()
    local grid = self.grid
    grid:for_each(function(s, x, y, i)
        if i == self.select then
            s.led[x][y] = Grid.rainbow_on[i]
        else
            s.led[x][y] = 1
        end
    end)
    grid:refresh('PresetGrid:set_grid')
end

return PresetGrid