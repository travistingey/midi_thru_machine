local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')

local MuteGrid = ModeComponent:new()
MuteGrid.__base = ModeComponent
MuteGrid.name = 'Mute Grid'

function MuteGrid:set(o)
	self.__base.set(self, o) -- call the base set method first   
    self.triggers = {}
   o.component = 'mute'

    o.grid = Grid:new({
        name = 'Mute',
        grid_start = {x=1,y=1},
        grid_end = {x=4,y=32},
        display_start = {x=1,y=10},
        display_end = {x=4,y=13},
        midi = App.midi_grid
    })

end

function MuteGrid:enable_event()
    self.triggers = {}
    self.base = App.track[self.track]
    -- for each track find the triggers matching the base track
    if(self.base.input_device) then
        for i,track in ipairs(self.base.input_device.triggers) do
            if track.midi_in == self.base.midi_in and track.triggered then
                self.triggers[track.trigger] = track

                table.insert(self.cleanup_functions, track:on('midi_trigger', function(data)
                    self:midi_event(self.base.mute, data)
                end))
            end
        end
        end

end

function MuteGrid:disable_event()
    self.triggers = nil
    self.base = nil
end

function MuteGrid:midi_event (mute, data)
    if data and data.note then
        
        local note = data.note
        local grid = self.grid
        local target = grid:index_to_grid(note + 1)
        local state = mute.state[note] 
        local color = mute.track.id


        if self.triggers[note] then
            local track = self.triggers[note]
            state = track.mute.active
            color = track.id
        end

        if (not state) then
            -- Mute is off
            if data.type == 'note_on' then
                grid.led[target.x][target.y] = 3 -- note_on unmuted.
            elseif data.type == 'note_off' then
                grid.led[target.x][target.y] = 0 -- note_on unmuted.
            end
        else
            -- Mute is on
            if data.type == 'note_on' then
                grid.led[target.x][target.y] = Grid.rainbow_on[color] -- note_on muted.
            elseif data.type == 'note_off' then
                grid.led[target.x][target.y] = Grid.rainbow_off[color] -- note_off muted.
            end
        end
            
        grid:refresh()
    end
end

function MuteGrid:grid_event (mute, data)
  local grid = self.grid
   
    if data.type == 'pad' and data.state then

        local note = grid:grid_to_index(data) - 1
        local isTrigger = false
        -- Set Mute state
        if self.triggers[note] then
            isTrigger = true
            self.triggers[note].mute:emit('set_active',data.toggled)
        else
            mute:emit('set_mute', note, data.toggled)
        end
        
        -- Set the grid led and kill notes
        if isTrigger then
            local track = self.triggers[note]
            if track.mute.active then
                track:kill()
                grid.led[data.x][data.y] = Grid.rainbow_off[track.id]
            else
                grid.led[data.x][data.y] = 0
            end            
        else
            local state = mute.state[note]

            if state then
                grid.led[data.x][data.y] = Grid.rainbow_off[mute.track.id]
                mute.track.output_device:emit('interrupt', { note = note, ch = mute.track.midi_in, note_id = note, type = 'interrupt_note' })
            else
                grid.led[data.x][data.y] = 0
            end
        end

        grid:refresh('grid event')
    end  
end

return MuteGrid