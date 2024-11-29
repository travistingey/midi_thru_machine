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
    --[[ Required properties
    o.id = o.id
    o.track = o.track
    o.grid = o.grid
    o.name = o.name
    o.component = o.component
    o.register = {'on_save'}
    ]]
    
    self.register = o.register or {}
end

function ModeComponent:set_track(id)
    self:disable()
    self.track = id
    self:enable()
end

function ModeComponent:get_component()
    if self.component then
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
        track_component.on_midi = function(track_component, data)
            mode_component:midi_event(track_component, data)
        end
    end

    
    if mode_component.transport_event ~= nil then
        
        track_component.on_transport = function(track_component, data)
            mode_component:transport_event(track_component, data)
        end
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

    if self.component then
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


function ModeComponent:start_blink()
    self.blink_mode = true
    -- Start the blinking coroutine if not already running
    if not self.blinking_clock then
        self.blink_state = true  -- Initialize blink state
        self.blinking_clock = clock.run(function()
        while self.blink_mode do
            self.blink_state = not self.blink_state
            self:set_grid()
            clock.sleep(0.5)  -- Adjust blink interval as desired
        end
        clock.cancel(self.blinking_clock)
        self.blinking_clock = nil
        self.blink_state = nil
        self:set_grid()
        end)
    end
end

function ModeComponent:end_blink()
-- Stop the blinking coroutine if it's running
self.blink_mode = false
end


return ModeComponent