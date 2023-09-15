local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Scale = require(path_name .. 'scale')
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
    self.scale_select = o.scale_select

    self:set(o) -- Set static variables
    self:register_params()
    
    return o
end

function Track:set(o)
    -- Set static properties here
    -- Note: most properties will be initialized by params:bang() or params:default() called in the init script
    o.note_range_upper = o.note_range_upper or 127
    o.note_range_lower = o.note_range_lower or 0
    o.triggered = o.triggered or false
end

function Track:register_params()
    -- Register the parameters
    local id = self.id
    local track = 'track_' .. self.id
    params:add_group('Track ' .. self.id, 13 )

    params:add_option(track .. '_input', 'Input Type', Input.options, 1)
    params:add_option(track .. '_output', 'Output Type', Output.options, 1)
    
    params:add_number(track .. '_midi_in', 'MIDI In', 1, 16, id)
    params:set_action(track .. '_midi_in', function(d)
        if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].midi_in = d
        end)
    
    params:add_number(track .. '_midi_out', 'MIDI Out', 1, 16, id)
    params:set_action(track .. '_midi_out', function(d)
        if App.track[id].output ~= nil then App.track[id].output:kill() end
        App.track[id].midi_out = d
        App.track[id].output = App.output[d]
        App.track[id]:build_chain()
    end)
    
    params:add_binary(track .. '_midi_thru','MIDI THRU','toggle', 0)
    params:set_action(track .. '_midi_thru',function(d)
        -- exclude trigger from other outputs
        App.track[id].midi_thru = (d>0)
    end)

    params:add_option(track .. '_voice','Voice',{'polyphonic','mono'}, 1)
    params:set_action(track .. '_voice',function(d)
        -- whether track is polyphonic or mono
        if d == 1 then
            App.track[id].mono = false
        else
            App.track[id].mono = true
        end
    end)


    params:add_number(track .. '_scale', 'Scale', 1, 16, id)
    params:set_action(track .. '_scale', function(d)
        if App.track[id].output ~= nil then App.track[id].output:kill() end
        App.track[id].scale = App.scale[d]
        App.track[id].scale_select = d 
        App.track[id]:build_chain()
    end)

    params:add_number(track .. '_trigger', 'Trigger', 0, 127, 36)
    params:set_action(track .. '_trigger', function(d)
        if App.track[id].output ~= nil then App.track[id].output:kill() end
        App.track[id].trigger = d
    end)
    
    params:add_binary(track .. '_exclude_trigger','Exclude Trigger','toggle', 0)
    params:set_action(track .. '_exclude_trigger',function(d)
        -- exclude trigger from other outputs
        App.track[id].exclude_trigger = (d>0)

        if App.track[id].midi_in  == App.track[App.current_track].midi_in and App.track[id].exclude_trigger then
            App.track[id].mute.grid = App.mute_grid
        end
        
    end)

    

    params:add_number(track .. '_note_range_lower', 'From Note', 0, 127, 0)
    params:set_action(track .. '_note_range_lower',
        function(d)
            if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].note_range_lower = d

            if d > App.track[id].note_range_upper then
                params:set(track .. '_note_range_upper', d)
            end
            
        end)

    params:add_number(track .. '_note_range_upper', 'To Note', 0, 127, 127)
    params:set_action(track .. '_note_range_upper',
        function(d)
            if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].note_range_upper = d

            if d < App.track[id].note_range_lower then
                params:set(track .. '_note_range_lower', d)
            end
            
        end)
    
   
    params:add_number(track .. '_crow_in', 'Crow In', 1, 2, 1)
    params:set_action(track .. '_crow_in', function(d) App.track[id].crow_in = d end)
    params:add_number(track .. '_crow_out', 'Crow Out', 1, 4, 1)
    params:set_action(track .. '_crow_out', function(d) App.track[id].crow_out = d end)
    

    self:register_component_set_actions(Input)
    self:register_static_components()
   -- self:register_component_set_actions(Output)
    
    
end

--[[
    Track components have a "track" property that points back to the parent track.
    In order to get these point to the right instance, I need to create the TrackComponents after 
    the track is instantiated. I'm using the params:set_action method do this as they will be 
    created when params:bang() is called during initilization.

    Now 'track' property can be optionally passed into the midi_event and transport_event functions.
    This is to accomodate track components that are shared, like Scales and Outputs. 
    ]]

function Track:register_static_components(id)
    local id = self.id
    local track = 'track_' .. self.id
    
    params:add_binary(track ..'_components', 'Set Components ' .. id, 'momentary')
    params:hide(track ..'_components')
    
    params:set_action(track .. '_components', function(d)
        local instance =  App.track[id]
        
        instance.scale_select = instance.scale_select or id
        instance.scale = App.scale[instance.scale_select]

        instance.output_select = instance.output_select or id
        instance.output = App.output[instance.output_select]


        instance.seq = Seq:new({
            id = id,
            track = App.track[id],
            -- clip_grid = Grid:new({
            --     name = 'Clip ' .. id,
            --     grid_start = {x=1,y=4},
            --     grid_end = {x=4,y=1},
            --     display_start = {x=1,y=1},
            --     display_end = {x=4,y=4},
            --     offset = {x=4,y=0},
            --     midi = App.midi_grid,
            --     event = function(s,d)
            --         instance.seq:clip_grid_event(d)
            --     end,
            --     set_grid = function()
            --         instance.seq:clip_set_grid()
            --     end
            -- }),
            -- seq_grid = Grid:new({
            --     name = 'Sequence ' .. id,
            --     grid_start = {x=1,y=128},
            --     grid_end = {x=8,y=1},
            --     display_start = {x=1,y=41},
            --     display_end = {x=8,y=48},
            --     offset = {x=0,y=0},
            --     midi = App.midi_grid,
            --     event = function(s,d)
            --         instance.seq:seq_grid_event(d)
            --     end,
            --     set_grid = function()
            --         instance.seq:seq_set_grid()
            --     end
            -- })
        })
        instance.mute = Mute:new({
            id = id,
            track = App.track[id],
            -- grid = Grid:new({
            --     name = 'Mute ' .. id,
            --     grid_start = {x=1,y=1},
            --     grid_end = {x=4,y=32},
            --     display_start = {x=1,y=10},
            --     display_end = {x=4,y=13},
            --     midi = App.midi_grid,
            --     event = function(s,d)
            --         instance.mute:grid_event(d)
            --     end,
            --     set_grid = function()
            --         instance.mute:set_grid()
            --     end
            -- })
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

        if type.set_action ~= nil then
            type.set_action(component, App.track[id])
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
    local track = self
    return function(s, input)
        local value = input
        for i, obj in ipairs(objects) do
            if obj[process_name] then
               
                value = obj[process_name](obj, value, track)
            end
        end
        return value
    end
end

function Track:build_chain()
    local components = {self.input, self.scale, self.seq, self.mute, self.output}    
    self.process_transport = self:chain_components(components, 'process_transport')
    self.process_midi = self:chain_components(components, 'process_midi')
    self.send = self:chain_components({self.mute, self.output}, 'process_midi')
    self.send_out = self:chain_components(self.output, 'process_midi')
end

return Track