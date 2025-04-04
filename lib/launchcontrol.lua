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

local TRACKCOUNT = 8

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
CC_MAP['top_encoders'] = {13,14,15,16,17,18,19,20}
CC_MAP['middle_encoders'] = {29,30,31,32,33,34,35,36}
CC_MAP['bottom_encoders'] = {49,50,51,52,53,54,55,56}
CC_MAP['faders'] = {77,78,79,80,81,82,83,84}

CC_MAP[SEND] = {0,1,2,3,4,5,6,7}
CC_MAP[DEVICE] = {100,101,102,103,104,105,106,107}
CC_MAP[SOLO] = {58,59,60,61,62,63,64,65}
CC_MAP[MUTE] = {37,38,39,40,41,42,43,44}
CC_MAP[ARM] = {86,87,88,89,90,91,92,93}

local LaunchControl = {
    device = {},
    state = MUTE,
    track = {},
    down = {},
    last_values = {},
    channel_values = {},
    channel_sends = {},
    cc_map = CC_MAP,
    note_map = NOTE_MAP,
    main_channel = 1,
    channel = 1,
    cleanup_functions = {}
}

-- Initialize tables
for i = 1, TRACKCOUNT do
    LaunchControl.track[i] = { [DEVICE] = false, [MUTE] = false, [SOLO] = false, [ARM] = false, [SEND] = false, [UP] = false, [DOWN] = true }
end

for ch = 1, TRACKCOUNT do
    LaunchControl.channel_values[ch] = {}
    LaunchControl.channel_sends[ch] = {output = true, input = false }
end 



function LaunchControl:handle_note(data)
    
    if self.note_map[data.note] then
        
        local control = self.note_map[data.note]
        
        if data.type == 'note_on' then
            self.down[control.type] = true
            if control.type == 'top_channel' then
                local state = not self.track[control.index][SEND]
                self.track[control.index][SEND] = state

                local send = {
                    type = 'cc',
                    val = state and 127 or 0,
                    ch = self.main_channel
                }

                send.cc = self.cc_map[SEND][control.index]
                
                return send

            elseif control.type == 'bottom_channel' then
                if self.down['device'] then
                    self:set_channel(control.index)
                    return
                end

                local state = not self.track[control.index][self.state]
                self.track[control.index][self.state] = state

                local send = {
                    type = 'cc',
                    val = state and 127 or 0,
                }
                
                if self.state == DEVICE then
                    send.ch = self.channel
                else
                    send.ch = self.main_channel
                end

                send.cc = self.cc_map[self.state][control.index]
                
                return send

            elseif control.type == 'device' then 
                self.state = DEVICE
            elseif control.type == 'mute'then 
                self.state = MUTE
            elseif control.type == 'solo'then 
                self.state = SOLO
            elseif control.type == 'arm' then
                self.state = ARM
            elseif control.type == 'up' then
                local state = self.channel_sends[self.channel].output
                self.channel_sends[self.channel].output = not state
            elseif control.type == 'down' then
                local state = self.channel_sends[self.channel].input
                self.channel_sends[self.channel].input = not state
            elseif control.type == 'left' and self.channel > 1 then
                self:set_channel(self.channel - 1)
            elseif control.type == 'right' and self.channel < TRACKCOUNT then
                self:set_channel(self.channel + 1)
            end
        else
            self.down[control.type] = false
        end
    end
end

function LaunchControl:set_led()
    local t = self.track
    local s = self.state
    local HIGH = YELLOW
    local LOW = YELLOW
    
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
    for i, cc in ipairs(self.cc_map.top_encoders) do
        if self.last_values[cc] == nil or self.channel_values[self.channel][cc] == nil then
            top_encoder_leds[i] = 0
        elseif self.last_values[cc] ~= self.channel_values[self.channel][cc] then
            top_encoder_leds[i] = AMBER_HIGH
        else
            top_encoder_leds[i] = GREEN_HIGH
        end
    end

    local middle_encoder_leds = {}
    for i, cc in ipairs(self.cc_map.middle_encoders) do
        if self.last_values[cc] == nil or self.channel_values[self.channel][cc] == nil then
            middle_encoder_leds[i] = 0
        elseif self.last_values[cc] ~= self.channel_values[self.channel][cc] then
            middle_encoder_leds[i] = AMBER_HIGH
        else
            middle_encoder_leds[i] = GREEN_HIGH
        end
    end

    local bottom_encoder_leds = {}
    for i, cc in ipairs(self.cc_map.bottom_encoders) do
        if self.last_values[cc] == nil or self.channel_values[self.channel][cc] == nil then
            bottom_encoder_leds[i] = 0
        elseif self.last_values[cc] ~= self.channel_values[self.channel][cc] then
            bottom_encoder_leds[i] = AMBER_HIGH
        else
            bottom_encoder_leds[i] = GREEN_HIGH
        end
    end

    -- For faders, if soft takeover is active, show RED_HIGH; otherwise, normal (GREEN_HIGH)
    local top_channel_leds = {}
    for i, cc in ipairs(self.cc_map.faders) do
        if self.last_values[cc] ~= nil and self.channel_values[self.channel][cc] ~= nil and self.last_values[cc] < self.channel_values[self.channel][cc] then
            top_channel_leds[i] = AMBER_HIGH
        else
            top_channel_leds[i] = (t[i][SEND] and GREEN_HIGH or 0)
        end
    end

    -- LED feedback for bottom channel buttons (unchanged from before)
    local bottom_channel_leds = {}
    for i = 1, 8 do

        
        local cc = CC_MAP['faders'][i]
        if self.down['device'] then
            bottom_channel_leds[i] = 0

            if self.channel == i then
                bottom_channel_leds[i] = RED_HIGH
            end
        elseif self.last_values[cc] == nil or self.channel_values[self.channel][cc] == nil then
            bottom_channel_leds[i] = 0
        elseif self.last_values[cc] > self.channel_values[self.channel][cc] then
            bottom_channel_leds[i] = AMBER_HIGH
        elseif t[i][SOLO] then 
            bottom_channel_leds[i] = GREEN_HIGH
        elseif t[i][MUTE] then
            bottom_channel_leds[i] = 0
        elseif t[i][DEVICE] then
            bottom_channel_leds[i] = YELLOW
        elseif t[i][ARM] then
            bottom_channel_leds[i] = RED_HIGH
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
        -- Top channel buttons now used for fader LED feedback
        24, top_channel_leds[1], 25, top_channel_leds[2], 26, top_channel_leds[3], 27, top_channel_leds[4],
        28, top_channel_leds[5], 29, top_channel_leds[6], 30, top_channel_leds[7], 31, top_channel_leds[8],
        -- Bottom channel buttons (unchanged)
        32, bottom_channel_leds[1], 33, bottom_channel_leds[2], 34, bottom_channel_leds[3], 35, bottom_channel_leds[4],
        36, bottom_channel_leds[5], 37, bottom_channel_leds[6], 38, bottom_channel_leds[7], 39, bottom_channel_leds[8],
        -- Device and other buttons
        40, (self.state == DEVICE and GREEN_HIGH or 0),
        41, (self.state == MUTE and GREEN_HIGH or 0),
        42, (self.state == SOLO and GREEN_HIGH or 0),
        43, (self.state == ARM and GREEN_HIGH or 0),
        44, (self.channel_sends[self.channel].output and RED_HIGH or 0),
        45, (self.channel_sends[self.channel].input and RED_HIGH or 0),
        46, (self.channel > 1 and RED_HIGH or 0),
        47, (self.channel < TRACKCOUNT and RED_HIGH or 0),
        247
    }

    self.device:send(sysex_message)
end

function LaunchControl:register(n)
    self.device = midi.connect(n)
    self:set_led()
end

-- Set the active channel (for soft takeover and routing)
function LaunchControl:set_channel(new_channel)
    self.channel = new_channel 
    self:set_led()  -- update LED feedback after channel change
end

-- Handle incoming CC messages with soft takeover logic
-- Updates the last_values table with the physical control's value
-- Compares against the stored target in channel_values for the active channel
-- If they do not match, no CC is sent
function LaunchControl:handle_cc(data)
    
    local current_channel = self.channel
    local target = self.channel_values[current_channel][data.cc]
    local last = self.last_values[data.cc]  
    self.last_values[data.cc] = data.val
    
    if target == nil or last == nil or data.val == target or last == target then
        self.channel_values[current_channel][data.cc] = data.val
        self:set_led()
        if self.channel_sends[current_channel].output == true or self.channel_sends[current_channel].input == true then
            return { type = 'cc', cc = data.cc, val = data.val, ch = self.channel, send_input = self.channel_sends[current_channel].input, send_output = self.channel_sends[current_channel].output}
        end
    else
        self:set_led()
        return
    end
end

return LaunchControl