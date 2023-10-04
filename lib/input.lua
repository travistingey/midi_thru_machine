local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
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

Input.options = {'midi', 'arpeggio' } -- {...'crow', 'bitwise', 'euclidean'}
Input.params = {'midi_in','trigger','crow_in','note_range_upper','note_range_lower','exclude_trigger'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

Input.types['midi'] = {
    props = {'midi_in','note_range_upper','note_range_lower'},
    set_action = function(s,track)
        params:set('track_' .. track.id .. '_voice',1) -- polyphonic
        params:set('track_' .. track.id .. '_note_range_upper', 127)
        params:set('track_' .. track.id .. '_note_range_lower', 0)
        params:set('track_' .. track.id .. '_scale', 0)
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


Input.types['arpeggio'] = {
    props = {'midi_in','trigger','note_range_upper','note_range_lower','exclude_trigger'},
    set_action = function(s,track)
        params:set('track_' .. track.id .. '_voice', 2) -- mono
        params:set('track_' .. track.id .. '_note_range_lower', 60)
        params:set('track_' .. track.id .. '_note_range', 1)
        params:set('track_' .. track.id .. '_exclude_trigger', 1)
        params:set('track_' .. track.id .. '_note_range', 1)
        params:set('track_' .. track.id .. '_arp',1)
        
        if track.scale_select == 0 then
            params:set('track_' .. track.id .. '_scale',1)
        end
        track.triggered = true

        
        s.arp = 'up'
        s.index = 0
    end,
    transport_event = function(s, data)
        if data.type == 'start' then
            s.index = 0
        elseif data.type == 'stop' and s.last_note then
            for note in pairs(s.last_note) do
                s.track:send({type = 'note_off', note = note })
            end
        end
        return data
    end,
    midi_event = function (s, data)
       
        if data.ch == s.track.midi_in and data.note == s.track.trigger then
            if data.type == 'note_on' then
                local intervals = s.track.scale.intervals
                local new_note = data.note
                local old_note = data.note
                
                if #intervals == 0 then 
                    intervals = {0,1,2,3,4,5,6,7,8,9,10,11}
                end
                
                local range = params:get('track_' .. s.track.id .. '_note_range') * #intervals
                local octave = math.floor(s.index / #intervals)


                if s.arp == 'up' then
                    s.index = util.wrap(s.index + 1, 1,range)
                    new_note = s.track.note_range_lower + s.track.scale.root + intervals[(s.index-1) % #intervals + 1 ] + (octave * 12)
                elseif s.arp == 'down' then
                    s.index = util.wrap(s.index - 1, 1, range)
                    new_note = s.track.note_range_lower + s.track.scale.root + intervals[(s.index-1) % #intervals + 1 ]  + (octave * 12)
                elseif s.arp == 'random' then
                    new_note = math.random( s.track.note_range_lower, s.track.note_range_upper )
                else 
                    return
                end
                               
                if s.last_note then
                    s.last_note[old_note] = new_note
                else
                    s.last_note = {[old_note] = new_note}
                end

                local event = {}

                for prop,v in pairs(data) do
                    event[prop] = v
                end

                event.note = new_note
                
                return event

            elseif data.type == 'note_off' then
                local event = {type = 'note_off'}
                if s.last_note and s.last_note[data.note] then
                    event.note = s.last_note[data.note]
                    s.last_note[data.note] = nil
                end
                return event
            end

            return data -- everything else
        end
    end
}

return Input