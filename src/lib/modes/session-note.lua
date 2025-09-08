local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid') 
local NoteGrid = require('Foobar/lib/components/mode/notegrid')
local PresetSeq = require('Foobar/lib/components/mode/presetseq')
local ModeDefault = require('Foobar/lib/components/mode/modedefault')

local Mode = require('Foobar/lib/components/app/mode')

local presetseq = PresetSeq:new({track=1})
local mutegrid = MuteGrid:new({track=1})
local notegrid = NoteGrid:new({track=1})
local modedefault = ModeDefault:new({})


local SessionMode = Mode:new({
    id = 1,
    track = 1,
    components = {
        modedefault,
        presetseq,
        mutegrid,
        notegrid
    },
   load_event = function(s,data)
        presetseq.track = App.current_track
        notegrid.track = App.current_track

        s.row_pads.led[9][9 - App.current_track] = 1
        s.row_pads:refresh()
        App.screen_dirty = true
    end,
    row_event = function(self,data)

        if data.state then
            self.row_pads:reset()

            if data.row ~= App.current_track then
                self.track = data.row
                App.current_track = data.row
                
                presetseq:row_event(data)
                notegrid:row_event(data)
            else
                App:set_mode(1)
                return
            end


            if self.alt then
                App:set_mode(1)
            else
                self:disable()
                self:enable()
            end
        end

    end
})

return SessionMode
