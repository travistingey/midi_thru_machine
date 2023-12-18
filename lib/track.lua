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
   

    self:set(o) -- Set static variables
    
    
    return o
end

function Track:set(o)
    -- Set static properties here
    -- Note: most properties will be initialized by params:bang() or params:default() called in the init script
    o.active = o.active or false
    o.note_range_lower = o.note_range_lower or 0
    o.note_range_upper = o.note_range_upper or 127
    o.note_range = o.note_range or 2
    o.triggered = o.triggered or false
    o.midi_in = o.midi_in or 1
    o.midi_out = o.midi_out or 1
    o.midi_thru = o.midi_thru or false
    o.mono = o.mono or false
    o.exclude_trigger = o.exclude_trigger or false
    self.scale_select = o.scale_select or 0
end

function Track:register_params(id)
    -- Register the parameters
    
    local track = 'track_' .. id
    params:add_group('Track ' .. id, 19 )

    params:add_option(track .. '_input', 'Input Type', Input.options, 1)
    params:set_action(track .. '_input',function(d)
        if App.mode[App.current_mode] then
            App.mode[App.current_mode]:enable()
        end
    end)
    
    params:add_option(track .. '_output', 'Output Type', Output.options, 1)
    params:set_action(track .. '_output',function(d)
        if App.mode[App.current_mode] then
            App.mode[App.current_mode]:enable()
        end
    end)

    params:add_number(track .. '_midi_in', 'MIDI In', 0, 16, id, function(param)
        local ch = param:get()
        if ch == 0 then 
           return 'off'
        else
           return ch
        end
    end)
    
    params:set_action(track .. '_midi_in', function(d)
        if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].midi_in = d

            if App.mode[App.current_mode] then
                App.mode[App.current_mode]:enable()
            end
        end
    )
    
    params:add_number(track .. '_midi_out', 'MIDI Out', 0, 16, 0, function(param)
        local ch = param:get()
        if ch == 0 then 
           return 'off'
        else
           return ch
        end
    end)

    params:set_action(track .. '_midi_out', function(d)
        if d == 0 then
            App.track[id].active = false
        else
            App.track[id].active = true
        end

        if App.track[id].output ~= nil then App.track[id].output:kill() end
        App.track[id].midi_out = d
        App.track[id].output = App.output[d]
        App.track[id]:build_chain()
       
        if App.mode[App.current_mode] then
            App.mode[App.current_mode]:enable()
        end
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


    local arp_options = {'up','down','up down', 'down up', 'converge', 'diverge'}
    params:add_option(track .. '_arp','Arpeggio',arp_options, 1)
    params:set_action(track .. '_arp',function(d)
        App.track[id].arp = arp_options[d]
    end)

    local step_options = {'midi trig','1/48','1/32', '1/32t', '1/16', '1/16t', '1/16d','1/8', '1/8t','1/8d','1/4','1/4t','1/4d','1/2','1','2','4','8','16'}
    local step_values =  {0,2,3,4,6,8,9,12,16,18,24,32,36,48,96,192,384,768, 1536}
    params:add_option(track .. '_step','Step',step_options, 1)
    params:set_action(track .. '_step',function(d)
        App.track[id].step = step_values[d]
        App.track[id].reset_tick = 1
        App.track[id].step_count = 0
    end)

    params:add_number(track .. '_reset','Reset',0,64,0, function(param) 
        local v = param:get()
        if v == 0 then
            return 'off'
        elseif v == 1 then
            return '1 step'
        else
            return v .. ' steps'
        end
    end)

    params:set_action(track .. '_reset',function(d)
        App.track[id].reset_step = d
        App.track[id].reset_tick = 1
        App.track[id].step_count = 0
    end)

    local chance_spec = controlspec.UNIPOLAR:copy()
    chance_spec.default = 0.5

    params:add_control(track .. '_chance', 'Chance', chance_spec)
    params:set_action(track .. '_chance', function(d)
        App.track[id].chance = d
    end)

    params:add_number(track .. '_scale', 'Scale', 0, 3, 0,function(param)
        local ch = param:get()
        if ch == 0 then 
           return 'off'
        else
           return ch
        end
    end)
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

        if App.mode[App.current_mode] then
            App.mode[App.current_mode]:enable()
        end

    end)

    params:add_number(track .. '_step_length', 'Step Length', 1, 16, 16)
    params:set_action(track .. '_step_length', function(d)
        App.track[id].step_length = d
    end)
    
    params:add_binary(track .. '_exclude_trigger','Exclude Trigger','toggle', 0)
    params:set_action(track .. '_exclude_trigger',function(d)
        -- exclude trigger from other outputs
        App.track[id].exclude_trigger = (d>0)

        if App.track[id].midi_in  == App.track[App.current_track].midi_in and App.track[id].exclude_trigger then
            App.track[id].mute.grid = App.mute_grid
        end

        if App.mode[App.current_mode] then
            App.mode[App.current_mode]:enable()
        end
        
    end)

    params:add_number(track .. '_note_range_lower', 'From Note', 0, 127, 0)
    params:set_action(track .. '_note_range_lower',
        function(d)
            if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].note_range_lower = d

            params:set(track .. '_note_range_upper', util.clamp(params:get(track .. '_note_range') * 12 + d,0,127))
            
        end)

    params:add_number(track .. '_note_range_upper', 'To Note', 0, 127, 127)
    params:set_action(track .. '_note_range_upper',
        function(d)
            if App.track[id].output ~= nil then App.track[id].output:kill() end
            App.track[id].note_range_upper = d

            params:set(track .. '_note_range', math.ceil((d - App.track[id].note_range_lower) / 12))

            if d < App.track[id].note_range_lower then
                params:set(track .. '_note_range_lower', d)
            end
            
        end)
    
    params:hide(track .. '_note_range_upper')

        params:add_number(track .. '_note_range', 'Octaves', 1, 11, 2)
        params:set_action(track .. '_note_range', function(d)
            params:set(track .. '_note_range_upper', util.clamp(d * 12 + App.track[id].note_range_lower,0,127))
        end)
        
   
    params:add_number(track .. '_crow_in', 'Crow In', 1, 2, 1)
    params:set_action(track .. '_crow_in', function(d) App.track[id].crow_in = d end)
    params:add_number(track .. '_crow_out', 'Crow Out', 1, 4, 1)
    params:set_action(track .. '_crow_out', function(d) App.track[id].crow_out = d end)
    

    self:register_component_set_actions(Input,id)
    self:register_static_components(id)

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
    local track = 'track_' .. id
    
    params:add_binary(track ..'_components', 'Set Components ' .. id, 'momentary')
    params:hide(track ..'_components')
    
    params:set_action(track .. '_components', function(d)
        local instance =  App.track[id]
        
        instance.scale_select = instance.scale_select or 0
        instance.scale = App.scale[instance.scale_select]

        instance.output_select = instance.output_select or id
        instance.output = App.output[instance.output_select]


        instance.seq = Seq:new({
            id = id,
            track = App.track[id],
        })
        instance.mute = Mute:new({
            id = id,
            track = App.track[id],
        })
        instance:build_chain()
    end)
    
end

function Track:register_component_set_actions(component, id)
    local track = 'track_' .. id
    local id = id
   
    -- Set the action for the input parameter
    params:set_action(track .. '_' .. component.name, function(i)
        local option = component.options[i]
        local type = component.types[option]

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

function Track:chain_components(objects, process_name)
    local track = self
    return function(s, input)
        if track.active then
            local value = input
            for i, obj in ipairs(objects) do
                if obj[process_name] then
                
                    value = obj[process_name](obj, value, track)
                end
            end
            return value
        end
    end
end

function Track:build_chain()
    local pre_scale =  {self.input, self.seq, self.scale, self.mute, self.output}     
    local post_scale = {self.input, self.scale, self.seq, self.mute, self.output} 
    
    local send_input = {self.scale, self.seq, self.mute, self.output} 
    local send =  {self.mute, self.output}
    self.process_transport = self:chain_components(post_scale, 'process_transport')
    self.process_midi = self:chain_components(post_scale, 'process_midi')
    self.send = self:chain_components(send, 'process_midi')
    self.send_input = self:chain_components(send_input, 'process_midi')
    self.send_out = self:chain_components(self.output, 'process_midi')
end

return Track