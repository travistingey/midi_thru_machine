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



function midi_trigger(s, data, process)
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
            
            return event
        elseif data.type == 'note_off' then
            local event = s.last_note
            local send = {}
            if event then
                for prop,v in pairs(event) do
                    send[prop] = v
                end
                send.type = 'note_off'

                return send
            end
        end
    end

end

function clock_trigger(s,data,process)

    
    if s.track.step > 0 and s.track.reset_step > 0 and App.tick % (s.track.reset_step * s.track.step) == s.track.reset_tick then
        s.track.reset_tick = App.tick % s.track.step
        s.index = 0
    end
    
    if s.track.step > 0 and App.tick % s.track.step == s.track.reset_tick then
        local event = process(data)
        if event then
            clock.run(function()
                s.track:send_input(event)

                local off = { type = 'note_off', note = event.note, vel = event.vel }

                clock.sync(math.ceil(s.track.step/2)/24)
                s.track:send_input(off)
            end)
        end
    end
end



Input.options = {'midi', 'arpeggio','random','bitwise'} -- {...'crow', 'bitwise', 'euclidean'}
Input.params = {'midi_in','trigger','crow_in','note_range_upper','note_range_lower','exclude_trigger'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

-- MIDI Input

Input.types['midi'] = {
    props = {'midi_in','note_range_upper','note_range_lower'},
    set_action = function(s,track)
        params:set('track_' .. track.id .. '_voice',1) -- polyphonic

        track.triggered = false
    end,
    midi_event = function(s, data)
        if data.ch == s.track.midi_in then
            for i = 1, #App.track do
                local track = App.track[i]
                if i ~= s.track.id and track.exclude_trigger and track.midi_in == s.track.midi_in and track.trigger == data.note then
                    return
                end
            end
            
            return data
            
        end
    end
}

-- Arpeggiator

Input.types['arpeggio'] = {
    props = {'midi_in','trigger','note_range_upper','note_range','exclude_trigger'},
    set_action = function(s, track)
        params:set('track_' .. track.id .. '_voice', 2) -- mono
        track.triggered = true
        
        if track.scale_select == 0 then
            params:set('track_' .. track.id .. '_scale',1)
        end
        

        s.index = 0
    end,
    transport_event = function(s, data)     
        if data.type == 'start' then
            s.index = 0
            s.track.reset_tick = 1
        elseif data.type == 'clock' then
            clock_trigger(s, data, function()    
                return arpeggiate(s)
            end)
                
        end
        return data
    end,
    midi_event = function(s,data)
        local event =  midi_trigger(s, data, function()
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
    local root = s.track.note_range_lower + s.track.scale.root
   
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
    props = {'midi_in','trigger','note_range_upper','note_range','exclude_trigger'},
    set_action = function(s, track)
        params:set('track_' .. track.id .. '_voice', 2) -- mono
        
        track.triggered = true

        s.index = 0
    end,
    transport_event = function(s, data)
        if data.type == 'start' then
            s.index = 0
        elseif data.type == 'clock' then

                clock_trigger(s, data, function()
                    local note = math.random( s.track.note_range_lower, s.track.note_range_upper )
                    local vel = math.random(0,127)
                    return {type = 'note_on', note = note, vel = vel }
                end)
                
        end
        return data
    end,
    midi_event = function(s,data)

        local event =  midi_trigger(s, data, function()
            local note = math.random( s.track.note_range_lower, s.track.note_range_upper )
            local vel = math.random(0,127)
            return {type = 'note_on', note = note, vel = vel }
            
        end)
        
        return event
    end
    
}

-- Bitwise Sequencer

Input.types['bitwise'] = {
    props = {'midi_in','trigger','note_range_upper','note_range','exclude_trigger'},
    set_action = function(s, track)
        params:set('track_' .. track.id .. '_voice', 2) -- mono
        track.triggered = true
        
        s.note = Bitwise:new({
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

                clock_trigger(s, data, function()
                    s.note:cycle()
                    s.vel:cycle()
                    if s.note:get().state then
                    return {type = 'note_on', note = s.note:get().value, vel = s.vel:get().value }
                    end
                end)
                
        end
        return data
    end,
    midi_event = function(s,data)

        local event =  midi_trigger(s, data, function()
            
            return { type = 'note_on', note = s.note:get().value, vel = 100 }
            
        end)
        
        return event
    end
    
}


return Input