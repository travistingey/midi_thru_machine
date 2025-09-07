local path_name = 'Foobar/lib/'

local Grid = require(path_name .. 'grid')
local utilities = require(path_name .. 'utilities')
local ParamTrace = require(path_name .. 'utilities/paramtrace')
local PresetSeq = require(path_name .. 'components/mode/presetseq')
local Mode = require(path_name .. 'components/app/mode')
local UI = require(path_name .. 'ui')

local presetseq = PresetSeq:new({
    track=1,
    grid_start = {x=1,y=8},
    grid_end = {x=8,y=1},
    display_start = {x=1,y=1},
    display_end = {x=8,y=8},
    offset = {x=0,y=0}
})


local SessionMode = Mode:new({
    id = 1,
    track = 1,
    components = {
        presetseq
    },
    load_event = function(self,data)
        presetseq.track = App.current_track 

        self.row_pads.led[9][9 - App.current_track] = 1
        self.row_pads:refresh()

        App.screen_dirty = true
    end,
    arrow_event = function(self,data)
        if data.state then
            if App.recording then
                print('Cannot mess with step length during recording')
                return
            end

            if data.type == 'left'  then
                presetseq:increase_step_length()
            elseif data.type == 'right' then
                presetseq:decrease_step_length()
            elseif data.type == 'up'  then
                presetseq:decrease_display_offset()
                if presetseq.display_offset == 0 then
                    print('at the start')
                end
            elseif data.type == 'down' then
                presetseq:increase_display_offset()
            end
          
        end
    end,
    row_event = function(self,data)
        if data.state then
            self.row_pads:reset()

            if data.row ~= App.current_track then
                self.track = data.row
                App.current_track = data.row
                presetseq:row_event(data)
            end
        end
    end,
})



return SessionMode