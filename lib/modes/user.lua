local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid') 
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local PresetSeq = require('Foobar/lib/components/mode/presetseq')

local Mode = require('Foobar/lib/components/app/mode')

local presetseq = PresetSeq:new({track=1})
local mutegrid = MuteGrid:new({track=1})
local presetgrid = PresetGrid:new({track=1})


local SessionMode = Mode:new({
    id = 1,
    components = {
        presetseq,
        mutegrid,
        presetgrid
    },
    on_load = function(s,data)
        s.row_pads.led[9][8] = 1
        s.row_pads:refresh()
         App.screen_dirty = true
    end,
    on_row = function(s,data)

        presetseq:on_row(data, true)
        presetgrid:on_row(data)

        for i = 2, 8 do
            s.row_pads.led[9][i] = 0
        end
    
        s.row_pads.led[9][9 - data.row] = 1
        s.row_pads:refresh()
    end,
    
})

return SessionMode