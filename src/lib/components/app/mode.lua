local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
local utilities = require(path_name .. 'utilities')

local Input = require(path_name .. 'components/track/input')
local Seq = require(path_name .. 'components/track/seq')
local Output = require(path_name .. 'components/track/output')
local UI = require(path_name .. 'ui')

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

-- Menu interaction logic (moved from UI)
function Mode:set_cursor(d)
    self.cursor = util.clamp((self.cursor or 1) + d, 1, self.cursor_positions or 1)
    App.screen_dirty = true
end

function Mode:use_menu(ctx, d)
    local item = self.menu and self.menu[self.cursor]
    if item and type(item[ctx]) == 'function' then
        item[ctx](d)
    end
    App.screen_dirty = true
end

function Mode:get_visible_menu_range()
    local total_items = #(self.menu or {})
    local max_visible = UI.max_visible_items

    if total_items <= max_visible then
        return 1, total_items
    end

    local start_index = 1
    local end_index = max_visible

    if (self.cursor or 1) > max_visible - 2 then
        if (self.cursor or 1) <= total_items - 2 then
            start_index = self.cursor - 2
            end_index = self.cursor + 2
        else
            start_index = total_items - max_visible + 1
            end_index = total_items
        end
    end

    return start_index, end_index
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

    self.track = o.track
    
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
    self.screen = o.screen or function() end

    -- Stateless UI now; track menu state per mode
    self.menu = {}
    self.cursor = 1
    self.cursor_positions = 0
    self.max_visible_items = 5
    self.default_menu = nil
    self.default_screen = nil


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
                if c.grid and c.grid.process then
                    c.grid:process(msg)
                end
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
            self:emit('arrow', self, data)
        end
    })

    self.row_pads = self.grid:subgrid({
        name = 'row pads',
        grid_start = { x = 9, y = 2 },
        grid_end = { x = 9, y = 8 },
        event = function(s, data)
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

function Mode:update_grid(device)
    -- Update the main mode grid
    self.grid:update_midi(device)
    -- Also update each component’s grid to the new device
    for _, component in ipairs(self.components) do
        if component.grid and component.grid.update_midi then
            component.grid:update_midi(device)
        end
    end
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
    
    for i, c in ipairs(self.components) do
        if c.set_grid ~= nil then
            c:set_grid()
        end
    end
    screen_dirty = true
end

function Mode:draw()
    for i, v in pairs(self.layer) do
        self.layer[i](self)
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
    
    -- restore default menu and screen if defined
    if self.default_menu then
        self.menu = self.default_menu
        self.cursor_positions = #self.menu
        self.cursor = util.clamp(self.cursor or 1, 1, math.max(1, self.cursor_positions))
    else
        self.menu = {}
        self.cursor = 1
        self.cursor_positions = 0
    end

    if self.default_screen then
        -- reapply default screen as context layer
        self.context_layer = self.default_screen
        table.insert(self.layer, self.context_layer)
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
function Mode:use_context(context, screen, option)
    local callback
    local timeout
    local menu_override = false
    local set_default = false
    local menu_context = context.menu or nil

    if type(option) == 'table' then
        timeout = option.timeout 
        callback = option.callback
        menu_override = option.menu_override
        set_default = option.set_default or false
        
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

    -- Apply menu context to this mode
    if menu_context then
        if menu_override then
            self.menu = {}
        end
        for _, menu_item in ipairs(menu_context) do
            table.insert(self.menu, menu_item)
        end
        self.cursor = 1
        self.cursor_positions = #self.menu
    end

    if set_default and menu_context then
        -- store default baseline
        self.default_menu = {}
        for _, item in ipairs(menu_context) do table.insert(self.default_menu, item) end
        self.default_screen = screen
    end

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

function Mode:toast(toast_text, draw_fn)
    draw_fn = draw_fn or function(t) UI:draw_toast(t) end
    
    local function toast_screen()
       draw_fn(toast_text)
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
function Mode:register_screens()
    self.layer = {App.default.screen}

    -- Register screen functions
    if self.screen and type(self.screen) == 'function' then
        table.insert(self.layer, self.screen)
    end
end

function Mode:enable()
    if self.enabled then
        return -- Prevent re-enabling
    end
    
    self.track = App.current_track

    for _, component in ipairs(self.components) do
        component.mode = self
        component:enable()
    end

    -- Register component screen functions into the layer system
    self:register_screens()

    self.grid:enable()
    self.enabled = true

    if self.id then
        self.mode_pads.led[4 + self.id][9] = 3
        self.mode_pads:refresh()
    end
    
    if self.load_event ~= nil then
        self:load_event()
    end

    if self.row_event ~= nil then
        self:on('row', self.row_event)
    end

    if self.arrow_event ~= nil then
        self:on('arrow', self.arrow_event)
    end

    self:emit('enable')
    screen_dirty = true
end

function Mode:disable()
    -- Cancel any active context or toast
    self:cancel_context()
    self:cancel_toast()
    self.enabled = false
    -- reset alt
    self:emit('alt_reset')

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
