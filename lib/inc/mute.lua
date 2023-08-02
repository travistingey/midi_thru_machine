local path_name = 'Foobar/lib/'
local App = require(path_name .. 'app')

Mute = {
    grid_start = {x = 1, y = 1},
    grid_end = {x = 4, y = 4},
    state = {},
    grid_map = {},
    note_map = {
        [36] = {x = 1, y = 1, index = 1},
        [37] = {x = 2, y = 1, index = 2},
        [38] = {x = 3, y = 1, index = 3},
        [39] = {x = 4, y = 1, index = 4},
        [40] = {x = 1, y = 2, index = 5},
        [41] = {x = 2, y = 2, index = 6},
        [42] = {x = 3, y = 2, index = 7},
        [43] = {x = 4, y = 2, index = 8},
        [44] = {x = 1, y = 3, index = 9},
        [45] = {x = 2, y = 3, index = 10},
        [46] = {x = 3, y = 3, index = 11},
        [47] = {x = 4, y = 3, index = 12},
        [48] = {x = 1, y = 4, index = 13},
        [49] = {x = 2, y = 4, index = 14},
        [50] = {x = 3, y = 4, index = 15},
        [51] = {x = 4, y = 4, index = 16}
    },
    build_map = function()
        Mute.note_map = {}
        Mute.grid_map = {}

        for i = 1, 16 do
            Mute.grid_map[(i-1) % 4 + 1] = {}

            local note = params:get('mute_' .. i ..'_note')
            local channel = params:get('mute_' .. i .. '_channel')
            Mute.grid_map[(i-1) % 4 + 1][math.floor( (i-1) / 4 ) + 1] = {note = note, index = i, channel = channel}
            Mute.note_map[note] = {x =(i-1) % 4 + 1, y= math.floor( (i-1) / 4 ) + 1, index = i, channel = channel}

        end

        Mute.grid_map[1][1] = {note = params:get('mute_1_note'), index = 1, channel = params:get('mute_1_channel')}
        Mute.grid_map[2][1] = {note = 37, index = 2}
        Mute.grid_map[3][1] = {note = 38, index = 3}
        Mute.grid_map[4][1] = {note = 39, index = 4}
        Mute.grid_map[1][2] = {note = 40, index = 5}
        Mute.grid_map[2][2] = {note = 41, index = 6}
        Mute.grid_map[3][2] = {note = 42, index = 7}
        Mute.grid_map[4][2] = {note = 43, index = 8}
        Mute.grid_map[1][3] = {note = 44, index = 9}
        Mute.grid_map[2][3] = {note = 45, index = 10}
        Mute.grid_map[3][3] = {note = 46, index = 11}
        Mute.grid_map[4][3] = {note = 47, index = 12}
        Mute.grid_map[1][4] = {note = 48, index = 13}
        Mute.grid_map[2][4] = {note = 49, index = 14}
        Mute.grid_map[3][4] = {note = 50, index = 15}
        Mute.grid_map[4][4] = {note = 51, index = 16}

    end,
    midi_event = function(data)
        local alt = App:get_alt()
        -- react only to drum pads
        if data.ch == 10 and Mute.note_map[data.note] then
            local target = Mute.note_map[data.note]
    
            if (not Mute.state[data.note]) then
                
                -- Mute is off
                if data.type == 'note_on' then
                    App.grid.led[target.x][target.y] = 3 -- note_on unmuted.
                elseif data.type == 'note_off' then
                    App.grid.led[target.x][target.y] = 0 -- note_on unmuted.
                end
            else
                -- Mute is on
                App.midi_out:note_off(data.note, 64, 10)
                if data.type == 'note_on' then
                    App.grid.led[target.x][target.y] = MidiGrid.rainbow_on[App.preset] -- note_on muted.
                    data.type = 'note_off'
                elseif data.type == 'note_off' then
                    App.grid.led[target.x][target.y] = MidiGrid.rainbow_off[App.preset] -- note_off muted.
                end
            end
        end
    end,
    grid_event = function (s, data)
        -- Mute are used to prevent incoming MIDI notes from passing through.
        -- Based on toggle state

        local x = data.x
        local y = data.y
        local alt = App:get_alt()
    
        if data.state and MidiGrid.in_bounds(data, Mute.bounds) then
    
            if alt then 
                App:set_alt(false)
            else
                local index = Mute.grid_map[x][y].note
                Mute.state[index] = s.toggled[x][y]
        
                if Mute.state[index] then 
                    App.grid.led[x][y] = MidiGrid.rainbow_off[App.preset]
                else
                    App.grid.led[x][y] = 0
                end
                
                if Mute.state[index] and Mute.note_map[index].x == data.x and Mute.note_map[index].y == data.y then
                    App.midi_out:note_off(App.chord.last_note,0,14)
                end
        
            end
	        
        end
    end,
    bounds = MidiGrid.get_bounds({x = 1, y = 1}, {x = 4, y = 4}),
    set_grid = function ()
        for i, state in pairs(Mute.state) do
            local x = Mute.note_map[i].x
            local y = Mute.note_map[i].y

            if state then
                App.grid.led[x][y] = MidiGrid.rainbow_off[App.preset]
            else
                App.grid.led[x][y] = 0
            end
        end
    end
}



for i = 1, 4 do Mute.grid_map[i] = {} end

Mute.grid_map[1][1] = {note = 36, index = 1}
Mute.grid_map[2][1] = {note = 37, index = 2}
Mute.grid_map[3][1] = {note = 38, index = 3}
Mute.grid_map[4][1] = {note = 39, index = 4}
Mute.grid_map[1][2] = {note = 40, index = 5}
Mute.grid_map[2][2] = {note = 41, index = 6}
Mute.grid_map[3][2] = {note = 42, index = 7}
Mute.grid_map[4][2] = {note = 43, index = 8}
Mute.grid_map[1][3] = {note = 44, index = 9}
Mute.grid_map[2][3] = {note = 45, index = 10}
Mute.grid_map[3][3] = {note = 46, index = 11}
Mute.grid_map[4][3] = {note = 47, index = 12}
Mute.grid_map[1][4] = {note = 48, index = 13}
Mute.grid_map[2][4] = {note = 49, index = 14}
Mute.grid_map[3][4] = {note = 50, index = 15}
Mute.grid_map[4][4] = {note = 51, index = 16}