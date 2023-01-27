Preset = {
    grid_start = {x = 5, y = 4},
    grid_end = {x = 8, y = 1},
    select = 1,
    bank = {},
    options = {
        set_mute = (params:get('preset_set_mute') > 0),
        set_scales = (params:get('preset_set_scales') > 0),
        set_pattern = (params:get('preset_set_pattern') > 0),
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
        local alt = get_alt()
    
        if (index ~= false and data.state) then

            if alt then
                -- Save Preset
                print('Saved Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)
                Preset.save( index )
            else
                -- Load Preset
                print('Load Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)
                Preset.select = index
                Preset.load( Preset.select )

            end
    
        end
    end,
    bounds = MidiGrid.get_bounds({x = 5, y = 4}, {x = 8, y = 1}),
    set_grid = function()
       
        local current  = MidiGrid.index_to_grid(Preset.select,Preset.grid_start,Preset.grid_end)
        for px = math.min(Preset.grid_start.x,Preset.grid_end.x), math.max(Preset.grid_start.x,Preset.grid_end.x) do
            for py = math.min(Preset.grid_start.y,Preset.grid_end.y), math.max(Preset.grid_start.y,Preset.grid_end.y) do
                
                if(current.x == px and current.y == py) then
                    g.led[px][py] = rainbow_off[Preset.select]
                else
                    g.led[px][py] = {20,20,20}
                end
                
            end 
        end

        g:redraw()
    end,
    load = function (i)
        Preset.select = i
        local bank = 'bank_' .. i .. '_'

        if Preset.options['set_pattern'] then
            local pattern = params:get( bank .. 'drum_pattern')
            transport:program_change(pattern - 1,10)
        end

        if Preset.options['set_scales'] then
            scale_root = params:get(bank .. 'scale_root')
            scale_one = params:get( bank .. 'scale_one')
            scale_two = params:get(bank .. 'scale_two')

            set_scale(scale_one,1)
            set_scale(scale_two,2)
        end
               
        if Preset.options['set_mute'] then
            local pset = Preset.bank[Preset.select]
            if (pset) then
                for k, v in pairs(pset) do
                    local target = drum_map[k]
                    Mute.state[k] = pset[k]
                    g.toggled[target.x][target.y] = pset[k]

                    if pset[k] then
                        g.led[target.x][target.y] = rainbow_off[Preset.select]
                    else
                        g.led[target.x][target.y] = 0
                    end
                end
            else
                for k, v in pairs(drum_map) do
                    local target = v
                    Mute.state[k] = false
                    g.toggled[target.x][target.y] = false
                    g.led[target.x][target.y] = 0
                end
            end
        end
        Preset:set_grid()
        g:redraw()
    end,
    save = function (i)
        local current_bank = 'bank_' .. Preset.select .. '_'
        local bank = 'bank_' .. i .. '_'

        if(Preset.options['save_pattern']) then
            local pattern = params:get( current_bank .. 'drum_pattern')
            params:set( bank .. 'drum_pattern', pattern )
        end
        
        if(Preset.options['save_scales']) then
            params:set( bank .. 'scale_root', scale_root )
            params:set( bank .. 'scale_one', scale_one )
            params:set( bank .. 'scale_two', scale_two )
        end

        Preset.bank[i] = {}
        
        if(Preset.options['save_mute']) then
            for k, v in pairs(drum_map) do
                Preset.bank[i][k] = (Mute.state[k] == true)
            end
        end
        
        set_alt(false)
        screen_dirty = true
    end
}