--- Base Class
local ModeComponent = {}

function ModeComponent:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    -- common functionality here
    self.set(o,o)

    return o
end

function ModeComponent:set(o)
    self.register = o.register or {}
end

function ModeComponent:set_track(id)
    self:disable()
    self.track = id
    self:enable()
end

-- In ModeComponent.lua
function ModeComponent:emit(event_name, ...)
    self.mode:emit(event_name, ...)
end

-- Convenience function to register and deregister event listeners to the Mode
function ModeComponent:on(event_name, listener)
    self.mode:on(event_name, listener)
    return function()
        self.mode:off(event_name, listener)
    end
end

function ModeComponent:off(event_name, listener)
    self.mode:off(event_name, listener)
end

function ModeComponent:get_component()
    if self.component and self.track then
        return App.track[self.track][self.component]
    end
end

function ModeComponent:enable()
    local mode_component = self
    local track_component = self:get_component()
    
    mode_component.grid:enable()

    mode_component.grid.event = function(s,d)
        local track_component = self:get_component()
        self:grid_event(track_component, d)
    end

    mode_component.grid.set_grid = function()
        local track_component = self:get_component()
        if mode_component.set_grid ~= nil then
            self:set_grid(track_component)
        end
    end

    mode_component.grid:set_grid(track_component)

    if mode_component.midi_event ~= nil then
        track_component:on('midi_event', function(data)
            mode_component:midi_event(track_component, data)
        end)
    end

    
    if mode_component.transport_event ~= nil then
        
        self.mode:on('transport_event', function(data)
            mode_component:transport_event(track_component, data)
        end)

    end

    
    for i,on in ipairs(self.register)do
        track_component[on] = function(track_component, data)
            mode_component[on](mode_component, track_component, data)
        end
    end
    
    if mode_component.on_enable ~= nil then
        mode_component:on_enable()
    end

end

function ModeComponent:disable()
    local mode = self
    
    mode.grid:disable()
    mode.grid.event = nil
    mode.grid.set_grid = nil

    if self.component and self.track then
        local component = self:get_component()
        component.on_midi = nil
        component.on_transport = nil
        

        for i,on in ipairs(self.register)do
            component[on] = nil
        end
    end
    if mode.on_disable ~= nil then
        mode:on_disable()
    end
end


function ModeComponent:start_blink(callback)
    local component = self:get_component()
    
    self.blink_mode = true
    
    -- Start the blinking coroutine if not already running
    if not self.blinking_clock then
        self.blink_state = true  -- Initialize blink state
        self.blinking_clock = clock.run(function()
            while self.blink_mode do
                self.blink_state = not self.blink_state
                self:set_grid(component)
                clock.sleep(0.5)  -- Adjust blink interval as desired
            end
            -- Blinking loop ended
            clock.cancel(self.blinking_clock)
            self.blinking_clock = nil
            self.blink_state = nil
            
            -- Check whether to skip set_grid
            if not self.skip_set_grid then
                self:set_grid(component)
            end

            self.skip_set_grid = nil
            -- We execute the callback only when mode is enabled
            if callback ~= nil and type(callback) == 'function' and self.mode.enabled then
                callback()
            end
        end)
    end
end

function ModeComponent:end_blink()
    -- Stop the blinking coroutine if it's running
    self.blink_mode = false
end


return ModeComponent