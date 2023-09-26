local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')

-- Output Class
-- last component in a Track's process chain that handles output to devices
local Output = TrackComponent:new()
Output.__base = TrackComponent
Output.name = 'output'

function Output:set(o)
    self.__base.set(self, o) -- call the base set method first    
    self.note_on = {}
end


function Output:process_midi(data, track)
    if data ~= nil then
        
        if data.type == 'note_on' then    
            self.note_on[data.note] = data
        elseif data.type == 'note_off' and self.note_on[data.note] ~= nil then
            self.note_on[data.note] = nil
        end

        data = self:midi_event(data, track)
        return data
    end
end

function Output:kill()
    for i,v in pairs(self.note_on) do
        local off = {
            type = 'note_off',
            note = v.note,
            vel = v.vel,
            ch = v.ch
        }

        
        App.midi_out:send(off)
    end

    self.note_on = {}
end

function Output:panic()
    clock.run(function()
    for c = 0,16 do
        for i = 0, 128 do
            

            local off = {
                note = i,
                type = 'note_off',
                ch = c,
                vel = 0
            }
            
            App.midi_out:send(off)
            clock.sync(.01)
        end
    end
end)

    self.note_on = {}
end

Output.options = {'midi','crow'}
Output.params = {'midi_out','crow_out'} -- Update this list to dynamically show/hide Track params based on Input type

Output.types = {}

Output.types['midi'] = {
    props = {'midi_out'},
    midi_event = function(s,data, track)
        if data ~= nil then
            data.ch = track.midi_out

            App.midi_out:send(data)
        end
        return data
    end
}

return Output