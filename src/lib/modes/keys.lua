local Mode = require('Foobar/lib/components/app/mode')
local ScaleGrid = require('Foobar/lib/components/mode/scalegrid')
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local Registry = require('Foobar/lib/utilities/registry')

local Default = require('Foobar/lib/components/mode/default')

local KeysMode = Mode:new({
    id = 3,
    components = {
        Default:new({}),
        ScaleGrid:new({id=1, offset = {x=0,y=6}}),
        ScaleGrid:new({id=2, offset = {x=0,y=4}}),
        ScaleGrid:new({id=3, offset = {x=0,y=2}}),
        PresetGrid:new({
            id = 2,
            track = 1,
            grid_start = {x=1,y=2},
            grid_end = {x=8,y=1},
            display_start = {x=1,y=1},
            display_end = {x=8,y=2},
            offset = {x=0,y=0},
            param_list={
                'scale_1_bits',
                'scale_1_root',
                'scale_2_bits',
                'scale_2_root',
                'scale_3_bits',
                'scale_3_root',
            }
        })
    },
    on_load = function() App.screen_dirty = true end,
    row_event = function(s,data)
        if data.state then
            if data.row < 7 then
                local scalegrid = s.components[math.ceil(data.row/2)]
                scalegrid:row_event(data)
            end
        end
    end,
    context = {
        enc1 = function(d)
            		Registry.set('scale_1_root', App.scale[1].root + d, 'keys_scale_root_change')
            App.screen_dirty = true
        end,
        alt_enc1 = function(d)
            App.scale[1]:shift_scale_to_note(App.scale[1].root + d)
            App.screen_dirty = true
        end,

    }

})

return KeysMode
