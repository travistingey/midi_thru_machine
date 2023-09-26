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

Input.options = {'midi', 'random' } -- {...'crow', 'bitwise', 'euclidean'}
Input.params = {'midi_in','trigger','crow_in','note_range_upper','note_range_lower','exclude_trigger'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

Input.types['midi'] = {
    props = {'midi_in','note_range_upper','note_range_lower'},
    set_action = function(s,track)
        params:set('track_' .. track.id .. '_voice',1) -- polyphonic
        params:set('track_' .. track.id .. '_note_range_upper', 0)
        params:set('track_' .. track.id .. '_note_range_lower', 127)

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

-- Make app store trigger

Input.types['random'] = {
    props = {'midi_in','trigger','note_range_upper','note_range_lower','exclude_trigger'},
    set_action = function(s,track)
        params:set('track_' .. track.id .. '_voice',2) -- mono
        params:set('track_' .. track.id .. '_note_range_lower', 60)
        params:set('track_' .. track.id .. '_note_range_upper', 84)
        params:set('track_' .. track.id .. '_exclude_trigger', 1)
        track.triggered = true

    end,
    transport_event = function(s, data)
        if data.type == 'stop' and s.last_note then
            for note in pairs(s.last_note) do
                s.track:send({type = 'note_off', note = note })
            end
        end
        return data
    end,
    midi_event = function (s, data)
       
        if data.ch == s.track.midi_in and data.note == s.track.trigger then
            if data.type == 'note_on' then
                
                local old_note = data.note
                local new_note = math.random( s.track.note_range_lower, s.track.note_range_upper )

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

            return data
        end
    end
}

return Input