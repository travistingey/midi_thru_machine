-- PROJECT ------------------------------------------------------------------
params:add_separator('Project')

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

chord_follow_options = {'No','Transpose','Degree','Chord','Pentatonic'}

params:add_group('chord', 'Chords', 29)
params:add_number( 'chord_root', 'Root', -24,24,0)

params:set_action('chord_root', function(d)
    if Chord.last_note ~= nil then
        midi_out:note_off(Chord.last_note,0,14)
    end
    Chord.root = d
end)

params:add_option( 'scale_1_follow', 'Scale 1 Follow', chord_follow_options,1)
params:set_action( 'scale_1_follow', function(d)
    Scale[1].follow = d    
end)

params:add_option( 'scale_2_follow', 'Scale 2 Follow', chord_follow_options,1)
params:set_action( 'scale_2_follow', function(d) Scale[2].follow = d end)

params:add_number( 'chord_mute', 'Mute Channel', 0,127,38)

params:add_separator('Chord Map')

for i=1,12 do

      
    params:add_number('chord_note_' .. i, i .. ' Root',0,11,i-1,
        function(param)
            return musicutil.note_num_to_name(param:get())
        end
    )
    
    params:set_action('chord_note_' .. i,
        function(d)
            if Chord[i] ~= nil then
                Chord[i].note = d
            end
        end
    )

    params:add_number('chord_slot_' .. i, '  Chord', 1,10,1,
        function(param)
            local chord = params:get('eo_slot_' .. param:get())

            return CHORDS[chord].name .. ' ('.. param:get() ..')'
        end
        )
    
    params:set_action('chord_slot_' .. i,
        function(d)
            local selection = params:get('eo_slot_' .. d)
            
            if Chord[i] == nil then
                Chord[i] = {}
            end
            
            Chord[i].note = params:get('chord_note_' .. i) or i - 1
            Chord[i].name = CHORDS[selection].name
            Chord[i].intervals = CHORDS[selection].intervals
            Chord[i].slot = d
            Chord[i].index = selection
        
        end
    )

end

-- DEVICES ------------------------------------------------------------------

params:add_separator('Devices')
params:add_group('bsp', 'Beatstep Pro', 4)

params:add_option("bsp_touchstrip_mode", "Touchstrip Mode", {'Looper','Roller'}, 1)
params:set_action("bsp_touchstrip_mode",function(x)
    if x == 1 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x00,0xF7})
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


-- Ensemble Oscillator -------------------------------------------------------------------------

params:add_group('eo','Ensemble Oscillator',13)

params:add_number('eo_program_select', 'Program', 1,10,1, function(param)
    local slot = param:get()
    local chord = params:get('eo_slot_' .. slot)

    return CHORDS[ chord ].name .. ' (' .. slot .. ')'

end)
params:add_trigger('eo_program','Go')
params:add_separator('')

for i = 1, 10 do
    params:add_number('eo_slot_' .. i, 'Scale ' .. i, 1,#CHORDS,1, function(param)
       return CHORDS[param:get()].name
    end)
end

EO_Learn = false

params:set_action('eo_program', function(d)
    local slot = params:get('eo_program_select')
    local selection = params:get('eo_slot_' .. slot)
    local step = 0 
    local intervals = CHORDS[selection].intervals
    
    midi_out:cc(21,util.clamp((slot - 1) * 14,0,127),14)
        
    print('Programming ' .. CHORDS[selection].name .. ' on Scale ' .. slot)
    metro[1].event = function(c)
        EO_Learn = true
        step = step + c%2
        if(step <= #intervals) then
            if(c%2 == 1)then
                print(intervals[step])
                midi_out:note_on(intervals[step] + 60,127,14)
            else
                midi_out:note_off(intervals[step] + 60,127,14)
            end
        else
            if(c%2 == 1)then
                print((math.floor(intervals[#intervals]/12) + 1) * 12)
                midi_out:note_on((math.floor(intervals[#intervals]/12) + 1) * 12 + 60,127,14)
            else
                midi_out:note_off((math.floor(intervals[#intervals]/12) + 1) * 12 + 60,127,14)
                print('done.')
            end
        end
        
        EO_Learn = false
    end
    
    metro[1].time = 0.125
    metro[1].count = #intervals * 2 + 2
    metro[1]:start()

    params:set('eo_program_select', util.wrap(slot + 1,1,10) )
end)

-- CROW -----------------------------------------------------------------------------

params:add_separator('Crow')

local crow_options = {'v/oct', 'gate', 'interval','arpeggio'}
local destination_options = {'crow', 'midi'}
params:add_number('crow_channel', 'Channel',1,16,10)

for i = 1,4 do
    local out = 'crow_out_' .. i .. '_'
    
    params:add_group(out, 'OUT ' .. i, 7)
    if i == 1 then
        params:add_option(out .. 'type', 'Type', crow_options, 1)
        params:add_option( out .. 'source', 'Source', {'IN 1','IN 2'},1)
    elseif i == 2 then
        params:add_option(out .. 'type', 'Type', crow_options, 2)
        params:add_option( out .. 'source', 'Source', {'IN 1','IN 2'},1)
    elseif i == 3 then
        params:add_option(out .. 'type', 'Type', crow_options, 1)
        params:add_option( out .. 'source', 'Source', {'IN 1','IN 2'},2)
    elseif i == 4 then
        params:add_option(out .. 'type', 'Type', crow_options, 2)
        params:add_option( out .. 'source', 'Source', {'IN 1','IN 2'},2)
    end

    params:set_action(out .. 'type', function(d)
        params:hide(out .. 'ratio')
        params:hide(out .. 'range')
        params:hide(out .. 'source')
        params:hide(out .. 'slew_up')
        params:hide(out .. 'slew_down')

        if d == 1 then
            -- v/oct
            params:show(out .. 'source')
            params:show(out .. 'slew_up')
            params:show(out .. 'slew_down')
            crow.output[i].action = "to(dyn{note=0},dyn{slew=0})"
        elseif d == 3 then
            -- intervals
            params:show(out .. 'ratio')
            params:show(out .. 'range')
            params:show(out .. 'source')
            params:show(out .. 'slew_up')
            params:show(out .. 'slew_down')
            crow.output[i].action = "to(dyn{note=0},dyn{slew=0})"
        elseif d == 4 then
            -- intervals
            params:show(out .. 'source')
            params:show(out .. 'slew_up')
            params:show(out .. 'slew_down')
            crow.output[i].action = "to(dyn{note=0},dyn{slew=0})"
        end

        Output[i].type = crow_options[d]
        
        _menu.rebuild_params()
    end)
    
    local ratio = controlspec.def{
        min = 0.00, -- the minimum value
        max = 1.0, -- the maximum value
        warp = 'lin', -- a shaping option for the raw value
        step = 0.01, -- output value quantization
        default = 0.68, -- default value
        units = '', -- displayed on PARAMS UI
        quantum = 0.01, -- each delta will change raw value by this much
        wrap = false -- wrap around on overflow (true) or clamp (false)
    }

    params:add_control(out .. 'ratio',"Step/Skip",ratio)
    
    local slew = controlspec.def{
        min = 0.00, -- the minimum value
        max = 30.0, -- the maximum value
        warp = 'lin', -- a shaping option for the raw value
        step = 0.01, -- output value quantization
        default = 0.00, -- default value
        units = 's', -- displayed on PARAMS UI
        quantum = 0.0002, -- each delta will change raw value by this much
        wrap = false -- wrap around on overflow (true) or clamp (false)
    }

    params:add_control(out .. 'slew_up',"Slew Up",slew)
    params:set_action( out .. 'slew_up', function(d) Output[i].slew_up = d end )
    params:add_control(out .. 'slew_down',"Slew Down",slew)
    params:set_action( out .. 'slew_down', function(d) Output[i].slew_down = d end )
    params:add_number(out .. 'range','Range',1,5,2)
    params:set_action( out .. 'range', function(d) Output[i].range = d end )
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

local mode_types = {'song', 'drum', 'keys',}
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
    
    -- Mode Presets
    if i == 1 then
        params:add_option(mode .. 'type','Type', mode_types,1)
        params:add_number( mode .. 'div', 'Division', 1, 10, 7, format_div)
    elseif i == 2 then
        params:add_option(mode .. 'type','Type', mode_types,1)
        params:add_number( mode .. 'div', 'Division', 1, 10, 2, format_div)
    elseif i == 3 then
        params:add_option(mode .. 'type','Type', mode_types,3)
        params:add_number( mode .. 'div', 'Division', 1, 10, 7, format_div)
    elseif i == 4 then
        -- recording grid
        params:add_option(mode .. 'type','Type', mode_types,1)
        params:add_number( mode .. 'div', 'Division', 1, 10, 7, format_div)
    end
 
    params:set_action( mode .. 'div', function(d) if Mode and Mode[i] then Mode[i].div = 3 * 2^d end end)
    
    params:add_number( mode .. 'length', 'Length', 1, 128, 16 )
    params:set_action( mode .. 'length', function(d) if Mode and Mode[i] and Mode[i].type ~= 3 then Mode[i]:set_length( d ) end end)

    
    params:set_action( mode .. 'type', function(d) if Mode and Mode[i] then Mode[i].type = d end end)
    params:add_number(mode .. 'channel','Channel', 1,16,10)


end

-- Mutes -----------------------------------------------------------------------
params:add_separator('Mutes')
params:add_group('mute_map','Mute Map',16)

for i=1,16 do
    params:add_number('mute_' .. i .. '_note', i .. " Note", 0,127, 75 + i)
    params:set_action('mute_' .. i .. '_note', function(n)
        
    end)
    params:add_number('mute_' .. i .. '_channel', i .. " Channel", 1,16, 10)
    params:set_action('mute_' .. i .. '_note', function(n)
        
    end)
end

-- Presets -----------------------------------------------------------------------
params:add_separator('Presets')
params:add_group('preset_options','Options',11)

params:add_binary('preset_auto_save', 'Auto Save', 'toggle', 1)
params:set_action('preset_auto_save', function(b) Preset.options['auto_save'] = (b > 0) end)

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

params:add_binary('preset_save_mute', 'Save Mute', 'toggle', 0)
params:set_action('preset_save_mute', function(b) Preset.options['save_mute'] = (b > 0) end)
params:add_binary('preset_save_scales', 'Save Scales', 'toggle', 1)
params:set_action('preset_save_scales', function(b) Preset.options['save_scales'] = (b > 0) end)
params:add_binary('preset_save_pattern', 'Save Pattern', 'toggle', 0)
params:set_action('preset_save_pattern', function(b) Preset.options['save_pattern'] = (b > 0) end)

params:add_binary('preset_save_seq1', 'Save Seq 1', 'toggle', 0)
params:set_action('preset_save_seq1', function(b) Preset.options['save_seq1'] = (b > 0) end)
params:add_binary('preset_save_seq2', 'Save Seq 2', 'toggle', 0)
params:set_action('preset_save_seq2', function(b) Preset.options['save_seq2'] = (b > 0) end)

-- BANKS -------------------------------------------------------------------------

params:add_separator('Banks')
for i = 1,16 do
    
    local bank = 'bank_' .. i .. '_'
    
    params:add_group( bank , 'Bank ' .. i, 10)
    
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
    
    
    params:add_number( bank .. 'chord_root', 'Chord Root',-24,24,0)
    params:set_action( bank .. 'chord_root', function(d)
        if(Preset.select and Preset.select == i) then
            if Chord.last_note ~= nil then
               midi_out:note_off(Chord.last_note,0,14) 
            end

            for s=1,2 do
                if(params:get('scale_' .. s .. '_follow') > 1) then
                    Scale[s].root = d
                end
            end
            
            params:set('chord_root', d)
            screen_dirty = true
            if Mode and Mode.select == 3 then
                Mode[3]:set_grid()
            end
           
        end    
    end)
    
    params:add_number( bank .. 'scale_1_root', 'Scale One Root',-24,24,0)
    params:set_action( bank .. 'scale_1_root', function(d)
        if(Preset.select and Preset.select == i) then
            Scale[1].root = d
        end    
    end)
    
    params:add_number( bank .. 'scale_1', 'Scale One',1,4095,1) -- end scale one
    params:set_action( bank .. 'scale_1', function(s) if (Preset.select and Preset.select == i) then set_scale(s,1) end end)
    
    params:add_option( bank .. 'scale_1_follow', 'Scale One Follow', chord_follow_options,1) -- end scale one
    params:set_action( bank .. 'scale_1_follow', function(d) if (Preset.select and Preset.select == i) then Scale[1].follow = d end end)
    
    params:add_number( bank .. 'scale_2_root', 'Scale Two Root',-24,24,0)
    params:set_action( bank .. 'scale_2_root', function(d)
        if(Preset.select and Preset.select == i) then
            Scale[2].root = d 
        end    
    end)
    
    params:add_number( bank .. 'scale_2', 'Scale Two',1,4095,1) -- end scale two
    params:set_action(bank .. 'scale_2', function(s) if(Preset.select and Preset.select == i) then set_scale(s,2) end end)
    
     params:add_option( bank .. 'scale_2_follow', 'Scale Two Follow', chord_follow_options,1) -- end scale one
    params:set_action( bank .. 'scale_2_follow', function(d) if (Preset.select and Preset.select == i) then Scale[2].follow = d end end)
    
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

