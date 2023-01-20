-- START PARAM MENU ------------------------------------------------------------------

params:add_separator('Beatstep Pro')

params:add_option("bsp_touchstrip_mode", "Touchstrip Mode", {'Roller','Looper'}, 2)
params:set_action("bsp_touchstrip_mode",function(x)
    if x == 1 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x00,0xF7})
    elseif x == 2 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x01,0xF7})
    end
end)

params:add_number('project_bank', 'Project',1,7,1)
params:set_action('project_bank', function(i)  transport:cc(0,i-1,16) end)

params:add_number('drum_bank', 'Drum Bank',1,7,1)
params:set_action('drum_bank', function(i)  midi_out:program_change(i-1,10) end)

params:add_separator('Crow')

-- CROW -----------------------------------------------------------------------------

local crow_options = {'v/oct', 'gate', 'envelope'}
params:add_number('crow_channel', 'Channel',1,16,10)

for i = 1,4 do
    local out = 'crow_out_' .. i .. '_'
    
    params:add_group(out, 'OUT ' .. i, 3)
    params:add_option(out .. 'type', 'Type', crow_options, 1)
    params:add_option( out .. 'source', 'Source',{'IN 1','IN 2'})
    params:set_action(out .. 'type', function(d)
        if d == 1 then
            params:show(out .. 'source')
        else
            params:hide(out .. 'source')
        end
        _menu.rebuild_params()
    end)

    params:add_number( out .. 'trigger', 'Trigger',1,128,36)

end

-- BANKS -------------------------------------------------------------------------

params:add_separator('Banks')
for i = 1,16 do
    
    local bank = 'bank_' .. i .. '_'
    
    params:add_group( bank , 'Bank ' .. i, 4)
    
    params:add_number( bank .. 'drum_pattern', 'Drum Pattern',1,16, i)
    params:set_action( bank .. 'drum_pattern', function(d)
        if(Preset.select and Preset.select == i) then
            transport:program_change(d-1,10)
        end    
    end)
    
    params:add_number( bank .. 'scale_root', 'Root',-12,12,0)
    params:set_action( bank .. 'scale_root', function(d)
        if(Preset.select and Preset.select == i) then
            scale_root = d 
        end    
    end)
    
    params:add_number( bank .. 'scale_one', 'Scale One',1,41,1,
        function(param)
            local name = musicutil.SCALES[param:get()].name
    
            if name:len() > 18 then
                return name:sub(1,15) .. '...'
            else
                return name
            end
        end
    ) -- end scale one
    params:set_action( bank .. 'scale_one', function(s) if (Preset.select and Preset.select == i) then set_scale(s,1) end end)
    
    params:add_number( bank .. 'scale_two', 'Scale Two',1,41,1,
        function(param)
            local name = musicutil.SCALES[param:get()].name
    
            if name:len() > 18 then
                return name:sub(1,15) .. '...'
            else
                return name
            end
        end
    ) -- end scale two
    params:set_action(bank .. 'scale_two', function(s) if(Preset.select and Preset.select == i) then set_scale(s,2) end end)    
end

-- Presets -----------------------------------------------------------------------

params:add_group('Preset',4)
params:add_binary('preset_mute', 'Mute', 'toggle', true)
params:add_binary('preset_change_pattern', 'Change Pattern', 'toggle', true)
params:add_binary('preset_save_pattern', 'Save Pattern', 'toggle', true)
params:add_binary('preset_scales', 'Scales', 'toggle', true)

-- Modes ------------------------------------------------------------------------- 

params:add_separator('Modes')
for i = 1, 4 do 
    params:add_group( 'Mode ' .. i, 2 )
    
    local mode = 'mode_' .. i .. '_'
    
    params:add_number( mode .. 'div', 'Division', 1, 10, 2,
        function(param)
            local i = param:get()
            return (3*2^i) / 96
        end
    ) -- end division
    params:set_action( mode .. 'div', function(d) Mode[i].div = 3 * 2^d end)
    
    params:add_number( mode .. 'length', 'Length', 1, 128, 16 )
    params:set_action( mode .. 'length', function(d) Mode[i]:set_length( d ) end)

end