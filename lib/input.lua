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

Input.options = {'midi'}
Input.params = {'midi_in','trigger','crow_in'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

Input.types['midi'] = {
    props = {'midi_in'},
    midi_event = function(s, data)
        if data.ch == s.track.midi_in then
            return data
        end
    end
}

Input.types['random'] = {
    props = {'midi_in','trigger'},
    transport_event = function(s, data)
        if data.type == 'stop' and s.last_note then
            for note in pairs(s.last_note) do
                s.track:send({type = 'note_off', note = note, ch = s.track.midi_out })
            end
        end
        return data
    end,
    midi_event = function (s, data)
        if data.type == 'note_on' then
            local old_note = data.note
            local new_note = math.random( 0,127 )

            if s.last_note then
                s.last_note[old_note] = new_note
            else
                s.last_note = {[old_note] = new_note}
            end
            
            data.note = new_note
            
            return data
        elseif data.type == 'note_off' then
            if s.last_note and s.last_note[data.note] then
                data.note = s.last_note[data.note]
                s.last_note[data.note] = nil
            end
            return data
        end

        return data
    end
}


return Input