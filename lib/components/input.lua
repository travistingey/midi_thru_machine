local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Bitwise = require(path_name .. 'bitwise')
local TrackComponent = require(path_name .. 'trackcomponent')

-- Input Class
-- first component in a Track's process chain that accepts midi or transport events
local Input = TrackComponent:new()
Input.__base = TrackComponent
Input.name = 'input'

function Input:set(o)
    self.__base.set(self, o) -- call the base set method first   
    for i,prop in ipairs(Input.params) do
        self[prop] = o[prop]
    end
end

function Input.set_midi_trigger(s, data, process)
    if s.track.step == 0 and data.ch == s.track.midi_in and data.note == s.track.trigger then
        if data.type == 'note_on' then
            s.track.step_count = s.track.step_count + 1

            if s.track.step_count == s.track.reset_step then
                s.track.step_count = 0
                s.index = 0
            end

            local intervals = s.track.scale.intervals
            local new_note = data.note
            local old_note = data.note
            local event = {}
            
            for prop,v in pairs(data) do
                event[prop] = v
            end

            event = process(event)
            
            if s.last_note then
                s.last_note = event
            else
                s.last_note = event
            end
            s.track:handle_note(event,'send_input')
            return event
        elseif data.type == 'note_off' then
            local event = s.last_note
            local send = {}
            if event then
                for prop,v in pairs(event) do
                    send[prop] = v
                end
                send.type = 'note_off'
                s.track:handle_note(send,'send_input')
                return send
            end
        end
    end

end

function Input.set_clock_trigger(s,data,process)

    
    if s.track.step > 0 and s.track.reset_step > 0 and App.tick % (s.track.reset_step * s.track.step) == s.track.reset_tick then
        s.track.reset_tick = App.tick % s.track.step
        s.index = 0
    end
    
    if s.track.step > 0 and App.tick % s.track.step == s.track.reset_tick then
        local event = process(data)
        if event then
            clock.run(function()
                s.track:handle_note(event,'send_input')
                s.track:send_input(event)

                local off = { type = 'note_off', note = event.note, vel = event.vel }

                clock.sync(math.ceil(s.track.step/2)/24)
                s.track:handle_note(off,'send_input')
                s.track:send_input(off)
                
            end)
        end
    end
end



Input.options = {'midi','crow' ,'arpeggio','random','bitwise'} -- {...'crow', 'bitwise', 'euclidean'}
Input.params = {'midi_in','trigger','crow_in','note_range_upper','note_range_lower','arp','note_range','step','reset_step','chance','voice','step_length'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

-- MIDI Input
-- Note: Set actions are called from the load_component function.
Input.types['midi'] = {
    props = {'midi_in', 'note_range_upper','note_range_lower'},
    set_action = function(s,track)
        -- params:set('track_' .. track.id .. '_voice',1) -- polyphonic
        track.triggered = false
    end,
    midi_event = function(s, data, track)
        if data.ch == track.midi_in then
            
            -- Exclude notes that are being handled by triggered tracks
            for i = 1, #App.track do 
                local other = App.track[i]
                if track.id ~= other.id and other.triggered and other.trigger == data.note then
                    return
                end
            end

            track:handle_note(data,'send_input')
            
            return data
            
        end
    end
}

Input.set_trigger = function (s, track)
    params:set('track_' .. track.id .. '_voice', 2) -- mono
    params:set('track_' .. track.id .. '_note_range_lower', 60) -- mono
    track.triggered = true
    s.index = 0
end

-- Crow Input
-- crow.send('input[1].query()') will query and save values to App.crow_in[1].volts
Input.types['crow'] = {
    props = {'midi_in','trigger'},
    set_action = function(s, track)
        track:kill()
            
            track.crow_out = d

            if track.output_type == 'crow' then
                track.output = App.crow_out[d]
                track:build_chain()
            end
            
            if App.mode[App.current_mode] then
                App.mode[App.current_mode]:enable()
            end

        Input.set_trigger(s,track)
       
    end,
    transport_event = function(s, data)
        if data.type == 'start' then
            s.index = 0
        elseif data.type == 'clock' then

                Input.set_clock_trigger(s, data, function()
                    crow.send('input['.. s.track.crow_in ..'].query()')
                    local note = math.floor(App.crow_in[ s.track.crow_in] * 12) + 60
                    local vel = 100
                    return {type = 'note_on', note = note, vel = vel }
                end)
                
        end
        return data
    end,
    midi_event = function(s,data)

        local event =  Input.set_midi_trigger(s, data, function()
            crow.send('input['.. s.track.crow_in ..'].query()')
            local note = math.floor(App.crow.input[ s.track.crow_in] * 12) + 60
            local vel = 100
            return {type = 'note_on', note = note, vel = vel }
            
        end)
        
        s.track:handle_note(event,'send_input')
        return event
    end
    
}



-- Arpeggiator

Input.types['arpeggio'] = {
    props = {'midi_in','trigger','note_range_upper','note_range'},
    set_action = function(s, track)
        Input.set_trigger(s,track)
        
        if track.scale_select == 0 then
            params:set('track_' .. track.id .. '_scale_select',1)
        end       
    end,
    transport_event = function(s, data)     
        if data.type == 'start' then
            s.index = 0
            s.track.reset_tick = 1
        elseif data.type == 'clock' then
            Input.set_clock_trigger(s, data, function()    
                return arpeggiate(s)
            end)
                
        end
        return data
    end,
    midi_event = function(s,data)
        local event =  Input.set_midi_trigger(s, data, function()
            return arpeggiate(s)
        end)
        
        return event
    end
    
}

function arpeggiate (s, data)
    local intervals = s.track.scale.intervals
    local note

    if #intervals == 0 then 
        intervals = {0,1,2,3,4,5,6,7,8,9,10,11}
    end
    
    local range = params:get('track_' .. s.track.id .. '_note_range') * #intervals
    local root = s.track.note_range_lower
   
    if s.track.arp == 'up' then                        
        s.index = util.wrap(s.index + 1, 1,range)        
        local octave = (math.ceil( s.index / #intervals) - 1) * 12
        note = root + intervals[(s.index-1) % #intervals + 1 ] + octave
    elseif s.track.arp == 'down' then
        s.index = util.wrap(s.index + 1, 1, range)
        local select = (#intervals + 1) - ((s.index-1) % #intervals + 1)
        local octave = (math.floor( (range -  (s.index)) / #intervals) ) * 12
        note = root + intervals[select] + octave
    elseif s.track.arp == 'up down' then
        s.index = util.wrap(s.index + 1, 1,range * 2 - 2) 

        if s.index <= range then       
            local octave = (math.ceil( s.index / #intervals) - 1) * 12
            note = root + intervals[(s.index-1) % #intervals + 1 ] + octave
        else
            local select = (#intervals + 1) - (s.index % #intervals + 1)
            local octave = (math.ceil( (range - (s.index - range )) / #intervals) - 1) * 12
            note = root + intervals[select] + octave
        end
    elseif s.track.arp == 'down up' then
        s.index = util.wrap(s.index + 1, 1,range * 2 - 2) 

        if s.index <= range then       
            local select = (#intervals + 1) - ((s.index-1) % #intervals + 1)
            local octave = (math.floor( (range -  (s.index)) / #intervals) ) * 12
            note = root + intervals[select] + octave

        else
            local octave = (math.floor( s.index / #intervals) - 2) * 12
            note = root + intervals[(s.index-range) % #intervals + 1 ] + octave
        end
        
    elseif s.track.arp == 'converge' then
        
        s.index = util.wrap(s.index + 1, 1, range)

        local index = 1
        
        if s.index % 2 == 0 then       
            index = range - (s.index - (math.ceil(s.index/2) + 1) )
        else
            index = s.index - (math.ceil(s.index/2) - 1)
        end
        
        local octave = (math.ceil( index / #intervals) - 1) * 12
        note = root + intervals[(index - 1) % #intervals + 1] + octave

    elseif s.track.arp == 'diverge' then
        
        s.index = util.wrap(s.index + 1, 1, range)
        
        local index = 1
        
        if s.index % 2 == 0 then       
            index = range - (s.index - math.ceil(s.index/2) + math.floor(range/2) - 1)
        else
            index = s.index - math.ceil(s.index/2) + math.floor(range/2) + 1
        end

        local octave = (math.ceil( index / #intervals) - 1) * 12
        note = root + intervals[(index - 1) % #intervals + 1] + octave

    end
    
    return {type = 'note_on', note = note, vel = 100 }
end

-- Random Notes

Input.types['random'] = {
    props = {'midi_in','trigger','note_range_upper','note_range'},
    set_action = function(s, track)
       Input.set_trigger(s,track)
    end,
    transport_event = function(s, data)
        if data.type == 'start' then
            s.index = 0
        elseif data.type == 'clock' then

                Input.set_clock_trigger(s, data, function()
                    local note = math.random( s.track.note_range_lower, s.track.note_range_upper )
                    local vel = math.random(0,127)
                    return {type = 'note_on', note = note, vel = vel }
                end)
                
        end
        return data
    end,
    midi_event = function(s,data)

        local event =  Input.set_midi_trigger(s, data, function()
            local note = math.random( s.track.note_range_lower, s.track.note_range_upper )
            local vel = math.random(0,127)
            return {type = 'note_on', note = note, vel = vel }
            
        end)
        
        return event
    end
    
}

-- Bitwise Sequencer

Input.types['bitwise'] = {
    props = {'midi_in','trigger','note_range_upper','note_range'},
    set_action = function(s, track)
        Input.set_trigger(s,track)
        track.chance = params:get('track_' .. track.id .. '_chance')
        track.step_length = params:get('track_' .. track.id .. '_step_length')

        s.note = Bitwise:new({
            chance = track.chance,
            format = function(value) 
                return util.wrap(math.floor( value * 127 ), track.note_range_lower, track.note_range_upper)
            end
        })
        
        s.vel = Bitwise:new({
            format = function(value)
                return math.floor( value * 127 )
            end
        })
    end,
    transport_event = function(s, data)
        if data.type == 'start' then
            s.index = 0
        elseif data.type == 'clock' then

                Input.set_clock_trigger(s, data, function()

                    s.note.chance = s.track.chance
                    s.vel.chance = s.track.chance

                    s.note.length = s.track.step_length
                    s.vel.length = s.track.step_length

                    s.index = util.wrap(s.index + 1,1,s.track.step_length)
                    
                    s.note:mutate(s.index)
                    s.vel:mutate(s.index)
                    
                    if s.note:get(s.index).state then
                        return {type = 'note_on', note = s.note:get(s.index).value, vel = s.vel:get(s.index).value }
                    end
                end)
                
        end
        return data
    end,
    midi_event = function(s,data)

        local event =  Input.set_midi_trigger(s, data, function()
            s.note.chance = s.track.chance
            s.vel.chance = s.track.chance

            s.note.length = s.track.step_length
            s.vel.length = s.track.step_length

            s.index = util.wrap(s.index + 1,1,s.track.step_length)
            s.note:mutate(s.index)
            s.vel:mutate(s.index)

            local send = { type = 'note_on', note = s.note:get(s.index).value, vel = 100 }
           
            
            return send
            
        end)
        
        return event
    end
    
}


return Input