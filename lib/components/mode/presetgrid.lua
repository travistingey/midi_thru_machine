local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local PresetGrid = ModeComponent:new()

PresetGrid.__base = ModeComponent
PresetGrid.name = 'presetgrid'

function PresetGrid:set(o)
    self.__base.set(self, o)
    self.select = o.select or 1
    self.param_type = o.param_type      -- eg. 'track', 'scale', 'cc'
    self.param_ids = o.param_ids        -- e.g., {1,2,3} or function returning ids
    self.param_list = o.param_list      -- Predefined list of parameter names
    self.id = o.id

    -- If param_type is set, we assume it's bound to a component
    self.component = 'auto'

    self.grid = Grid:new({
        name = 'PresetGrid',
        grid_start = o.grid_start or {x=1, y=4},
        grid_end = o.grid_end or {x=4, y=1},
        display_start = o.display_start or {x=1, y=1},
        display_end = o.display_end or {x=4, y=4},
        offset = o.offset or {x=4, y=0},
        midi = App.midi_grid
    })
    self.alt_context = o.alt_context or {}
    self.alt_screen = o.alt_screen or function() end
    self.grid:refresh()
end
function PresetGrid:enable_event()
    local auto = self:get_component()
    table.insert(self.cleanup_functions, auto:on('preset_change', function(data)
        self:set_grid(auto)
    end))
   
end

function PresetGrid:get_param_list()
    if self.param_list then
        return self.param_list
    elseif self.param_type and self.param_ids then
        local params = {}
        local props = App.preset_props[self.param_type]
        
        if props then
            local ids = self.param_ids
            
            if type(ids) == 'function' then
                ids = ids()  -- Call the function to get the current ids
            end

            for _, id in ipairs(ids) do
                for _, prop in ipairs(props) do
                    local param_name
                    param_name = self.param_type  .. '_' .. id .. '_' .. prop
                    table.insert(params, param_name)
                end
            end
        end
        return params
    elseif self.param_type and self.track  then
        local params = {}
        local props = App.preset_props[self.param_type]
        
        for _, prop in ipairs(props) do
            local param_name
            param_name = self.param_type  .. '_' .. self.track .. '_' .. prop
            table.insert(params, param_name)
        end
        return params
    else
        return {}
    end
end

function PresetGrid:save_preset(number)
    local param_list = self:get_param_list()
    App:save_preset(number, param_list)
    self.mode:toast('Saved preset ' .. number)
end

function PresetGrid:load_preset(number)
    if self.component then
        local component = self:get_component()
        if component then
            component.track.current_preset = number
        end
    end
    local param_list = self:get_param_list()
    App:load_preset(number, param_list)
    self.mode:toast('Loaded preset ' .. number)
end

-- If no value is specified, it references the track's current_preset
function PresetGrid:set_select(value)
    local track = self:get_component().track

    if value then
        self.select = { type = self.param_type, value = value }
    elseif self.param_type == 'track' then
        self.select = { type='track', value = track.current_preset }
    elseif self.param_type == 'cc' then
        self.select = { type='cc', value = track.current_preset }
    end
    
end

function PresetGrid:grid_event(component, data)

    local auto = self:get_component()

    if data.state and data.type == 'pad' then
        local selection = self.grid:grid_to_index(data)

        if self.mode.alt then
            self:save_preset(selection)
            self:emit('alt_reset')
        else
            self:set_select(selection)
            self:emit('preset_select', self.select)
            self:load_preset(selection)
        end
        if component then
            component.track.current_preset = selection
        end
        self:set_grid(component)
    end
end

function PresetGrid:set_grid(component)
    if component then
        self.select = component.track.current_preset
    end
    local grid = self.grid
    grid:for_each(function(s, x, y, i)
        if i == self.select then
            s.led[x][y] = Grid.rainbow_on[(i - 1) % #Grid.rainbow_on + 1]
        else
            s.led[x][y] = 1
        end
    end)
    grid:refresh('PresetGrid:set_grid')
end

function PresetGrid:row_event(data)
    if data.state then
        self.track = data.row
    end
end

return PresetGrid