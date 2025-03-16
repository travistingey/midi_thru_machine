
local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/track/'
local Input = require(path_name .. 'input')
local Seq = require(path_name .. 'seq')
local Output = require(path_name .. 'output')


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

    self.enabled = false
    self.timeout = 5
    self.reset_timeout_count = false
    self.interupt = false
    self.context = o.context or {}
    self.default = {}

    self.event_listeners = {}
    self.cleanup_functions = {}

    for binding, func in pairs(App.default) do
        if self.context[binding] then
            self.default[binding] = self.context[binding]
        else
            self.default[binding] = func
            self.context[binding] = func
        end
    end

    self.layer = o.layer or {}
    self.layer[1] = App.default.screen
    
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
            local mode = self

            for i, component in ipairs(mode.components) do
                component.grid:event(data)
            end

            self:emit('arrow', data)

        end
    })

    self.row_pads = self.grid:subgrid({
        name = 'row pads',
        grid_start = { x = 9, y = 2 },
        grid_end = { x = 9, y = 8 },
        event = function(s, data)
            tab.print(data)
            self:emit('row', self, data)
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
            self:emit('alt', data)
        end
    })


end

-- Mode event listeners
function Mode:on(event_name, listener)
    if not self.event_listeners[event_name] then
        self.event_listeners[event_name] = {}
    end
    
    table.insert(self.event_listeners[event_name], listener)

    local cleanup = function() self:off(event_name, listener) end
    table.insert(self.cleanup_functions, cleanup)

    return cleanup
end

function Mode:off(event_name, listener)
    if self.event_listeners and self.event_listeners[event_name] then
        for i, l in ipairs(self.event_listeners[event_name]) do
            if l == listener then
                table.remove(self.event_listeners[event_name], i)
                break
            end
        end
    end
end

function Mode:emit(event_name, ...)
    local listeners = self.event_listeners[event_name]
    if listeners then
        for _, listener in ipairs(listeners) do
            listener(...)
        end
    end
end

function Mode:refresh()
    self:draw()
    screen_dirty = true
end

function Mode:draw()
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
    if self.context_layer then
        for i, layer in ipairs(self.layer) do
            if layer == self.context_layer then
                table.remove(self.layer, i)
                break
            end
        end
        self.context_layer = nil
    end

    -- Reset the context functions to default
    for binding, func in pairs(self.default) do
        self.context[binding] = func
    end

    for i, c in pairs(self.components) do
        local component = c:get_component()
        if c.set_grid then
            c:set_grid(component)
        end
    end

    App.screen_dirty = true
end


-- cancel_toast
function Mode:cancel_toast()
    if self.toast_clock then
        clock.cancel(self.toast_clock)
        self.toast_clock = nil
    end

    if self.toast_layer then
        for i, layer in ipairs(self.layer) do
            if layer == self.toast_layer then
                table.remove(self.layer, i)
                break
            end
        end
        self.toast_layer = nil
    end
    App.screen_dirty = true
end

function Mode:reset_timeout()
    if self.context_clock then
        self.reset_timeout_count = true
    end
end

function Mode:context_timeout(timeout, callback)
    if self.context_clock then
        clock.cancel(self.context_clock)
        self.context_clock = nil
    end

    local count = 0

    self.context_clock = clock.run(function()
        while count < timeout do

            if self.reset_timeout_count then
                count = 0
                self.reset_timeout_count = false
            end

            clock.sleep(1 / 24)
            count = count + (1 / 24)
        end

        self:cancel_context()

        if callback then
            callback()
        end

        self.context_clock = nil
    end)
end

-- Options is going to represent an optional third property
-- If an option is type of function, we will assume its a callback
-- If an option is a type of number, we will assume its a timeout
-- if an option is type of boolean, we will assume whether or not to use a timeout
-- if the timeout is true then we use the default timeout
function Mode:handle_context(context, screen, option)
    local callback
    local timeout

    if type(option) == 'table' then
        timeout = option.timeout or nil
        callback = option.callback or nil
        if timeout == true then
            timeout = self.timeout
        end
    elseif type(option) == 'number' then
        timeout = option
    elseif type(option) == 'function' then
        callback = option
    elseif type(option) == 'boolean' then
        if option then
            timeout = self.timeout
        end
    end

    -- Cancel any existing context
    self:cancel_context()

    -- Cancel any existing toast when a new context is started
    self:cancel_toast()

    -- Insert the context screen and keep a reference to it
    self.context_layer = screen
    table.insert(self.layer, screen)

    App.screen_dirty = true

    if timeout then
        self:context_timeout(timeout, callback)
    end

    for binding, func in pairs(context) do
        if func and type(func) == "function" then  -- Ensure function exists and is callable
            self.context[binding] = function(a, b)
                func(a, b)
                if timeout then
                    self:context_timeout(timeout, callback)
                end
            end
        end
    end
end

function Mode:toast(toast_text)
    local function toast_screen()
        screen.level(15)
        screen.move(64,32)
        screen.text_center(toast_text)
        screen.fill()
    end

    -- Cancel any existing toast
    self:cancel_toast()

    -- Insert the new toast screen and keep a reference to it
    self.toast_layer = toast_screen
    table.insert(self.layer, toast_screen)

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
    if self.enabled then
        return -- Prevent re-enabling
    end
    
    for _, component in ipairs(self.components) do
        component.mode = self
        component:enable()
    end

    self.grid:enable()
    self.enabled = true

    if self.id then
        self.mode_pads.led[4 + self.id][9] = 3
        self.mode_pads:refresh()
    end

    -- Listen for an 'alt_reset' event so that components can trigger a reset of the alt pad.
    self:on('alt_reset', function()
        if self.alt_pad and self.alt_pad.reset then
        self.alt_pad:reset()
        self.alt = false
        self.alt_pad:refresh('alt reset')
        end
    end)
    
    if self.load_event ~= nil then
        self:load_event()
    end

    if self.row_event ~= nil then
        self:on('row', self.row_event)
    end

    screen_dirty = true
end

function Mode:disable()
    -- Cancel any active context or toast
    self:cancel_context()
    self:cancel_toast()
    self.enabled = false
    
    -- reset alt
    self.alt_pad.toggled[1][9] = false
    self.alt = false

    self.grid:disable()

    -- First, execute all cleanup functions
    for i, cleanup in ipairs(self.cleanup_functions) do
        cleanup()
    end
    self.cleanup_functions = {}

    -- Then disable each component and clear its mode reference
    for i, component in ipairs(self.components) do
        component:disable()
        component.mode = nil
    end

    self.event_listeners = {}
    App.screen_dirty = true
end

return Mode