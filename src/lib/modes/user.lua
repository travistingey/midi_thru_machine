local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local ParamTrace = require('Foobar/lib/utilities/paramtrace')
local path_name = 'Foobar/lib/components/mode/'

local PresetSeq = require('Foobar/lib/components/mode/presetseq')

local Mode = require('Foobar/lib/components/app/mode')

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
    cursor = 1,
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
    context = {
        enc1 = function(d)
            local mode = App.mode[1]
            mode.cursor = util.clamp (mode.cursor + d, 1, 2)
            App.screen_dirty = true
        end,
        enc2 = function(d)
            local mode = App.mode[1]
            
            if mode.cursor == 1 then
                ParamTrace.set('track_' .. App.current_track .. '_device_in', App.track[App.current_track].device_in + d, 'session_device_in_change')
            elseif mode.cursor == 2 then
                ParamTrace.set('track_' .. App.current_track .. '_device_out', App.track[App.current_track].device_out + d, 'session_device_out_change')
            end
            App.screen_dirty = true
        end,
        enc3 = function(d)
            local mode = App.mode[1]
            
            if mode.cursor == 1 then
                ParamTrace.set('track_' .. App.current_track .. '_midi_in', App.track[App.current_track].midi_in + d, 'session_midi_in_change')
            elseif mode.cursor == 2 then
                ParamTrace.set('track_' .. App.current_track .. '_midi_out', App.track[App.current_track].midi_out + d, 'session_midi_out_change')
            end

            App.screen_dirty = true
        end
    },
    layer = {[2] = function()
            screen.level(15)
            App:set_font(1)
            screen.move(0, App.mode[1].cursor * 10 + 12)
            screen.text('_')
            screen.fill()
        end
    }
})



return SessionMode