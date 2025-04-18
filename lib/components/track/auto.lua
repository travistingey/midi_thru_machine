local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

-- Auto is short for automation!

local Auto = {}
Auto.name = 'auto'
Auto.__index = Auto
setmetatable(Auto,{ __index = TrackComponent })

function Auto:new(o)
    o = o or {}
    setmetatable(o, self)
    TrackComponent.set(o,o)
    o:set(o)
    return o
end

function Auto:set(o)
    self.id = o.id or 1
    self.seq = o.seq or {}
    self.seq_start = o.seq_start or 0
    self.seq_length = App.ppqn * 16
    self.step = o.step or 0
    self.playing = false
    self.enabled = true

    self.active_cc = nil  -- Holds active CC automation data

    self.track.current_preset = 1

    self:on('record_event', function(data)
        local step = self.step
        if data.quantize then
            step = math.floor(step / data.quantize) * data.quantize
        end
        self:set_action(self.step, data.type, data.value)
    end)

end

function Auto:get_action(step, lane)
    if self.seq[step] then
        return self.seq[step][lane]
    end
end

function Auto:set_action(step, lane, value)
    local action = {}

    -- Initialize step
    if not self.seq[step] then
        self.seq[step] = {}
    end

    if type(lane) == 'table' then
        local action = lane

        -- Manage nested table of CC
        if action.type == 'cc' then

            if not self.seq[step]['cc'] then
                self.seq[step]['cc'] = {}
            end
            
            local entry = self.seq[step]['cc']
            
            if action.value == nil then
                entry[action.cc] = nil
            else
                entry[action.cc] = action
            end
        else
            -- Standard action
            self.seq[step][action.type] = lane
        end
    elseif type(lane) == 'string' then
        action.type = lane
        action.value = value

        -- Remove nil value entries
        if action.value == nil then
            self.seq[step][action.type] = nil
        else
            self.seq[step][action.type] = {type = action.type, value = value}
        end
    end
end

-- Set value if none exists. If value exists, set to nil
-- This only works for single action types
function Auto:toggle_action(step, action)
    local action_type = action.type
    local last_selection

    if self.seq[step] and self.seq[step][action_type] then
        last_selection = self.seq[step][action_type]
        self:set_action(step,action_type,nil)
    else
        last_selection = nil
        self:set_action(step,action_type,action.value)
    end

    return last_selection
end

function Auto:set_loop(loop_start, loop_end)
    self.seq_start = loop_start
    self.seq_length = loop_end - loop_start + 1
end

-- Transport Event Handling
function Auto:transport_event(data)
    if data.type == 'start' then
        self.playing = true
        self.step = 0
        self.active_cc = nil
        
        if self.seq[self.step] then
            self:run_events(self.seq[self.step])
        end
    elseif data.type == 'stop' then
        self.playing = false
        self.step = 0
        if self.seq[self.step] then
            self:run_events(self.seq[self.step])
        end
    elseif data.type == 'clock' and self.playing then
        self:update_cc()
        -- Offset run steps ahead of step
        local run_offset = 2 

        if self.step < run_offset then
            if self.seq[self.step] then
                self:run_events(self.seq[self.step])
            end
        end

        -- Calculate the next step
        local next_step = self.step + run_offset

        if next_step >= self.seq_start + self.seq_length then
            next_step = self.seq_start
            self.step = self.seq_start
        else
            self.step = self.step + 1
        end

        local actions = self.seq[next_step]

        if actions then
            self:run_events(actions)
        end

    end

    return data
end

function Auto:run_events(actions)
    for action_type, action_data in pairs(actions) do
        if action_type == 'track' and action_data then
            self:run_preset(action_data)
            self:emit('preset_change', action_data)
        elseif action_type == 'scale' and action_data then
            self:run_scale(action_data)
            self:emit('scale_change', action_data)
        elseif action_type == 'cc' and action_data then
            self:run_cc(action_data)
            self:emit('cc_change', action_data)
        end
    end
end

function Auto:run_preset(action)
    local component_props = App.preset_props.track
    local id = self.track.id

    self.track.current_preset = action.value

    if component_props then
        local props = {}
        for i,v in ipairs(component_props) do
            props[i] = 'track_' .. id .. '_' .. v
        end

        App:load_preset(action.value, props)
    end
end

function Auto:run_scale(action)
    local component_props = App.preset_props.scale
    local props = {}

    self.track.current_scale = action.value

    for id=1,3 do
        if component_props then    
            for i,v in ipairs(component_props) do
                props[i] = 'scale_' .. id .. '_' .. v
            end
            App:load_preset(action.value, props)
        end
    end
end

function Auto:run_cc(cc_actions)
    for cc_number, action in pairs(cc_actions) do
        if action then
            -- Initialize CC automation parameters for each CC
            self.active_ccs = self.active_ccs or {}
            self.active_ccs[cc_number] = {
                curve = action.curve,  -- {P0, P1, P2, P3}
                duration = action.duration,
                start_tick = self.tick,
                end_tick = self.tick + action.duration,
                midi_channel = action.midi_channel or 1
            }
        end
    end
end

function Auto:update_cc()
    if not self.active_ccs then return end

    for cc_number, automation in pairs(self.active_ccs) do
        local current_tick = self.tick
        if current_tick <= automation.end_tick then
            local t = (current_tick - automation.start_tick) / automation.duration
            t = math.min(math.max(t, 0), 1)  -- Clamp t between 0 and 1
            local value = self:bezier_transform(t, automation.curve)
            local cc_message = {
                type = 'cc',
                cc = cc_number,
                val = math.floor(value * 127),
                ch = automation.midi_channel
            }
            -- Send the CC message
            App.midi_out:send(cc_message)
        else
            -- Automation completed
            self.active_ccs[cc_number] = nil
        end
    end

    -- Clean up if all automations are done
    if next(self.active_ccs) == nil then
        self.active_ccs = nil
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