Preset = {
    grid_start = {x = 5, y = 4},
    grid_end = {x = 8, y = 1},
    select = 1,
    bank = {},
    grid_event = function (s, data)
        -- Preset are used to store different combination of mute settings, stored as a 2D table
        -- Ony one preset in a bank is active at a time.
        -- Pressing pad will load preset. Pressing alt + pad will save current mutes as a preset
        local x = data.x
        local y = data.y
        local index = MidiGrid.grid_to_index({x = x, y = y}, Preset.grid_start, Preset.grid_end)
        local alt = s.toggled[9][1]
    
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
    end,
    load = function (i)
        Preset.select = i
        local bank = 'bank_' .. i .. '_'
       
        local pattern = params:get( bank .. 'drum_pattern')
        scale_root = params:get(bank .. 'scale_root')
        scale_one = params:get( bank .. 'scale_one')
        scale_two = params:get(bank .. 'scale_two')
    
        transport:program_change(pattern - 1,10)
        set_scale(scale_one,1)
        set_scale(scale_two,2)
        
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
        
        Preset:set_grid()
    end,
    save = function (i)
        local current_bank = 'bank_' .. Preset.select .. '_'
        local bank = 'bank_' .. i .. '_'
        local pattern = params:get( current_bank .. 'drum_pattern')
        print(scale_one .. '  and ' .. scale_two)
        params:set( bank .. 'drum_pattern', pattern )
        params:set( bank .. 'scale_root', scale_root )
        params:set( bank .. 'scale_one', scale_one )
        params:set( bank .. 'scale_two', scale_two )
        
        Preset.bank[i] = {}
        
        for k, v in pairs(drum_map) do
            Preset.bank[i][k] = (Mute.state[k] == true)
        end
        
        g.toggled[9][1] = false
        g.led[9][1] = 0
        screen_dirty = true
    end
}