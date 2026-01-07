local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')

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

    -- Buffer for live MIDI recording
    self.buffer_length = App.BUFFER_LENGTH or (App.ppqn * 16)

    -- Track active notes from buffer playback to prevent stuck notes
    -- Key: note number, Value: { ch = channel }
    self.active_buffer_notes = {}

    self:on('record_event', function(data)
        local step = self.step
        if data.quantize then
            step = math.floor(step / data.quantize) * data.quantize
        end
        self:set_action(self.step, data.type, data.value)
    end)

end

-- Record a MIDI event to the buffer lane at the current step
-- Events wrap around when exceeding buffer_length
-- In overwrite mode, clears existing events at tick before recording
function Auto:record_buffer(midi_event)
    local tick = self.step % self.buffer_length

    if not self.seq[tick] then
        self.seq[tick] = {}
    end

    -- In overwrite mode, clear existing buffer events at this tick
    -- (but only once per tick - track with a flag)
    if not App.buffer_overdub then
        if not self.overwrite_cleared_ticks then
            self.overwrite_cleared_ticks = {}
        end
        if not self.overwrite_cleared_ticks[tick] then
            self.seq[tick].buffer = {}
            self.overwrite_cleared_ticks[tick] = true
        end
    end

    if not self.seq[tick].buffer then
        self.seq[tick].buffer = {}
    end

    -- Store the event (multiple events can exist at same tick)
    table.insert(self.seq[tick].buffer, {
        type = midi_event.type,
        note = midi_event.note,
        vel = midi_event.vel,
        ch = midi_event.ch,
    })
end

-- Clear buffer events for a single tick (used for overwrite mode)
function Auto:clear_buffer_tick(tick)
    if self.seq[tick] and self.seq[tick].buffer then
        self.seq[tick].buffer = {}
    end
end

-- Clear the buffer lane
function Auto:clear_buffer()
    for tick, lanes in pairs(self.seq) do
        if lanes.buffer then
            lanes.buffer = nil
        end
        -- Clean up empty tick entries
        if next(lanes) == nil then
            self.seq[tick] = nil
        end
    end
    print('Buffer cleared for track ' .. self.track.id)
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
        -- Clear any lingering buffer notes from previous playback
        self:kill_buffer_notes()
        -- Reset overwrite tracking for new playback
        self.overwrite_cleared_ticks = {}

        if self.seq[self.step] then
            self:run_events(self.seq[self.step])
        end
    elseif data.type == 'stop' then
        self.playing = false
        self.step = 0
        -- Kill all active buffer notes to prevent stuck notes
        self:kill_buffer_notes()
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

        -- Handle scrub mode separately
        if self.scrub_mode then
            if next_step > self.scrub_end then
                if self.scrub_loop then
                    -- Loop back to scrub start
                    self:kill_buffer_notes()
                    next_step = self.scrub_start
                    self.step = self.scrub_start
                else
                    -- Play-through mode: stay at end (will be restored when scrub stops)
                    next_step = self.scrub_end
                    self.step = self.scrub_end
                end
            else
                self.step = self.step + 1
            end

            -- Only run buffer events during scrub
            local actions = self.seq[next_step]
            if actions and actions.buffer then
                self:run_buffer(actions.buffer)
            end
        else
            -- Normal playback mode
            if next_step >= self.seq_start + self.seq_length then
                -- Loop boundary: kill active buffer notes to prevent stuck notes
                -- This handles cases where note_on is near end but note_off is after loop point
                self:kill_buffer_notes()

                -- Handle buffer recording modes at loop boundary
                if self.track.armed then
                    -- One-shot mode: disarm track after completing loop
                    if not App.buffer_loop then
                        self.track.armed = false
                        Registry.set('track_' .. self.track.id .. '_armed', 0, 'buffer_oneshot')
                        print('Track ' .. self.track.id .. ' disarmed (one-shot complete)')
                    end
                end

                -- Reset overwrite tracking for new loop iteration
                self.overwrite_cleared_ticks = {}

                -- Emit loop boundary event
                self:emit('loop_boundary')

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
        elseif action_type == 'buffer' and action_data then
            self:run_buffer(action_data)
        end
    end
end

-- Playback buffer events directly to output (bypasses processing chain)
-- Respects App.buffer_playback and App.buffer_mute_on_arm settings
function Auto:run_buffer(events)
    if not self.track.output_device then return end

    -- Check if buffer playback is globally disabled
    if not App.buffer_playback then return end

    -- Check if buffer should be muted because track is armed
    if App.buffer_mute_on_arm and self.track.armed then return end

    for _, event in ipairs(events) do
        local ch = event.ch or self.track.midi_out
        local midi_msg = {
            type = event.type,
            note = event.note,
            vel = event.vel,
            ch = ch,
        }

        -- Track active notes to prevent stuck notes
        if event.type == 'note_on' and event.vel > 0 then
            self.active_buffer_notes[event.note] = { ch = ch }
        elseif event.type == 'note_off' or (event.type == 'note_on' and event.vel == 0) then
            self.active_buffer_notes[event.note] = nil
        end

        self.track.output_device:send(midi_msg)
    end
end

-- Send note_off for all active buffer notes (prevents stuck notes)
function Auto:kill_buffer_notes()
    if not self.track.output_device then return end

    for note, data in pairs(self.active_buffer_notes) do
        local midi_msg = {
            type = 'note_off',
            note = note,
            vel = 0,
            ch = data.ch or self.track.midi_out,
        }
        self.track.output_device:send(midi_msg)
    end

    self.active_buffer_notes = {}
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
            self.track.midi_out:send(cc_message)
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

-- Scrub playback: temporarily play a range of the buffer
-- loop_mode: true = loop the range, false = play through once then stop
function Auto:start_scrub(start_tick, end_tick, loop_mode)
    -- Kill any currently playing buffer notes before scrub
    self:kill_buffer_notes()

    -- Store scrub state
    self.scrub_mode = true
    self.scrub_loop = loop_mode
    self.scrub_start = start_tick
    self.scrub_end = end_tick
    self.scrub_length = end_tick - start_tick + 1

    -- Jump to scrub start position
    self.step = start_tick
end

-- Update scrub range (for multi-pad selection)
function Auto:update_scrub(start_tick, end_tick)
    if not self.scrub_mode then return end

    -- Kill notes to prevent stuck notes when range changes
    self:kill_buffer_notes()

    self.scrub_start = start_tick
    self.scrub_end = end_tick
    self.scrub_length = end_tick - start_tick + 1
end

-- Stop scrub and restore normal playback
function Auto:stop_scrub(saved_step, saved_seq_start, saved_seq_length)
    if not self.scrub_mode then return end

    -- Kill any scrub notes
    self:kill_buffer_notes()

    -- Restore previous state
    self.scrub_mode = false
    self.scrub_loop = false
    self.scrub_start = nil
    self.scrub_end = nil
    self.scrub_length = nil

    -- Restore playback position and loop points
    if saved_step then
        self.step = saved_step
    end
    if saved_seq_start then
        self.seq_start = saved_seq_start
    end
    if saved_seq_length then
        self.seq_length = saved_seq_length
    end
end

return Auto