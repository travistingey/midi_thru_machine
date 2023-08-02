--- Base Class
local TrackComponent = {}

function TrackComponent:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    -- common functionality here
    self:set(o)

    return o
end

function TrackComponent:set(o)
    -- Set up default methods if none are provided
    self.transport_event = o.transport_event or function(s,data) return data end
    self.midi_event = o.midi_event or function(s,data) return data end   
    
    o.on_transport = o.on_transport or function(s,data) return data end
	o.on_midi = o.on_midi or function(s,data) return data end
	
end

function TrackComponent:process_transport(data)
    if data ~= nil then
        data = self:transport_event(data)
        self:on_transport(data)
        return data
    end
end

function TrackComponent:process_midi(data)
    if data ~= nil then
        data = self:midi_event(data)
        self:on_midi(data)
        return data
    end
end

return TrackComponent