Mute = {
    grid_start = {x = 1, y = 1},
    grid_end = {x = 4, y = 4},
    state = {},
    transport_event = function(data)
        local alt = get_alt()
        -- react only to drum pads
        if data.ch == 10 and drum_map[data.note] then
            local target = drum_map[data.note]
    
            if (not Mute.state[data.note]) then
                drum_map[data.note].state = true
                
                -- Mute is off
                if data.type == 'note_on' then
                    g.led[target.x][target.y] = 3 -- note_on unmuted.
                elseif data.type == 'note_off' then
                    g.led[target.x][target.y] = 0 -- note_on unmuted.
                end
            else
                -- Mute is on
                drum_map[data.note].state = false
    
                midi_out:note_off(data.note, 64, 10)
                if data.type == 'note_on' then
                    g.led[target.x][target.y] = rainbow_on[Preset.select] -- note_on muted.
                    data.type = 'note_off'
                elseif data.type == 'note_off' then
                    g.led[target.x][target.y] = rainbow_off[Preset.select] -- note_off muted.
                end
            end
        end
    end,
    grid_event = function (s, data)
        -- Mute are used to prevent incoming MIDI notes from passing through.
        -- Based on toggle state

        local x = data.x
        local y = data.y
        local alt = get_alt()
    
        if data.state and MidiGrid.in_bounds(data, Mute.bounds) then
    
            if alt then 
                set_alt(false)
            else
                local index = grid_map[x][y].note
                Mute.state[index] = s.toggled[x][y]
    
                if Mute.state[index] then 
                    g.led[x][y] = rainbow_off[Preset.select]
                else
                    g.led[x][y] = 0
                end
            end
        end
    end,
    bounds = MidiGrid.get_bounds({x = 1, y = 1}, {x = 4, y = 4}),
    set_grid = function ()
        for i, state in pairs(Mute.state) do
            local x = drum_map[i].x
            local y = drum_map[i].y

            if state then
                g.led[x][y] = rainbow_off[Preset.select]
            else
                g.led[x][y] = 0
            end
        end
    end
}