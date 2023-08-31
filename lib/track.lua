local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Mute = require(path_name .. 'mute')
local Grid = require(path_name .. 'grid')
local Output = require(path_name .. 'output')

-- Define a new class for Track
local Track = {}

-- Constructor
function Track:new(o)
    o = o or {}

    if o.id == nil then
        error("Track:new() missing required 'id' parameter.")
    end
    
    setmetatable(o, self)
    self.__index = self

    self.id = o.id

    self:set(o) -- Set static variables
    self:register_params()
    
    return o
end

function Track:set(o)
    -- Set static properties here
end

function Track:register_params()
    -- Register the parameters
    local id = self.id
    local track = 'track_' .. self.id
    params:add_group('Track ' .. self.id, 7 )
    params:add_option(track .. '_input', 'Input Type', Input.options, 1)
    params:add_option(track .. '_output', 'Output Type', Output.options, 1)
    params:add_number(track .. '_midi_in', 'MIDI In', 1, 16, id)
    params:set_action(track .. '_midi_in', function(d)
        App.track[id].midi_in = d end)
    params:add_number(track .. '_midi_out', 'MIDI Out', 1, 16, id)
    params:set_action(track .. '_midi_out', function(d) App.track[id].midi_out = d end)
    params:add_number(track .. '_trigger', 'Trigger', 0, 127, 36)
    params:set_action(track .. '_trigger', function(d) App.track[id].trigger = d end)
    params:add_number(track .. '_crow_in', 'Crow In', 1, 2, 1)
    params:set_action(track .. '_crow_in', function(d) App.track[id].crow_in = d end)
    params:add_number(track .. '_crow_out', 'Crow Out', 1, 4, 1)
    params:set_action(track .. '_crow_out', function(d) App.track[id].crow_out = d end)
    

    self:register_component_set_actions(Input)
    self:register_static_components()
    self:register_component_set_actions(Output)
    
    
end

--[[
    Track components have a "track" property that points back to the parent track.
    In order to get these point to the right instance, I need to create the TrackComponents after 
    the track is instantiated. I'm using the params:set_action method do this as they will be 
    created when params:bang() is called during initilization.
    ]]

function Track:register_static_components(id)
    local id = self.id
    local track = 'track_' .. self.id
    
    params:add_binary(track ..'_components', 'Set Components ' .. id, 'momentary')
    params:hide(track ..'_components')
    
    params:set_action(track .. '_components', function(d)
        local instance =  App.track[id]
        instance.seq = Seq:new({
            id = id,
            track = App.track[id],
            clip_grid = Grid:new({
                grid_start = {x=1,y=4},
                grid_end = {x=4,y=1},
                display_start = {x=1,y=1},
                display_end = {x=4,y=4},
                offset = {x=4,y=0},
                midi = App.midi_grid,
                event = function(s,d)
                    instance.seq:clip_grid_event(d)
                end,
                set_grid = function()
                    instance.seq:set_clip_grid()
                end
            }),
            seq_grid = Grid:new({
                grid_start = {x=1,y=128},
                grid_end = {x=8,y=1},
                display_start = {x=1,y=41},
                display_end = {x=8,y=44},
                offset = {x=0,y=4},
                midi = App.midi_grid,
                event = function(s,d)
                    instance.seq:seq_grid_event(d)
                end,
                set_grid = function()
                    instance.seq:set_seq_grid()
                end
            })
        })
        instance.mute = Mute:new({
            id = id,
            track = App.track[id],
            grid = Grid:new({
                grid_start = {x=1,y=1},
                grid_end = {x=4,y=32},
                display_start = {x=1,y=10},
                display_end = {x=4,y=13},
                midi = App.midi_grid,
                event = function(s,d)
                    instance.mute:grid_event(d)
                end,
                set_grid = function()
                    instance.mute:set_grid()
                end
            })
        })
        instance:build_chain()
    end)
    
end

function Track:register_component_set_actions(component)
    local track = 'track_' .. self.id
    local id = self.id
    -- Hide dynamic params and wait for set action
    for i, value in ipairs(component.params) do
        params:hide(track .. '_' .. value)
    end
   
    -- Set the action for the input parameter
    params:set_action(track .. '_' .. component.name, function(i)
        local option = component.options[i]
        local type = component.types[option]
        
        for i, value in ipairs(component.params) do
            params:hide(track .. '_' .. value)
        end

        if type ~= nil then
            local props = {}
        
            for i, prop in ipairs(type.props) do
                params:show(track .. '_' .. prop)
                props[prop] = params:get(track .. '_' .. prop)
            end

            if type.transport_event ~= nil then
                props.transport_event = type.transport_event
            end

            if type.midi_event ~= nil then
                props.midi_event = type.midi_event
            end

            if type.grid_event ~= nil then
                props.grid_event = type.grid_event
            end

            props.track = App.track[id]
            
            local instance =  App.track[id]
            instance[component.name] = component:new(props)
            instance:build_chain()

        else
            error('Component type \'' .. option .. '\' is not defined in the class.')
        end      

        _menu.rebuild_params() -- Refresh params menu

    end)
end

-- function Track:set_params()
--     -- Set the initial value for the input parameter
--     params:set('track_' .. self.id .. '_input', self.input)
-- end

-- function Track:get_param(param_name)
--     return params:get('track_' .. self.id .. '_' .. param_name)
-- end

function Track:chain_components(objects, process_name)
    return function(s, input)
        local value = input
        for i, obj in ipairs(objects) do
            if obj[process_name] then
               
                value = obj[process_name](obj, value)
            end
        end
        return value
    end
end

function Track:build_chain()
    local components = {self.input, self.seq, self.mute, self.output}    
    self.process_transport = self:chain_components(components, 'process_transport')
    self.process_midi = self:chain_components(components, 'process_midi')
    self.send = self:chain_components({self.mute, self.output}, 'process_midi')
end

return Track