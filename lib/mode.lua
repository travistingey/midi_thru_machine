local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Output = require(path_name .. 'output')
local Grid = require(path_name .. 'grid')

-- Define a new class for Mode
local Mode = {}

-- Constructor

function Mode:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self:set(o)
    self:register_params(o)
    return o
end

function Mode:set(o)
    o.id = o.id or #App.mode + 1 or 1
    o.components = o.components or {}

    o.set_action = o.set_action
    o.on_load = o.on_load
    o.on_midi = o.on_midi
    o.on_transport = o.on_transport

    -- Create the modes
	o.grid = Grid:new({
		grid_start = {x=1,y=1},
		grid_end = {x=9,y=9},
		display_start = {x=1,y=1},
		display_end = {x=9,y=9},
		midi = App.midi_grid,
		active = false,
        
        process = function(s,msg)
        
        for i,g in ipairs(o.grid.subgrids) do
					g.active = true
					g:process(msg)
				end
            

            for i,c in ipairs(o.components) do
                c.grid:process(msg)
            end
        end
	})

    o.arrow_pads = o.grid:subgrid({
        name = 'arrows pads',
        grid_start = {x=1,y=9},
        grid_end = {x=4,y=9},
        event = function(s,data)
            local mode = App.mode[App.current_mode]

            for i,component in ipairs(mode.components) do
                component.grid:event(data)
            end
            
            if o.on_arrow ~= nil then
              o:on_arrow(data)
            end
            
        end})

	o.row_pads = o.grid:subgrid({
        name = 'row pads',
        grid_start = {x=9,y=8},
        grid_end = {x=9,y=2},
        event = function(s,data)
            local mode = App.mode[App.current_mode]

            for i,component in ipairs(mode.components) do
                component.grid:event(data)
            end
            
            if o.on_row ~= nil then
              o:on_row(data)
            end
        end
    })

	

	-- Alt pad
	o.alt_pad = o.grid:subgrid({
        name = 'alt pad',
        grid_start = {x=9,y=1},
        grid_end = {x=9,y=1}, 
        event = function(s,data)
            if data.toggled then
                s.led[data.x][data.y] = 1
            else
                s.led[data.x][data.y] = 0
            end
            self.alt = data.toggled
            s:refresh('alt event')
            
            if o.on_row ~= nil then
              o:on_alt(data)
            end
            
        end,
        on_reset = function(s)
            self.alt = false
        end
    } )

    for i,c in ipairs(o.components) do
        self:register_component(c)
    end

end

function Mode:register_component(c)
    if self.components == nil then self.components = {} end
    self.components[ #self.components + 1 ] = c
    
    
end

function Mode:register_params(o)
    --local mode = 'mode_' .. o.id .. '_'
end

-- Methods
function Mode:enable()

    if self.on_load ~= nil then
        self:on_load()
    end

    self.grid:enable()

    for i, component in ipairs(self.components) do
        component.mode = App.mode[App.current_mode]
        component:enable()
    end
end

function Mode:disable()
    
    self.grid:disable()

    for i, component in ipairs(self.components) do
        component:disable()
        component.mode = nil
    end
end


return Mode