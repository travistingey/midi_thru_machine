local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Output = require(path_name .. 'output')
local Grid = require(path_name .. 'grid')

-- Define a new class for Mode
local Mode = {}

-- Constructor

function Mode:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self:set(o)
    self:register_params(o)
    return o
end

--[[
    TODO: we're going to offload the options into individual mode components.
    the new approach will be:
        -   directly assign callbacks for a specified track component
            (eg. App.track[1]['seq'].on_midi )
        -   Remove references to grid inside track components!
        -   Make mode switching arbitrary through a single call from the App
        -   Mode will contain multiple grids and single context for display
        -   Grids should not be a state machine, but modes can
        -   Avoid dependencies on param actions
]]
function Mode:set(o)
    o.id = o.id
    o.components = o.components or {}

    --local mode = self.types[self.options[o.type]]
    local mode = nil
    
    o.set_action = o.set_action
    o.on_load = o.on_load
    o.on_midi = o.on_midi
    o.on_transport = o.on_transport
end

function Mode:register_params(o)
    --local mode = 'mode_' .. o.id .. '_'
end

-- Methods
function Mode:enable()

    if self.on_load ~= nil then
        self:on_load()
    end

    for i, component in ipairs(self.components) do
        component:enable()
    end
end

function Mode:disable()
    for i, component in ipairs(self.components) do
        component:disable()
    end
end

-- Types
Mode.options = {'Session','Drums','Keys','User'}

Mode.types = {}
Mode.types['Session'] = {
    props = {},
    set_action = function(s)
        
        s.clip_grid = Grid:new({
            name = 'All clips',
            grid_start = {x=1,y=4},
            grid_end = {x=8,y=1},
            display_start = {x=1,y=1},
            display_end = {x=8,y=4},
            offset = {x=0,y=4},
            midi = App.midi_grid,
            event = function(s,d)
               
                local alt = App.alt
                
                for i = 1, #App.track do
                    -- Process grid events for all tracks
                    if alt then App.alt = true end -- Need to keep the alt reset from toggling for subsequent events
                    App.track[i].seq:clip_grid_event(d)
                end
            end,
            set_grid = function()
                -- Clip grid is based on the state of the sequencer banks
                -- Only update the grid based on the first track
                App.track[1].seq:clip_set_grid()
            end
        })

        	
        s.mute_grid = Grid:new({
            name = 'Mute',
            grid_start = {x=1,y=1},
            grid_end = {x=4,y=32},
            display_start = {x=1,y=10},
            display_end = {x=4,y=13},
            midi = App.midi_grid,
            event = function(g,data)
                if data.state then
                    local note = g:grid_to_index(data) - 1
                    local track = s.triggers[note] or s.base

                    track.mute:grid_event(data)
                end
            end,
            set_grid = function (s)
                s:clear()
            end
        })

        s.components = {s.clip_grid, s.mute_grid}
    end,
    on_load = function(s)
        s.base = nil
        s.triggers = {}
        
        for i = 1, #App.track do
            local track = App.track[i]
            track.seq.clip_grid = App.mode[App.current_mode].components[1]

            if track.midi_in == App.current_track then
                if track.triggered then
                    s.triggers[track.trigger] = track
                else
                    s.base = track
                end

                track.mute.grid = s.mute_grid
            end
        end
 
    end,
    on_midi = function(s,data) end,
    on_transport = function(s,data) end,
    
}

Mode.types['Drums'] = {
    props = {},
    set_action = function(s,data) end,
    on_midi = function(s,data) end,
    on_transport = function(s,data) end,
    on_load = function() end,
}


Mode.types['Keys'] = {
    props = {},
    set_action = function(s)
       
        App.scale[1].grid = Grid:new({
            name = 'Scale ' .. 1,
            grid_start = {x=1,y=2},
            grid_end = {x=8,y=1},
            display_start = {x=1,y=1},
            display_end = {x=8,y=2},
            offset = {x=0,y=6},
            midi = App.midi_grid,
            event = function(s,d)
                App.scale[1]:grid_event(d)
            end,
            set_grid = function()
                App.scale[1]:set_grid()
            end
        })
    
        App.scale[2].grid = Grid:new({
            name = 'Scale ' .. 2,
            grid_start = {x=1,y=2},
            grid_end = {x=8,y=1},
            display_start = {x=1,y=1},
            display_end = {x=8,y=2},
            offset = {x=0,y=3},
            midi = App.midi_grid,
            event = function(s,d)
                App.scale[2]:grid_event(d)
            end,
            set_grid = function()
                App.scale[2]:set_grid()
            end
        })
    
        App.scale[3].grid = Grid:new({
            name = 'Scale ' .. 3,
            grid_start = {x=1,y=2},
            grid_end = {x=8,y=1},
            display_start = {x=1,y=1},
            display_end = {x=8,y=2},
            offset = {x=0,y=0},
            midi = App.midi_grid,
            event = function(s,d)
                App.scale[3]:grid_event(d)
            end,
            set_grid = function()
                App.scale[3]:set_grid()
            end
        })

        s.components = {App.scale[1].grid,App.scale[2].grid,App.scale[3].grid}

    end,
    on_midi = function(s,data) end,
    on_transport = function(s,data) end,
    on_load = function()
        print(App.current_track)
    end,
}


Mode.types['User'] = {
    props = {},
    set_action = function(s,data) end,
    on_midi = function(s,data) end,
    on_transport = function(s,data) end,
    on_load = function() end,
}


return Mode