--- Base Class
local ModeComponent = {}

function ModeComponent:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    -- common functionality here
    self:set(o)

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

    o.register = o.register or {}
end

function ModeComponent:set_track(id)
    self:disable()
    self.track = id
    self:enable()
end

function ModeComponent:get_component()
    return App.track[self.track][self.component]
end

function ModeComponent:enable()
    local mode = self
    local component = self:get_component()

    mode.grid:enable()

    mode.grid.event = function(s,d)
        local component = self:get_component()
        self:grid_event(component, d)
    end

    mode.grid.set_grid = function()
        local component = self:get_component()
        if mode.set_grid ~= nil then
            self:set_grid(component)
        end
    end

    mode.grid:set_grid(component)

    if mode.midi_event ~= nil then
        component.on_midi = function(component, data)
            mode:midi_event(component, data)
        end
    end

    if mode.transport_event ~= nil then
        component.on_transport = function(component, data)
            mode:transport_event(component, data)
        end
    end

    for i,on in ipairs(self.register)do
        component[on] = function(component, data)
            mode[on](mode, component, data)
        end
    end
    
    if mode.on_enable ~= nil then
        mode:on_enable()
    end

end

function ModeComponent:disable()
    local mode = self
    mode.grid:disable()
    mode.grid.event = nil
    mode.grid.set_grid = nil

    local component = self:get_component()
    component.on_midi = nil
    component.on_transport = nil

    for i,on in ipairs(self.register)do
        component[on] = nil
    end

    if mode.on_disable ~= nil then
        mode:on_disable()
    end
end

return ModeComponent