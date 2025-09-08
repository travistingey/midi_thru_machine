local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local ParamTrace = require('Foobar/lib/utilities/paramtrace')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid') 
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local PresetSeq = require('Foobar/lib/components/mode/presetseq')
local ModeDefault = require('Foobar/lib/components/mode/modedefault')

local Mode = require('Foobar/lib/components/app/mode')

local presetseq = PresetSeq:new({track=1})
local mutegrid = MuteGrid:new({track=1})
local presetgrid = PresetGrid:new({track=1, param_type='track'})
local modedefault = ModeDefault:new({})

local SessionMode = Mode:new({
    id = 1,
    track = 1,
    cursor = 1,
    components = {
        modedefault,
        presetseq,
        mutegrid,
        presetgrid
    },
    load_event = function(self,data)
        presetseq.track = App.current_track 
        presetgrid.track = App.current_track

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

            if data.type == 'up'  then
                presetseq:increase_step_length()
            elseif data.type == 'down' then
                presetseq:decrease_step_length()
            end
            print('Preset Seq now set to' .. presetseq.step_length)
        end
    end,
    row_event = function(self,data)
        if data.state then
            self.row_pads:reset()

            if data.row ~= App.current_track then
                self.track = data.row
                App.current_track = data.row
                
                presetseq:row_event(data)
                presetgrid:row_event(data)
            else
                App:set_mode(5)
                return
            end


            if self.alt then
                App:set_mode(5)
            else
                self:disable()
                self:enable()
            end
        end
    end
})



return SessionMode
