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