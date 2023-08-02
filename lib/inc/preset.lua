local path_name = 'Foobar/lib/'
local App = require(path_name .. 'app')
local MidiGrid = require(path_name .. 'midigrid')

Preset = {
    grid_start = {x = 5, y = 4},
    grid_end = {x = 8, y = 1},
    select = 1,
    bank = {},
    options = {
        auto_save = (params:get('preset_auto_save') > 0),
        set_mute = (params:get('preset_set_mute') > 0),
        set_scales = (params:get('preset_set_scales') > 0),
        set_pattern = (params:get('preset_set_pattern') > 0),
        set_seq1 = (params:get('preset_set_seq1') > 0),
        set_seq2 = (params:get('preset_set_seq2') > 0),
        save_seq1 = (params:get('preset_save_seq1') > 0),
        save_seq2 = (params:get('preset_save_seq2') > 0),
        save_mute = (params:get('preset_save_mute') > 0),
        save_scales = (params:get('preset_save_scales') > 0),
        save_pattern = (params:get('preset_save_pattern') > 0)
    },
    grid_event = function (s, data)
        -- Preset are used to store different combination of mute settings, stored as a 2D table
        -- Ony one preset in a bank is active at a time.
        -- Pressing pad will load preset. Pressing alt + pad will save current mutes as a preset
        local x = data.x
        local y = data.y
        local index = MidiGrid.grid_to_index({x = x, y = y}, Preset.grid_start, Preset.grid_end)
        local alt = App:get_alt()
    
        if (index ~= false and data.state) then

            if alt then
                -- Save Preset
                print('Saved Preset ' .. App.preset .. ' ' .. x .. ',' .. y)
                Preset.save( index )
            else
                -- Load Preset
                print('Load Preset ' .. App.preset .. ' ' .. x .. ',' .. y)
                App:set('preset',index)
                Preset.load( App.preset )

            end
        elseif data.state and data.x ~= 9 and data.y ~= 9 then
            if(Preset.options['auto_save']) then
                Preset.save(App.preset)
            end
        end
    end,
    bounds = MidiGrid.get_bounds({x = 5, y = 4}, {x = 8, y = 1}),
    set_grid = function()
       
        local current  = MidiGrid.index_to_grid(App.preset,Preset.grid_start,Preset.grid_end)
        for px = math.min(Preset.grid_start.x,Preset.grid_end.x), math.max(Preset.grid_start.x,Preset.grid_end.x) do
            for py = math.min(Preset.grid_start.y,Preset.grid_end.y), math.max(Preset.grid_start.y,Preset.grid_end.y) do
                
                if(current.x == px and current.y == py) then
                    App.grid.led[px][py] = MidiGrid.rainbow_off[App.preset]
                else
                    App.grid.led[px][py] = {20,20,20}
                end
                
            end 
        end

        App.grid:redraw()
    end,
    load = function (i)
        App:set('preset',i)
        local bank = 'bank_' .. i .. '_'

        if Preset.options['set_pattern'] then
            local pattern = params:get( bank .. 'drum_pattern')
            local channel = params:get('bsp_drum_channel')
            App.midi_in:program_change(pattern - 1, channel)
        end

        if Preset.options['set_seq1'] then
            local pattern = params:get( bank .. 'seq1_pattern')
            local channel = params:get( 'bsp_seq1_channel')
            App.midi_in:program_change(pattern - 1, channel)
        end

        if Preset.options['set_seq2'] then
            local pattern = params:get( bank .. 'seq2_pattern')
            local channel = params:get( 'bsp_seq2_channel')
            App.midi_in:program_change(pattern - 1, channel)
        end

        if Preset.options['set_scales'] then
            App.scale[1].bits = params:get(bank .. 'scale_1')
            App.scale[2].bits = params:get(bank .. 'scale_2')
            App.scale[1].root = params:get(bank .. 'scale_1_root')
            App.scale[2].root = params:get(bank .. 'scale_2_root')
            App.scale[1].follow = params:get(bank .. 'scale_1_follow')
            App.scale[2].follow = params:get(bank .. 'scale_2_follow')
            App.chord.root = params:get(bank .. 'chord_root')
            
            App:set_scale(App.scale[1].bits,1)
            App:set_scale(App.scale[2].bits,2)
                       
        end
               
        if Preset.options['set_mute'] then
            local pset = Preset.bank[App.preset]
            if (pset) then
                for k, v in pairs(pset) do
                    local target = Mute.note_map[k]
                    Mute.state[k] = pset[k]
                    App.grid.toggled[target.x][target.y] = pset[k]

                    if pset[k] then
                        App.grid.led[target.x][target.y] = MidiGrid.rainbow_off[App.preset]
                    else
                        App.grid.led[target.x][target.y] = 0
                    end
                end
            else
                for k, v in pairs(Mute.note_map) do
                    local target = v
                    Mute.state[k] = false
                    App.grid.toggled[target.x][target.y] = false
                    App.grid.led[target.x][target.y] = 0
                end
            end
        end
        Preset:set_grid()
        App.grid:redraw()
    end,
    save = function (i)
        local current_bank = 'bank_' .. App.preset .. '_'
        local bank = 'bank_' .. i .. '_'

        if(Preset.options['save_pattern']) then
            local pattern = params:get( current_bank .. 'drum_pattern')
            params:set( bank .. 'drum_pattern', pattern )
        end

        if(Preset.options['save_seq1']) then
            local pattern = params:get( current_bank .. 'seq1_pattern')
            params:set( bank .. 'seq1_pattern', pattern )
        end

        if(Preset.options['save_seq2']) then
            local pattern = params:get( current_bank .. 'seq2_pattern')
            params:set( bank .. 'seq2_pattern', pattern )
        end
        
        if(Preset.options['save_scales']) then
            params:set( bank .. 'scale_1_root', App.scale[1].root )
            params:set( bank .. 'scale_1', App.scale[1].bits )
            params:set( bank .. 'scale_2_root', App.scale[2].root )
            params:set( bank .. 'scale_2', App.scale[2].bits )
            
            params:set( bank .. 'scale_1_follow', App.scale[1].follow )
            params:set( bank .. 'scale_2_follow', App.scale[2].follow )
            params:set( bank .. 'chord_root', App.chord.root )
            
        end

        Preset.bank[i] = {}
        
        if(Preset.options['save_mute']) then
            for k, v in pairs(Mute.note_map) do
                Preset.bank[i][k] = (Mute.state[k] == true)
            end
        end
        
        App:set_alt(false)
        screen_dirty = true
    end
}