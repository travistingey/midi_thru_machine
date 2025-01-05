local path_name = 'Foobar/lib/'
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Grid = require(path_name .. 'grid')


-- Mute controls events just before output

local Mute = {}
Mute.name = 'mute'
Mute.__index = Mute
setmetatable(Mute,{ __index = TrackComponent })

function Mute:new(o)
    o = o or {}
    setmetatable(o, self)
    TrackComponent.set(o,o)
    o:set(o)
    return o
end

function Mute:set(o)
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