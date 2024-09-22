local path_name = 'Foobar/lib/'

local utilities = require(path_name .. 'utilities')
local Input = require(path_name .. 'components/input')
local Seq = require(path_name .. 'components/seq')
local Output = require(path_name .. 'components/output')
local Grid = require(path_name .. 'grid')

-- Define a new class for Mode
local Mode = {}

-- Constructor

function Mode:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.set(o,o)
    self.register_params(o,o)
    return o
end

function Mode:set(o)
    self.id = o.id
    self.components = o.components or {}

    self.set_action = o.set_action
    self.on_load = o.on_load
    self.on_midi = o.on_midi
    self.on_transport = o.on_transport

    self.timeout = 5
    self.interupt = false
    self.context = o.context or {}
    self.default = {}

    for binding,func in pairs(App.default) do
       if self.context[binding] then
            self.default[binding] = self.context[binding]
        else
            self.default[binding] = func
            self.context[binding] = func
       end
    end

    self.layer = o.layer or {}

    self.layer[0] = App.default.screen

    -- Create the modes
	self.grid = Grid:new({
		grid_start = {x=1,y=1},
		grid_end = {x=9,y=9},
		display_start = {x=1,y=1},
		display_end = {x=9,y=9},
		midi = App.midi_grid,
		active = false,
        
        process = function(s,msg)
            for i,g in ipairs(self.grid.subgrids) do
                g.active = true
                g:process(msg)
            end

            for i,c in ipairs(self.components) do
                c.grid:process(msg)
            end
        end
	})

    self.mode_pads = self.grid:subgrid({
        name = 'mode pads',
        grid_start = {x=5,y=9},
        grid_end = {x=8,y=9},
    })

    self.arrow_pads = self.grid:subgrid({
        name = 'arrows pads',
        grid_start = {x=1,y=9},
        grid_end = {x=4,y=9},
        event = function(s,data)
            local mode = App.mode[App.current_mode]

            for i,component in ipairs(mode.components) do
                component.grid:event(data)
            end
            
            if self.on_arrow ~= nil then
              self:on_arrow(data)
            end
            
        end})

	self.row_pads = self.grid:subgrid({
        name = 'row pads',
        grid_start = {x=9,y=2},
        grid_end = {x=9,y=8},
        event = function(s,data)
            local mode = App.mode[App.current_mode]

            for i,component in ipairs(mode.components) do
                component.grid:event(data)
            end

            if self.on_row ~= nil then
              self:on_row(data)
            end
        end
    })

	-- Alt pad
	self.alt_pad = self.grid:subgrid({
        name = 'alt pad',
        grid_start = {x=9,y=1},
        grid_end = {x=9,y=1}, 
        event = function(s,data)
            if data.toggled then
                s.led[data.x][data.y] = 1
            else
                s.led[data.x][data.y] = 0
                if data.state then
                    s:reset()
                end
            end
            self.alt = data.toggled
            s:refresh('alt event')
            
            if self.on_alt ~= nil then
              self:on_alt(data)
            end
            
        end,
        on_reset = function(s)
            self.alt = false

            for i,c in pairs(self.components) do
                c.selection = nil
                if c.set_grid then
                    c:set_grid()
                end
            end

        end
    } )

end

function Mode:refresh()
    self:draw()
    screen_dirty = true
end

function Mode:draw()
    -- if interupt is true,
    if self.layer[0] then
        self.layer[0]()
    else
        error('We lost the layer?')
    end
    
    for i=1, #self.layer do
        self.layer[i]()
    end
   
end

function Mode:context_timeout(callback)
    if self.context_clock then
        clock.cancel(self.context_clock)
    end

    local count = 0
    
    self.context_clock = clock.run(function()
        while count < self.timeout do
            clock.sleep(1/24)
            count = count + (1/24)
        end
        
        self.alt_pad:reset()
        
        if callback then
            callback()
        end

        clock.cancel(self.context_clock)
        self.context_clock = nil
    end)
end

function Mode:handle_context(context, screen, layer)
    print('alt context?')
    if layer then
        self.layer[layer] = screen
    end

    App.screen_dirty = true
    
    local callback = function()
        print('context callback timeout')
        for binding, func in pairs(context) do
            -- Only bind default if defined and is a function
            if self.default and self.default[binding] and type(self.default[binding]) == "function" then
                self.context[binding] = self.default[binding]
            else
                self.context[binding] = function() print('fuck ' .. binding) end
            end
        end

        for i,c in pairs(self.components) do
            if c.set_grid then
                c:set_grid()
            end
        end

        if layer then
            self.layer[layer] = nil
        end
        App.screen_dirty = true
    end

    self:context_timeout(callback)

    for binding, func in pairs(context) do
        if func and type(func) == "function" then  -- Ensure function exists and is callable
            self.context[binding] = function(a, b)
                func(a, b)
                self:context_timeout(callback)
            end
        end
    end
end


function Mode:toast(toast_screen, layer)
    App.screen_dirty = true

    local count = 0
    self.layer[layer] = toast_screen

    if self.toast_clock then
        clock.cancel(self.toast_clock)
    end

    App.screen_dirty = true
    self.toast_clock = clock.run(function()
        while count < self.timeout do
            clock.sleep(1/15)
            count = count + (1/15)
        end
        self.layer[layer] = nil
        App.screen_dirty = true
        clock.cancel(self.toast_clock)
    end)
end 


function Mode:register_params(o)
    --local mode = 'mode_' .. o.id .. '_'
end

-- Methods
function Mode:enable()
    

    self.grid:enable()
    
    if self.id then
        self.mode_pads.led[4 + self.id][9] = 3
        self.mode_pads:refresh()
    end
    
    if self.on_load ~= nil then
        self:on_load()
    end

    for i, component in ipairs(self.components) do
        component.mode = App.mode[App.current_mode]
        component:enable()
    end

    screen_dirty = true

end

function Mode:disable()
    
    self.grid:disable()

    for i, component in ipairs(self.components) do
        component:disable()
        component.mode = nil
    end
end


return Mode