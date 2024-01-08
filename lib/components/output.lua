local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')

-- Output Class
-- last component in a Track's process chain that handles output to devices
local Output = TrackComponent:new()
Output.__base = TrackComponent
Output.name = 'output'

function Output:set(o)
    self.__base.set(self, o) -- call the base set method first    
end

Output.options = {'midi','crow'}
Output.params = {'midi_out','crow_out','slew'} -- Update this list to dynamically show/hide Track params based on Input type

Output.types = {}

Output.types['midi'] = {
    props = {'midi_out'},
    set_action = function(s,track)
       
        if track.midi_out == 0 then
            track.active = false
        else
            track.active = true
        end

        -- if App.mode[App.current_mode] then
        --     App.mode[App.current_mode]:enable()
        -- end
    end,
    midi_event = function(s,data, track)
        if data ~= nil then
            local send = {}

            for i,v in pairs(data) do
                send[i] = v
            end
            
            send.ch = track.midi_out

            -- App.midi_out:send(send)
        end
        return data
    end
}

Output.types['crow'] = {
    props = {'crow_out'},
    set_action = function(s,track)
        
        track.active = true

        if track.output ~= nil then track.output:kill() end
            
        track.crow_out = d
        track.active = true

        -- if track.output_type == 'crow' then
        --     track.output = App.crow_out[d]
        --     track:build_chain()
        -- end
        
        -- if App.mode[App.current_mode] then
        --     App.mode[App.current_mode]:enable()
        -- end
    end,
    midi_event = function(s,data, track)
        if data ~= nil and data.note ~= nil then
            local volts = (data.note - track.note_range_lower) / 12
            local voct = 1
            local gate = 2

            if track.crow_out == 1 then
                voct = 1
                gate = 2
            elseif track.crow_out == 2 then
                voct = 3
                gate = 4
            end

            crow.output[voct].action = '{to(dyn{note = '.. volts .. '},dyn{slew = ' .. track.slew .. '})}'
            crow.output[voct].dyn.note = volts    
            crow.send('output[' .. voct .. ']()')

            if data.type == 'note_on' then
                crow.output[gate].volts = 5
            elseif data.type == 'note_off' then
                crow.output[gate].volts = 0
            end

        end
        return data
    end

}

return Output