-- START PARAM MENU ------------------------------------------------------------------

params:add_separator('Beatstep Pro')

params:add_option("bsp_touchstrip_mode", "Touchstrip Mode", {'Looper','Roller'}, 1)
params:set_action("bsp_touchstrip_mode",function(x)
    if x == 1 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x63,0x01,0xF7})
    elseif x == 2 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x01,0xF7})
    end
end)
params:add_number("bsp_seq1_channel", "Seq 1 Ch", 1,16,1)
params:set_action("bsp_seq1_channel",function(x)
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x40,x - 1,0xF7})      
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x41,x - 1,0xF7})    
end)
params:add_number("bsp_seq2_channel", "Seq 2 Ch", 1,16,5)
params:set_action("bsp_seq2_channel",function(x)
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x42,x - 1,0xF7})
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x43,x - 1,0xF7}) 
end)

params:add_number("bsp_drum_channel", "Drum Ch", 1,16,10)
params:set_action("bsp_drum_channel",function(x)
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x44,x - 1,0xF7})   
    transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x45,x - 1,0xF7})   
end)

params:add_number('project_bank', 'Project',1,16,1)
params:set_action('project_bank', function(i)  transport:cc(0,i-1,16) end)

params:add_number('drum_bank', 'Drum Bank',1,7,1)
params:set_action('drum_bank', function(i)
    midi_out:program_change(i-1,10)
    for y=1,8 do
        g.led[9][y] = 0
    end    
    g.led[9][9 - i] = 3 -- Set Drum Bank
    current_bank = i
	g:redraw()
end)



-- CROW -----------------------------------------------------------------------------

params:add_separator('Crow')

local crow_options = {'v/oct', 'gate'}
params:add_number('crow_channel', 'Channel',1,16,10)

for i = 1,4 do
    local out = 'crow_out_' .. i .. '_'
    
    params:add_group(out, 'OUT ' .. i, 3)
    if i == 1 then
        params:add_option(out .. 'type', 'Type', crow_options, 1)
    elseif i == 2 then
        params:add_option(out .. 'type', 'Type', crow_options, 2)
    elseif i == 3 then
        params:add_option(out .. 'type', 'Type', crow_options, 1)
    elseif i == 4 then
        params:add_option(out .. 'type', 'Type', crow_options, 2)
    end
    params:set_action(out .. 'type', function(d)
        if d == 1 then
            params:show(out .. 'source')
            
        else
            params:hide(out .. 'source')
        end
        
        Output[i].type = crow_options[d]
        
        _menu.rebuild_params()
    end)
    params:add_option( out .. 'source', 'Source', {'IN 1','IN 2'})
    params:set_action( out .. 'source', function(d) Output[i].source = d end )
    
    if i == 1 then
        params:add_number( out .. 'trigger', 'Trigger',1,128,36)
    elseif i == 2 then
        params:add_number( out .. 'trigger', 'Trigger',1,128,36)
    elseif i == 3 then
        params:add_number( out .. 'trigger', 'Trigger',1,128,37)
    elseif i == 4 then
        params:add_number( out .. 'trigger', 'Trigger',1,128,37)
    end

    params:set_action( out .. 'trigger',function(d) Output[i].trigger = d end )

end



-- MODES ------------------------------------------------------------------------- 

local mode_types = {'song', 'drum', 'break'}
function format_div(param)
    local index = param:get()

    if index > 5 then
        return math.floor( (3*2^index) / 96 ) .. ' bars'
    elseif index == 5 then
        return '1 bar' 
    else
        return '1/' .. math.floor(2^(5-index)) .. ' notes'
    end
end
params:add_separator('Modes')
for i = 1, 4 do 
    params:add_group( 'Mode ' .. i, 4 )
    
    local mode = 'mode_' .. i .. '_'
    
    if i == 1 then
        params:add_number( mode .. 'div', 'Division', 1, 10, 7, format_div)
    else
        params:add_number( mode .. 'div', 'Division', 1, 10, 2, format_div)
    end
    
    params:set_action( mode .. 'div', function(d) if Mode and Mode[i] then Mode[i].div = 3 * 2^d end end)
    
    params:add_number( mode .. 'length', 'Length', 1, 128, 16 )
    params:set_action( mode .. 'length', function(d) if Mode and Mode[i] and Mode[i].type ~= 3 then Mode[i]:set_length( d ) end end)

    params:add_option(mode .. 'type','Type', mode_types)
    params:set_action( mode .. 'type', function(d) if Mode and Mode[i] then Mode[i].type = d end end)
    params:add_number(mode .. 'channel','Channel', 1,16,10)


end


-- Presets -----------------------------------------------------------------------

params:add_separator('Preset')
params:add_binary('preset_set_mute', 'Set Mute', 'toggle', 1)
params:set_action('preset_set_mute', function(b) Preset.options['set_mute'] = (b > 0) end)
params:add_binary('preset_set_scales', 'Set Scales', 'toggle', 1)
params:set_action('preset_set_scales', function(b) Preset.options['set_scales'] = (b > 0) end)
params:add_binary('preset_set_pattern', 'Set Pattern', 'toggle', 1)
params:set_action('preset_set_pattern', function(b) Preset.options['set_pattern'] = (b > 0) end)

params:add_binary('preset_set_seq1', 'Set Seq 1', 'toggle', 1)
params:set_action('preset_set_seq1', function(b) Preset.options['set_seq1'] = (b > 0) end)
params:add_binary('preset_set_seq2', 'Set Seq 2', 'toggle', 1)
params:set_action('preset_set_seq2', function(b) Preset.options['set_seq2'] = (b > 0) end)

params:add_binary('preset_save_mute', 'Save Mute', 'toggle', 1)
params:set_action('preset_save_mute', function(b) Preset.options['save_mute'] = (b > 0) end)
params:add_binary('preset_save_scales', 'Save Scales', 'toggle', 1)
params:set_action('preset_save_scales', function(b) Preset.options['save_scales'] = (b > 0) end)
params:add_binary('preset_save_pattern', 'Save Pattern', 'toggle', 1)
params:set_action('preset_save_pattern', function(b) Preset.options['save_pattern'] = (b > 0) end)

params:add_binary('preset_save_seq1', 'Save Seq 1', 'toggle', 1)
params:set_action('preset_save_seq1', function(b) Preset.options['save_seq1'] = (b > 0) end)
params:add_binary('preset_save_seq2', 'Save Seq 2', 'toggle', 1)
params:set_action('preset_save_seq2', function(b) Preset.options['save_seq2'] = (b > 0) end)

-- BANKS -------------------------------------------------------------------------

params:add_separator('Banks')
for i = 1,16 do
    
    local bank = 'bank_' .. i .. '_'
    
    params:add_group( bank , 'Bank ' .. i, 7)
    
    params:add_number( bank .. 'drum_pattern', 'Drum Pattern',1,16, i)
    params:set_action( bank .. 'drum_pattern', function(d)
        if(Preset.select and Preset.select == i) then
            transport:program_change(d-1,10)
        end    
    end)

    params:add_number( bank .. 'seq1_pattern', 'Seq 1 Pattern',1,16, i)
    params:set_action( bank .. 'seq1_pattern', function(d)
        if(Preset.select and Preset.select == i) then
            transport:program_change(d-1,10)
        end    
    end)

    params:add_number( bank .. 'seq2_pattern', 'Seq 2 Pattern',1,16, i)
    params:set_action( bank .. 'seq2_pattern', function(d)
        if(Preset.select and Preset.select == i) then
            transport:program_change(d-1,10)
        end    
    end)
    
    params:add_number( bank .. 'scale_1_root', 'Scale One Root',-24,24,0)
    params:set_action( bank .. 'scale_1_root', function(d)
        if(Preset.select and Preset.select == i) then
            Scale[1].root = d 
        end    
    end)

    params:add_number( bank .. 'scale_2_root', 'Scale Two Root',-24,24,0)
    params:set_action( bank .. 'scale_2_root', function(d)
        if(Preset.select and Preset.select == i) then
            Scale[2].root = d 
        end    
    end)
    
    -- params:add_number( bank .. 'scale_one', 'Scale One',1,41,1,
    --     function(param)
    --         local name = musicutil.SCALES[param:get()].name
    
    --         if name:len() > 18 then
    --             return name:sub(1,15) .. '...'
    --         else
    --             return name
    --         end
    --     end
    -- ) -- end scale one

    params:add_number( bank .. 'scale_1', 'Scale One',1,4095,4095) -- end scale one

    params:set_action( bank .. 'scale_1', function(s) if (Preset.select and Preset.select == i) then set_scale(s,1) end end)
    
    params:add_number( bank .. 'scale_2', 'Scale Two',1,4095,5289) -- end scale two
    params:set_action(bank .. 'scale_2', function(s) if(Preset.select and Preset.select == i) then set_scale(s,2) end end)    
end

params.action_write = function(filename,name,number)
    print("finished writing '"..filename.."' as '"..name.."' and PSET number: "..number)
    local save_name = filename:match('(%w*-%d*)%.pset$')
    tab.save(Mode,'/home/we/dust/data/' .. script_name .. '/' .. save_name .. '.data')
end

params.action_read = function(filename,silent,number)
    print("finished reading '"..filename.."' as PSET number: "..number)
    local name = filename:match('(%w*-%d*)%.pset$')
    local loaded = tab.load('/home/we/dust/data/' .. script_name .. '/' .. name .. '.data')
    if loaded then
        Mode:load(loaded)
    else
        Mode:load()
    end
end

params.action_delete = function(filename,name,number)
    print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
end