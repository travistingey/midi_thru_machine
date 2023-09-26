
local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local ModeName = ModeComponent:new()
ModeName.__base = ModeComponent
ModeName.name = 'Mode Name'

function ModeName:set(o)
	self.__base.set(self, o) -- call the base set method first   

   o.component = 'component'
   o.register = {'on_load'} -- list events outside of transport, midi and grid events

    o.grid = Grid:new({
        name = 'Component ' .. o.track,
        grid_start = {x=1,y=128},
        grid_end = {x=8,y=1},
        display_start = o.display_start or {x=1,y=41},
        display_end = o.display_end or {x=8,y=48},
        offset = o.offset or {x=0,y=0},
        midi = App.midi_grid
    })
  
end

function ModeName:transport_event (component, data) end
function ModeName:midi_event (component, data) end
function ModeName:grid_event (component, data) end
function ModeName:set_grid (component) end
function ModeName:set_display (component) end
function ModeName:handle_button (component, e, d) end
function ModeName:handle_enc (component, e, d) end

return ModeName