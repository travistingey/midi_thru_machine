-- Base Class
local ModeComponent = {}

function ModeComponent:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self:set(o)
    return o
end

function ModeComponent:set(o)

    self.grid = o.grid -- subgrid of main grid
    
    self.transport_event = o.transport_event or function(data) end
    self.midi_event = o.midi_event or function(data) end
    self.grid_event = o.grid_event or function(data) end   
end

function ModeComponent:process_midi(data)
    if data.type == 'clock' or data.type == 'start' or data.type == 'stop' or data.type == 'continue' then
        self:transport_event(data)
    else
        self:midi_event(data)
    end
end

function ModeComponent:process_grid(data)
    self.grid.event = self.grid_event(data)
end

return ModeComponent