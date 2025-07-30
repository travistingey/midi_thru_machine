-- This script is used to add state-based logic and LED feedback for the LaunchControl XL

-- These buttons are associated with the top and bottom channels and a group of states.
local MUTE = 1
local SOLO = 2
local ARM = 3
local SEND = 4 -- CC toggle used for sending tracks for resampling on BitBox
local DEVICE = 5

-- Using arrows as a toggle state
local UP = 6
local DOWN = 7
local LEFT = 8
local RIGHT = 9

local RED_LOW = 13
local RED_HIGH = 15
local AMBER_LOW = 29
local AMBER_HIGH = 63 
local YELLOW = 62
local GREEN_LOW = 28
local GREEN_HIGH = 60

local TRACKCOUNT = 16

local NOTE_MAP = {}

-- Using top channel row to show SEND state per track
NOTE_MAP[0] = {type='top_channel', index = 1}
NOTE_MAP[1] = {type='top_channel', index = 2}
NOTE_MAP[2] = {type='top_channel', index = 3}
NOTE_MAP[3] = {type='top_channel', index = 4}
NOTE_MAP[4] = {type='top_channel', index = 5}
NOTE_MAP[5] = {type='top_channel', index = 6}
NOTE_MAP[6] = {type='top_channel', index = 7}
NOTE_MAP[7] = {type='top_channel', index = 8}

-- Using bottom channel to show states of either DEVICE, MUTE, SOLO and ARM)
NOTE_MAP[12] = {type='bottom_channel', index = 1}
NOTE_MAP[13] = {type='bottom_channel', index = 2}
NOTE_MAP[14] = {type='bottom_channel', index = 3}
NOTE_MAP[15] = {type='bottom_channel', index = 4}
NOTE_MAP[16] = {type='bottom_channel', index = 5}
NOTE_MAP[17] = {type='bottom_channel', index = 6}
NOTE_MAP[18] = {type='bottom_channel', index = 7}
NOTE_MAP[19] = {type='bottom_channel', index = 8}
    
NOTE_MAP[120] = {type='up'}
NOTE_MAP[121] = {type='down'}
NOTE_MAP[122] = {type='left'}
NOTE_MAP[123] = {type='right'}
NOTE_MAP[124] = {type='device'} -- Mapping device button to DEVICE state
NOTE_MAP[125] = {type='mute'}
NOTE_MAP[126] = {type='solo'}
NOTE_MAP[127] = {type='arm'}

local CC_MAP = {}


-- Main Channel CC (Fixed)
CC_MAP[SEND] = {81,82,83,84,85,86,87,88}
CC_MAP[SOLO] = {89,90,91,92,93,94,95,96}
CC_MAP[MUTE] = {97,98,99,100,101,102,103,104}
CC_MAP[ARM] = {105,106,107,108,109,110,111,112}

-- Channel CC
CC_MAP['top_encoders'] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16} 
CC_MAP['middle_encoders'] = {17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32} 
CC_MAP['bottom_encoders'] = {33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48} 
CC_MAP['faders'] = {49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64}
CC_MAP[DEVICE] = {65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80}

local CONTROL_MAP = {
    [13] = { index = 1, type = 'top_encoders'},
    [14] = { index = 2, type = 'top_encoders'},
    [15] = { index = 3, type = 'top_encoders'},
    [16] = { index = 4, type = 'top_encoders'},
    [17] = { index = 5, type = 'top_encoders'},
    [18] = { index = 6, type = 'top_encoders'},
    [19] = { index = 7, type = 'top_encoders'},
    [20] = { index = 8, type = 'top_encoders'},
    [29] = { index = 1, type = 'middle_encoders'},
    [30] = { index = 2, type = 'middle_encoders'},
    [31] = { index = 3, type = 'middle_encoders'},
    [32] = { index = 4, type = 'middle_encoders'},
    [33] = { index = 5, type = 'middle_encoders'},
    [34] = { index = 6, type = 'middle_encoders'},
    [35] = { index = 7, type = 'middle_encoders'},
    [36] = { index = 8, type = 'middle_encoders'}, 
    [49] = { index = 1, type = 'bottom_encoders'},
    [50] = { index = 2, type = 'bottom_encoders'},
    [51] = { index = 3, type = 'bottom_encoders'},
    [52] = { index = 4, type = 'bottom_encoders'},
    [53] = { index = 5, type = 'bottom_encoders'},
    [54] = { index = 6, type = 'bottom_encoders'},
    [55] = { index = 7, type = 'bottom_encoders'},
    [56] = { index = 8, type = 'bottom_encoders'},
    [77] = { index = 1, type = 'faders'},
    [78] = { index = 2, type = 'faders'},
    [79] = { index = 3, type = 'faders'},
    [80] = { index = 4, type = 'faders'},
    [81] = { index = 5, type = 'faders'},
    [82] = { index = 6, type = 'faders'},
    [83] = { index = 7, type = 'faders'},
    [84] = { index = 8, type = 'faders'}
}

local REVERSE_CONTROL_MAP = {}

-- Build the reverse lookup for each group in CONTROL_MAP
for physical_cc, info in pairs(CONTROL_MAP) do
  local group = info.type
  local base_index = info.index
  -- For both track_select 1 (offset 0) and 2 (offset 8)
  for offset = 0, 8, 8 do
    local mapped_cc = CC_MAP[group][base_index + offset]
    if mapped_cc then
        REVERSE_CONTROL_MAP[mapped_cc] = physical_cc
    end
  end
end

local LaunchControl = {
    device = {},
    state = MUTE,
    track = {},
    down = {},
    last_values = {},
    channel_values = {},
    channel_sends = {},
    cc_map = CC_MAP,
    control_map = CONTROL_MAP,
    track_select = 1,
    note_map = NOTE_MAP,
    main_channel = 1,
    channel = 1,
    cleanup_functions = {},
    send_active = false,
    last_led_time = 0,
    led_interval = 0.02,
}

-- Initialize tables
for i = 1, TRACKCOUNT do
    LaunchControl.track[i] = { [DEVICE] = false, [MUTE] = false, [SOLO] = false, [ARM] = false, [SEND] = false, [UP] = false, [DOWN] = true }
end

for ch = 1, TRACKCOUNT do
    LaunchControl.channel_values[ch] = {}
end 



function LaunchControl:handle_note(data)
    
    if self.note_map[data.note] then
        
        local control = self.note_map[data.note]
        local track_offset = (self.track_select - 1) * 8
        
        
        if data.type == 'note_on' then
            self.down[control.type] = true

            if control.type == 'top_channel' then
                local new_state = not self.track[control.index][SEND]
                self.track[control.index][SEND] = new_state
                local fader_cc = self.cc_map.faders[control.index]
                local send_cc = self.cc_map[SEND][control.index]
                local current_channel = self.channel

                if new_state then
                    local fader_value = self.channel_values[current_channel][fader_cc]
                    -- When toggling ON
                    local main_fader = {
                        type = 'cc',
                        val = 0,
                        ch = current_channel,
                        cc = fader_cc
                    }

                    local send_fader = {
                        type = 'cc',
                        val = fader_value,
                        ch = current_channel,
                        cc = send_cc
                    }

                    -- Then send the toggle message 
                    self.send_active = true
                    local toggle_msg = {
                        type = 'cc',
                        ch = current_channel,
                        cc = 127,
                        val = 127
                    }

                    self.channel_values[current_channel][send_cc] = fader_value
                    self.channel_values[current_channel][fader_cc] = 0
                    self:set_led(true)
                    return { main_fader, send_fader, toggle_msg }
                else
                    local fader_value = self.channel_values[current_channel][send_cc]
                   
                    -- When toggling OFF
                    local send_fader = {
                        type = 'cc',
                        val = 0,
                        ch = current_channel,
                        cc = send_cc
                    }


                    local main_fader = {
                        type = 'cc',
                        val = fader_value,
                        ch = current_channel,
                        cc = fader_cc
                    }
                    
                    self.channel_values[current_channel][fader_cc] = fader_value
                    self.channel_values[current_channel][send_cc] = 0

                    local toggle_msg = {
                        type = 'cc',
                        ch = current_channel,
                        cc = 127,
                        val = 0
                    }

                    for i,track in ipairs(self.track) do
                        if track[SEND] then
                            toggle_msg.val = 127
                            break
                        elseif i == TRACKCOUNT then
                            self.send_active = false
                        end
                    end
                    
                    self:set_led(true)
                    return { send_fader, main_fader, toggle_msg }
                end

            elseif control.type == 'bottom_channel' then
                if self.down['device'] then
                    self:set_channel(control.index + track_offset)
                    return
                end

                local send = {
                    type = 'cc'
                }
                
                if self.state == DEVICE then
                    local state = not self.track[control.index + track_offset][self.state]
                    self.track[control.index  + track_offset][self.state] = state
                    send.ch = self.channel
                    send.cc = self.cc_map[DEVICE][control.index  + track_offset]
                    send.val =  state and 127 or 0
                else
                    local state = not self.track[control.index][self.state]
                    self.track[control.index][self.state] = state
                    send.ch = self.main_channel
                    send.cc = self.cc_map[self.state][control.index]
                    send.val =  state and 127 or 0
                end
                
                self:set_led(true)
                return send

            elseif control.type == 'device' then 
                self.state = DEVICE
            elseif control.type == 'mute'then 
                self.state = MUTE
            elseif control.type == 'solo'then 
                self.state = SOLO
            elseif control.type == 'arm' then
                self.state = ARM
            elseif control.type == 'left' then
                self:set_channel(1)
                self:set_track(1)
            elseif control.type == 'right' then
                self:set_channel(2)
                self:set_track(1)
            elseif control.type == 'up' then
                self:set_track(1)
            elseif control.type == 'down' then
                self:set_track(2)
            end

            self:set_led(true)
        else
            self.down[control.type] = false
            if control.type == 'device' then
                self:set_led(true)
            end
        end
    end
end

function LaunchControl:set_led(force)
    
    local now = os.clock()
    
    if not force and now - self.last_led_time < self.led_interval then
        return
    end

    self.last_led_time = now
    local t = self.track
    local s = self.state
    local HIGH = RED_LOW
    local LOW = RED_LOW
    
    local track_offset = (self.track_select - 1) * 8

    if s == MUTE then
        HIGH = 0
    end
    if s == SOLO then
        HIGH = GREEN_LOW
    end
    if s == ARM then
        HIGH = RED_HIGH
    end

    -- Compute LED states for encoders and faders based on soft takeover
    local top_encoder_leds = {}
    for i = 1, 8 do
        local cc = self.cc_map.top_encoders[i + track_offset]
        local orig_cc = REVERSE_CONTROL_MAP[cc] or cc
        local last = self.last_values[orig_cc]
        local target = self.channel_values[self.channel][cc]
        if last == nil or target == nil then
            top_encoder_leds[i] = 0
        elseif last ~= target then
            top_encoder_leds[i] = RED_LOW
        elseif last > target then
            top_encoder_leds[i] = AMBER_LOW
        else
            top_encoder_leds[i] = GREEN_HIGH
        end
    end

    local middle_encoder_leds = {}
    for i = 1, 8 do
        local cc = self.cc_map.middle_encoders[i + track_offset]
        local orig_cc = REVERSE_CONTROL_MAP[cc] or cc
        local last = self.last_values[orig_cc]
        local target = self.channel_values[self.channel][cc]
        if last == nil or target == nil then
            middle_encoder_leds[i] = 0
        elseif last < target then
            middle_encoder_leds[i] = RED_LOW
        elseif last > target then
            middle_encoder_leds[i] = AMBER_LOW
        else
            middle_encoder_leds[i] = GREEN_HIGH
        end
    end

    local bottom_encoder_leds = {}
    for i = 1, 8 do
        local cc = self.cc_map.bottom_encoders[i + track_offset]
        local orig_cc = REVERSE_CONTROL_MAP[cc] or cc
        local last = self.last_values[orig_cc]
        local target = self.channel_values[self.channel][cc]
        if last == nil or target == nil then
            bottom_encoder_leds[i] = 0
        elseif last < target then
            bottom_encoder_leds[i] = RED_LOW
        elseif last > target then
            bottom_encoder_leds[i] = AMBER_LOW
        else
            bottom_encoder_leds[i] = GREEN_HIGH
        end
    end

    -- For faders, if soft takeover is active, show RED_HIGH; otherwise, normal (GREEN_HIGH)
    local top_channel_leds = {}
    for i = 1, 8 do
        local cc = self.cc_map.faders[i + track_offset]
        local orig_cc = REVERSE_CONTROL_MAP[cc] or cc
        local last = self.last_values[orig_cc]

        
        if last ~= nil and self.channel_values[self.channel][cc] ~= nil and last < self.channel_values[self.channel][cc] then
            top_channel_leds[i] = t[i][SEND] and AMBER_HIGH or AMBER_LOW
        else
            top_channel_leds[i] = (t[i][SEND] and GREEN_HIGH or 0)
        end
    end

    -- LED feedback for bottom channel buttons (unchanged from before)
    local bottom_channel_leds = {}
    for i = 1, 8 do
        local track_index = i + track_offset
        local cc = CC_MAP['faders'][track_index]
        local orig_cc = REVERSE_CONTROL_MAP[cc] or cc
        local last = self.last_values[orig_cc]

        if self.down['device'] then
            bottom_channel_leds[i] = 0
            if self.channel == i then
                bottom_channel_leds[i] = RED_HIGH
            end
        elseif last == nil or self.channel_values[self.channel][cc] == nil then
            bottom_channel_leds[i] = 0
        elseif last > self.channel_values[self.channel][cc] then
            local state = t[track_index][SOLO] or not t[track_index][MUTE] or t[track_index][DEVICE] or t[track_index][ARM]
            bottom_channel_leds[i] = state and AMBER_HIGH or AMBER_LOW
        elseif t[track_index][SOLO] then 
            bottom_channel_leds[i] = t[track_index][ARM] and RED_HIGH or GREEN_HIGH
        elseif t[track_index][MUTE] then
            bottom_channel_leds[i] = 0
        elseif t[track_index][DEVICE] then
            bottom_channel_leds[i] = YELLOW
        elseif t[track_index][ARM] then
            bottom_channel_leds[i] = RED_LOW
        else
            bottom_channel_leds[i] = GREEN_LOW
        end
    end

    -- Construct the SysEx message with updated LED rows:
    local sysex_message = {
        240, 0, 32, 41, 2, 17, 120, 0,
        -- Top row: top_encoders
        0, top_encoder_leds[1], 1, top_encoder_leds[2], 2, top_encoder_leds[3], 3, top_encoder_leds[4],
        4, top_encoder_leds[5], 5, top_encoder_leds[6], 6, top_encoder_leds[7], 7, top_encoder_leds[8],
        -- Middle row: middle_encoders
        8, middle_encoder_leds[1], 9, middle_encoder_leds[2], 10, middle_encoder_leds[3], 11, middle_encoder_leds[4],
        12, middle_encoder_leds[5], 13, middle_encoder_leds[6], 14, middle_encoder_leds[7], 15, middle_encoder_leds[8],
        -- Bottom row: bottom_encoders
        16, bottom_encoder_leds[1], 17, bottom_encoder_leds[2], 18, bottom_encoder_leds[3], 19, bottom_encoder_leds[4],
        20, bottom_encoder_leds[5], 21, bottom_encoder_leds[6], 22, bottom_encoder_leds[7], 23, bottom_encoder_leds[8],
        -- Top channel buttons  used for fader LED feedback
        24, top_channel_leds[1], 25, top_channel_leds[2], 26, top_channel_leds[3], 27, top_channel_leds[4],
        28, top_channel_leds[5], 29, top_channel_leds[6], 30, top_channel_leds[7], 31, top_channel_leds[8],
        -- Bottom channel buttons 
        32, bottom_channel_leds[1], 33, bottom_channel_leds[2], 34, bottom_channel_leds[3], 35, bottom_channel_leds[4],
        36, bottom_channel_leds[5], 37, bottom_channel_leds[6], 38, bottom_channel_leds[7], 39, bottom_channel_leds[8],
        -- Device and other buttons
        40, (self.state == DEVICE and GREEN_HIGH or 0),
        41, (self.state == MUTE and GREEN_HIGH or 0),
        42, (self.state == SOLO and GREEN_HIGH or 0),
        43, (self.state == ARM and GREEN_HIGH or 0),
        44, (self.track_select == 1  and RED_HIGH or 0),
        45, (self.track_select == 2  and RED_HIGH or 0),
        46, (self.channel == 1 and RED_HIGH or 0),
        47, (self.channel == 2 and RED_HIGH or 0),
        247
    }
    self.device:send(sysex_message)
end

function LaunchControl:register(n)
    self.device = midi.connect(n)
    self:set_led(true)
end

-- Set the active channel (for soft takeover and routing)
function LaunchControl:set_channel(new_channel)
    self.channel = new_channel 
    self:set_led()  -- update LED feedback after channel change
end

function LaunchControl:set_track(track)
    self.track_select = track
    self:set_led()  -- update LED feedback after channel change
end

-- Handle incoming CC messages with soft takeover logic
-- Updates the last_values table with the physical control's value
-- Compares against the stored target in channel_values for the active channel
-- If they do not match, no CC is sent
function LaunchControl:handle_cc(data)
    
    local current_channel = self.channel
    local control = CONTROL_MAP[data.cc]
    local offset = (self.track_select - 1) * 8
    local cc = nil
    if control and control.type == 'faders' then
        local track_index = control.index + offset
        if self.track[track_index] and self.track[track_index][SEND] then
            cc = self.cc_map[SEND][control.index + offset]
        else
            cc = self.cc_map.faders[control.index + offset]
        end
    else
        cc = self.cc_map[control.type][control.index + offset]
    end

    local target = self.channel_values[current_channel][cc]
    local last = self.last_values[data.cc]  
    self.last_values[data.cc] = data.val
    
    if target == nil or last == nil or data.val == target or last == target then
        self.channel_values[current_channel][cc] = data.val
        self:set_led()
        return { type = 'cc', cc = cc, val = data.val, ch = self.channel}
    else
        self:set_led()
        return
    end
end

return LaunchControl