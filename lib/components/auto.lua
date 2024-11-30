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
    
    o.step_length = o.step_length or 96
    o.tick = o.tick or 0
    o.playing = false
    o.enabled = true

    o.active_cc_automation = nil  -- Holds active CC automation data
    o.cc_automation_start_tick = 0  -- Records the start tick for CC automation

    o.on_start = o.on_start or function() end
    o.on_stop = o.on_stop or function() end
    o.on_clock = o.on_clock or function() end
    o.on_step = o.on_step or function() end

	-- o:load_bank(1)

	return o
end


-- BASE METHODS ---------------

function Auto:transport_event(data)
    if data.type == 'start' or data.type == 'continue' then
        self.tick = 0
        self.step = 1
        self.playing = true
        self:on_start()
    elseif data.type == 'stop' then
        self.playing = false
        self:on_stop()
    elseif data.type == 'clock' then
        if self.playing then
            self:on_clock()
            self.tick = self.tick + 1
        end
    end
    return data
end

function Auto:on_start()
    -- Reset any active automation
    self.active_cc_automation = nil
end

function Auto:on_stop()
    -- Handle stopping of automation if needed
    self.active_cc_automation = nil
end

function Auto:on_clock()
    -- Handle tick-based automation
    if self.active_cc_automation then
        self:update_cc_automation()
    end

    -- Implement step advancement
    if self.tick % self.step_length == 0 then
        if #self.seq > 0 then
            self:on_step()
        else
            print('no step')
        end
    end
end

function Auto:on_step()
    local action = self.seq[self.step]

    if action then
        self:run(action)
    end

    -- Advance to the next step
    self.step = (self.step % #self.seq) + 1
end

function Auto:run(action)
    if action.type == 'preset' then
        self:run_preset_action(action)
    elseif action.type == 'cc_automation' then
        self:run_cc_automation_action(action)
    end
end

function Auto:run_preset_action(action)
    -- Load the specified preset
    App:load_preset(action.preset_number, action.param_list)
end

function Auto:run_cc_automation_action(action)
    -- Initialize CC automation parameters
    self.active_cc_automation = {
        cc_number = action.cc_number,
        curve = action.curve,  -- {P0, P1, P2, P3}
        duration = action.duration,
        start_tick = self.tick,
        end_tick = self.tick + action.duration,
        midi_channel = action.midi_channel or 1
    }
    self.cc_automation_start_tick = self.tick
end

function Auto:update_cc_automation()
    local automation = self.active_cc_automation
    local current_tick = self.tick
    if current_tick <= automation.end_tick then
        local t = (current_tick - automation.start_tick) / automation.duration
        local value = self:bezier_transform(t, automation.curve)
        local cc_message = {
            type = 'cc',
            cc = automation.cc_number,
            val = math.floor(value * 127),
            ch = automation.midi_channel
        }
        -- Send the CC message
        App.midi_out:send(cc_message)
    else
        -- Automation completed
        self.active_cc_automation = nil
    end
end

function Auto:bezier_transform(t, curve)
    local P0, P1, P2, P3 = curve[1], curve[2], curve[3], curve[4]
    local u = 1 - t
    local tt = t * t
    local uu = u * u
    local uuu = uu * u
    local ttt = tt * t
    local y = uuu * P0.y + 3 * uu * t * P1.y + 3 * u * tt * P2.y + ttt * P3.y
    return y  -- Normalized between 0 and 1
end

return Auto