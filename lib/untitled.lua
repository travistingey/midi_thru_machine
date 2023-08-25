local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')
local Grid = require(path_name .. 'grid')


-- 

local Scale = TrackComponent:new()
Scale.__base = TrackComponent
Scale.name = 'scale'

function Scale:set(o)
	self.__base.set(self, o) -- call the base set method first   
	o.id = o.id
    o.grid = o.grid
    
end

function Scale:midi_event(data)
    if data.note then
        
    end
end

function Scale:grid_event(data)
    if data.type == 'pad' then
    
        self.grid:refresh()
    end
end

function Scale:set_grid()
    self.grid:refresh()
end

return Scale