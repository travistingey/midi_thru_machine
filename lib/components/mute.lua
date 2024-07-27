local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')
local Grid = require(path_name .. 'grid')


-- Mute controls events just before output

local Mute = TrackComponent:new()
Mute.__base = TrackComponent
Mute.name = 'mute'

function Mute:set(o)
	self.__base.set(self, o) -- call the base set method first   
	o.id = o.id
    o.grid = o.grid
    o.state = {}
    o.active = false
    for i= 0, 127 do
        o.state[i] = false
    end
end

function Mute:midi_event(data)
    
    if data.note ~= nil then
        local grid = self.grid      
        local note = data.note
        local state = self.state[note] 
        
        if self.track.triggered then
           state = self.active
        end

        if (not state) then
            return data
        end
        
    end
end

return Mute