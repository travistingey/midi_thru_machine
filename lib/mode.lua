local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Output = require(path_name .. 'output')

-- Define a new class for Mode
local Mode = {}

-- Constructor
function Mode:new(o)
    o = o or {}

    if o.id == nil then
        error("Mode:new() missing required 'id' parameter.")
    end

    if o.grid == nil then
        error("Mode:new() missing required 'grid' parameter.")
    end
    
    setmetatable(o, self)
    self.__index = self
    self.id = o.id
    self:set(o) -- Set static variables

    self.grid = o.grid 

    return o
end

function Mode:set(o)
    -- Set static properties here
    
    self.transport_event = o.transport_event or function(s,data) end
    self.midi_event = o.midi_event or function(s,data) end
    self.grid_event = o.grid_event or function(s,data) end 
    self.enable = o.on_enable or function(s,data) end
    self.enabled = o.enabled or false
end

function Mode:process_transport(data)
    if self.enabled then
        self:transport_event(data)
    end
end

function Mode:process_midi(data)
    if self.enabled then
        self:midi_event(data)
    end    
end

function Mode:process_grid(msg)
    if self.enabled then
        self.grid:process(msg)
    end
end

return Mode