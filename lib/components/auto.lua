local path_name = 'Foobar/lib/'
local utilities = require(path_name .. '/utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require(path_name .. 'trackcomponent')

-- Auto is short for automation!

local Auto = TrackComponent:new()
Auto.__base = TrackComponent
Auto.name = 'auto'

--Initialize
function Auto:set(o)
	self.__base.set(self, o) -- call the base set method first   
		
	o.id = o.id or 1
		
	o.seq = o.seq or {}
    o.step = o.step or 1
    
    o.last_value = nil
    
    o.length = o.length or 96
    o.tick = o.tick or 0
    o.playing = false
    o.enabled = true

    o.on_start = o.on_start or function() end
    o.on_stop = o.on_stop or function() end
    o.on_clock = o.on_clock or function() end
    o.on_step = o.on_step or function() end

	-- o:load_bank(1)

	return o
end


-- BASE METHODS ---------------
function Auto:transport_event(data)
	if data.type == 'start' then
        self.tick = 0
        self.step = 1
        self:on_start()
    elseif data.type == 'stop' then
        self:on_stop()
    elseif data.type == 'clock' then
        if self.playing then
            self.tick = self.tick + 1
            self:on_clock()
        end
    end
	return data
end

function Auto:on_start()
    -- To be overridden by subclasses
end

function Auto:on_stop()
    -- To be overridden by subclasses
end

function Auto:on_clock()
    -- Implement step advancement
    local next_step = (self.tick - 1) % self.length + 1
    local last_step = self.step
    self.step = next_step

    if next_step ~= last_step then
        self:on_step()
    end
end

function Auto:on_step()
    local value = self.seq[self.step]

    -- Only run if the value has changed
    if value and value ~= self.last_value then
      self:run(value)
      self.last_value = value
    end

end

function Auto:run(value)
    print('Run')
end

function Auto:save_preset(number)
    App:set_preset(number, self.param_list)
end

function Auto:load_preset(number)
    App:load_preset(number, self.param_list)
end

return Auto