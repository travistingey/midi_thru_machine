-- START PARAM MENU -------------------------------------------------------------------------------------------------

params:add_separator('Beatstep Pro')

params:add_binary("bsp_touchstrip_mode", "Touchstrip Mode", "toggle", 0)
params:set_action("bsp_touchstrip_mode",function(x)
    if x == 0 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x00,0xF7})
    elseif x == 1 then
        transport:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x41,0x17,0x01,0xF7})
    end
end)

-- DEVICES --------------------------------------------------------------------------------------------
--[[ All this didnt work... it seems like it doesnt like being messed with after the initialization, which is no surprise as its a hot mess of spaghetti.
params:add_separator('Devices')
midi_device_names = {}
for i = 1,#midi.vports do
    local abbr = string.match(midi.vports[i].name,'.-%S*')
    midi_device_names[i] = i .. ' (' .. abbr .. ')'
end

params:add{
    type = "option",
    id = "Device transport",
    name = "Transport",
    options = midi_device_names,
    default = 1,
    action = function(id) transport = midi.connect(id) end
}

params:add{
    type = "option",
    id = "device_midi_output",
    name = "Midi Output",
    options = midi_device_names,
    default = 2,
    action = function(id) out_device = midi.connect(id) end
}

params:add{
    type = "option",
    id = "device_grid",
    name = "Grid",
    options = midi_device_names,
    default = 3,
    action = function(id) g = midi.connect(id) end
}

]]

params:add_number('project_bank', 'Project',1,7,1)
params:set_action('project_bank', function(i)  transport:cc(0,i-1,16) end)

params:add_number('drum_bank', 'Drum Bank',1,7,1)
params:set_action('drum_bank', function(i)  midi_out:program_change(i-1,10) end)

params:add_separator('Crow')

-- -- CROW --------------------------------------------------------------------------------------------



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
-- -- BANKS ------------------------
params:add_separator('Banks')
for i = 1,16 do
    local bank = 'bank_' .. i .. '_'
    params:add_group( bank , 'Bank ' .. i, 4)
    params:add_number( bank .. 'drum_pattern', 'Drum Pattern',1,16, i)
    params:add_number( bank .. 'scale_root', 'Root Note',-11,11,0)
    params:add_number( bank .. 'scale_one', 'Scale One',1,41,1)
    params:set_action(bank .. 'scale_one', function(s)
        if (Preset.select and Preset.select == i) then
            set_scale(s,1) end
        end)
    params:add_number( bank .. 'scale_two', 'Scale Two',1,41,1)
    params:set_action(bank .. 'scale_two', function(s) if(Preset.select and Preset.select == i) then set_scale(s,2) end end)    
end
-- params:add_number(bank .. 'scale_one', 'Scale One', 1, 41,3 )
--     params:set_action(bank .. 'scale_one', function(i) set_scale(i,1) end)
--     params:add_number(bank .. 'scale_two', 'Scale Two', 1, 1, 41,3)
--     params:set_action(bank .. 'scale_two', function(i) set_scale(i,2) end)
