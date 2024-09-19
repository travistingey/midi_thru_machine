-- This script is used to add state-based logic and LED feedback for the LaunchControl XL

-- These buttons are associated with the top and bottom channels and a group of states.
local MUTE = 1
local SOLO = 2
local ARM = 3
local SEND = 4 -- CC toggle used for sending tracks for resampling on BitBox
local CUE = 5

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

-- Using bottom channel to show states of either CUE(Device), MUTE, SOLO and ARM)
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
NOTE_MAP[124] = {type='device'} -- Mapping device button to CUE state
NOTE_MAP[125] = {type='mute'}
NOTE_MAP[126] = {type='solo'}
NOTE_MAP[127] = {type='arm'}

local CC_MAP = {}
CC_MAP['top_encoders'] = {13,14,15,16,17,18,19,20}
CC_MAP['middle_encoders'] = {29,30,31,32,33,34,35,36}
CC_MAP['bottom_encoders'] = {49,50,51,52,53,54,55,56}
CC_MAP['faders'] = {77,78,79,80,81,82,83,84}

CC_MAP[SEND] = {0,1,2,3,4,5,6,7}
CC_MAP[CUE] = {100,101,102,103,104,105,106,107}
CC_MAP[SOLO] = {58,59,60,61,62,63,64,65}
CC_MAP[MUTE] = {37,38,39,40,41,42,43,44}
CC_MAP[ARM] = {86,87,88,89,90,91,92,93}

local LaunchControl = {
    device = {}, -- Device represents the second MIDI device used for SysEx Messages
    state = MUTE,
    toggle = {[UP] = false, [DOWN] = true},
    track = {},
    cc_map = CC_MAP,
    note_map = NOTE_MAP 
}

-- Initialize track states
for i = 1, TRACKCOUNT do
    LaunchControl.track[i] = { [CUE] = false, [MUTE] = false, [SOLO] = false, [ARM] = false, [SEND] = false, [UP] = false, [DOWN] = true }
end


function LaunchControl:handle_note(data)
    if self.note_map[data.note] then
        local control = self.note_map[data.note]
        if control.type == 'top_channel' then
            local state = not self.track[control.index][SEND]
		    self.track[control.index][SEND] = state

            local send = {
                type = 'cc',
                val = state and 127 or 0,
            }

            send.cc = self.cc_map[SEND][control.index]

            return send

        elseif control.type == 'bottom_channel' then

            local state = not self.track[control.index][self.state]
		    self.track[control.index][self.state] = state

            local send = {
                type = 'cc',
                val = state and 127 or 0,
            }

            send.cc = self.cc_map[self.state][control.index]

            return send
        elseif control.type == 'device' then 
            self.state = CUE
        elseif control.type == 'mute'then 
            self.state = MUTE
        elseif control.type == 'solo'then 
            self.state = SOLO
        elseif control.type == 'arm' then
            self.state = ARM
        elseif control.type == 'up' then
            self.toggle[UP] = not self.toggle[UP]

            if self.on_up ~= nil then
                self:on_up(self.toggle[UP])
            end
        elseif control.type == 'down' then
            self.toggle[DOWN] = not self.toggle[DOWN]

            if self.on_down ~= nil then
                self:on_down(self.toggle[DOWN])
            end
        end

    elseif control.type == 'left' then
        self.toggle[LEFT] = not self.toggle[LEFT]

        if self.on_left ~= nil then
            self:on_left(self.toggle[LEFT])
        end
    elseif control.type == 'right' then
        self.toggle[RIGHT] = not self.toggle[RIGHT]

        if self.on_right ~= nil then
            self:on_right(self.toggle[RIGHT])
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

    local led = {}

    for i = 1, 8 do
        if t[i][SOLO] then 
            led[i] = GREEN_HIGH
        elseif t[i][MUTE] then
            led[i] = 0
        elseif t[i][CUE] then
            led[i] = YELLOW
        elseif t[i][ARM] then
            led[i] = RED_HIGH
        else
            led[i] = GREEN_LOW
        end
    end

    local sysex_message = {
        240, 0, 32, 41, 2, 17, 120, 0, 
        0, led[1], 1, led[2], 2, led[3], 3, led[4], 4, led[5], 5, led[6], 6, led[7], 7, led[8],     -- Top row knobs bright green
        8, led[1], 9, led[2], 10, led[3], 11, led[4], 12, led[5], 13, led[6], 14, led[7], 15, led[8], -- Middle row knobs bright green
        16, led[1], 17, led[2], 18, led[3], 19, led[4], 20, led[5], 21, led[6], 22, led[7], 23, led[8], -- Bottom row knobs bright green
        24, (t[1][SEND] and GREEN_HIGH or 0), 25, (t[2][SEND] and GREEN_HIGH or 0), 26, (t[3][SEND] and GREEN_HIGH or 0), 27, (t[4][SEND] and GREEN_HIGH or 0), 28, (t[5][SEND] and GREEN_HIGH or 0), 29, (t[6][SEND] and GREEN_HIGH or 0), 30, (t[7][SEND] and GREEN_HIGH or 0), 31, (t[8][SEND] and GREEN_HIGH or 0), -- Top channel buttons low amber
        32, led[1], 33, led[2], 34, led[3], 35, led[4], 36, led[5], 37, led[6], 38, led[7], 39, led[8], -- Bottom channel buttons full green
        40, (self.state == CUE and GREEN_HIGH or 0), -- Device off
        41, (self.state == MUTE and GREEN_HIGH or 0), -- Mute button full
        42, (self.state == SOLO and GREEN_HIGH or 0), -- Solo button low
        43, (self.state == ARM and GREEN_HIGH or 0), -- Record Arm button low
        44, (self.toggle[UP] and RED_HIGH or 0), -- Up
        45, (self.toggle[DOWN] and RED_HIGH or 0), -- Down
        46, 0, -- LEFT off
        47, 0, -- RIGHT off
        247
    }

    self.device:send(sysex_message)
end

function LaunchControl:register(n)
	self.device.event = nil
	self.device = midi.connect(n)
end

return LaunchControl