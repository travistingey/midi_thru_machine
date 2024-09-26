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
    self.set(o, o)
    self.register_params(o, o)
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

    for binding, func in pairs(App.default) do
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
        grid_start = { x = 1, y = 1 },
        grid_end = { x = 9, y = 9 },
        display_start = { x = 1, y = 1 },
        display_end = { x = 9, y = 9 },
        midi = App.midi_grid,
        active = false,

        process = function(s, msg)
            for i, g in ipairs(self.grid.subgrids) do
                g.active = true
                g:process(msg)
            end

            for i, c in ipairs(self.components) do
                c.grid:process(msg)
            end
        end
    })

    self.mode_pads = self.grid:subgrid({
        name = 'mode pads',
        grid_start = { x = 5, y = 9 },
        grid_end = { x = 8, y = 9 },
    })

    self.arrow_pads = self.grid:subgrid({
        name = 'arrows pads',
        grid_start = { x = 1, y = 9 },
        grid_end = { x = 4, y = 9 },
        event = function(s, data)
            local mode = App.mode[App.current_mode]

            for i, component in ipairs(mode.components) do
                component.grid:event(data)
            end

            if self.on_arrow ~= nil then
                self:on_arrow(data)
            end

        end
    })

    self.row_pads = self.grid:subgrid({
        name = 'row pads',
        grid_start = { x = 9, y = 2 },
        grid_end = { x = 9, y = 8 },
        event = function(s, data)
            local mode = App.mode[App.current_mode]

            for i, component in ipairs(mode.components) do
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
        grid_start = { x = 9, y = 1 },
        grid_end = { x = 9, y = 1 },
        event = function(s, data)
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
            
            if data.state and data.toggled then
                if self.on_alt ~= nil then
                    self:on_alt(data)
                end
                
                for i, c in pairs(self.components) do
                    if c.on_alt ~= nil then
                        c:on_alt(data)
                    end
                end
            end

        end,
        on_reset = function(s)
            self.alt = false

            for i, c in pairs(self.components) do
                c.selection = nil
                if c.set_grid then
                    c:set_grid()
                end
            end

        end
    })
end

function Mode:refresh()
    self:draw()
    screen_dirty = true
end

function Mode:draw()
    if self.layer[0] then
        self.layer[0]()
    else
        error('We lost the layer?')
    end

    for i, v in pairs(self.layer) do
        self.layer[i]()
    end

end

-- Added cancel_context method to handle context cleanup
function Mode:cancel_context()
    if self.context_clock then
        clock.cancel(self.context_clock)
        self.context_clock = nil
    end

    -- Remove the context screen from the layer
    if self.context_layer_index then
        table.remove(self.layer, self.context_layer_index)
        self.context_layer_index = nil
    end

    -- Reset the context functions to default
    for binding, func in pairs(self.default) do
        self.context[binding] = func
    end

    for i, c in pairs(self.components) do
        if c.set_grid then
            c:set_grid()
        end
    end

    App.screen_dirty = true
end

-- Added cancel_toast method to handle toast cleanup
function Mode:cancel_toast()
    if self.toast_clock then
        clock.cancel(self.toast_clock)
        self.toast_clock = nil
    end
    if self.toast_layer_index then
        table.remove(self.layer, self.toast_layer_index)
        self.toast_layer_index = nil
    end
    App.screen_dirty = true
end

function Mode:context_timeout(callback)
    if self.context_clock then
        clock.cancel(self.context_clock)
        self.context_clock = nil
    end

    local count = 0

    self.context_clock = clock.run(function()
        while count < self.timeout do
            clock.sleep(1 / 24)
            count = count + (1 / 24)
        end

        self.alt_pad:reset()

        if callback then
            callback()
        end

        self.context_clock = nil
    end)
end

function Mode:handle_context(context, screen)
    -- Cancel any existing context
    self:cancel_context()

    -- Cancel any existing toast when a new context is started
    self:cancel_toast()

    -- Insert the context screen and keep track of its layer index
    table.insert(self.layer, screen)
    self.context_layer_index = #self.layer

    App.screen_dirty = true

    local function context_callback()
        print('context callback timeout')
        -- Perform cleanup
        self:cancel_context()
    end

    self:context_timeout(context_callback)

    for binding, func in pairs(context) do
        if func and type(func) == "function" then  -- Ensure function exists and is callable
            self.context[binding] = function(a, b)
                func(a, b)
                self:context_timeout(context_callback)
            end
        end
    end
end

function Mode:toast(toast_screen)
    -- Cancel any existing toast
    self:cancel_toast()

    -- Insert the new toast screen and keep track of its layer index
    table.insert(self.layer, toast_screen)
    self.toast_layer_index = #self.layer  -- Keep track of the layer index

    local count = 0
    self.toast_clock = clock.run(function()
        while count < self.timeout do
            clock.sleep(1 / 15)
            count = count + (1 / 15)
        end
        -- Remove the toast layer
        self:cancel_toast()
    end)

    App.screen_dirty = true
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
    -- Cancel any active context or toast
    self:cancel_context()
    self:cancel_toast()
    
    self.grid:disable()

    for i, component in ipairs(self.components) do
        component:disable()
        component.mode = nil
    end

    -- Optionally, clear the layers to ensure a clean state
    self.layer = {}
    self.layer[0] = App.default.screen

    App.screen_dirty = true
end

function Mode:on_cc(data)
    for _, component in ipairs(self.components) do
        if component.on_cc then
            component:on_cc(data)
        end
    end
end

return Mode