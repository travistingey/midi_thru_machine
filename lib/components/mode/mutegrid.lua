local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')

local MuteGrid = ModeComponent:new()
MuteGrid.__base = ModeComponent
MuteGrid.name = 'Mute Grid'

function MuteGrid:set(o)
	self.__base.set(self, o) -- call the base set method first   

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

function MuteGrid:on_enable()
    self.triggers = {}
    local base = App.track[1]
    
    -- for each track find the triggers matching the base track
    if base.enabled then
        for i = 1, #App.track do
            local track = App.track[i]

            if base ~= track and track.midi_in == base.midi_in  and track.triggered then
                -- store the trigger in the mode
                self.triggers[track.trigger] = track
                
                -- and assign the mode's midi event to the trigger
                track.mute.on_midi = function(s, data)
                    self:midi_event(s, data)
                end

                base.mute.state[track.trigger] = false
            elseif base == track then
                track.mute.on_midi = function(s,data)
                    self:midi_event(s,data)
                end
            end
        end
    end

    self.grid.event = function(s,d)
        if self.grid:in_bounds(d) then

            local note = self.grid:grid_to_index(d) - 1

            if self.triggers[note] ~= nil and self.triggers[note] ~= self.base then
                self:grid_event(self.triggers[note].mute, d)
            elseif base.enabled then
                self:grid_event(base.mute, d)
            
            end
        end
    end

    
end

function MuteGrid:on_disable()
    
    self.triggers = nil
    self.base = nil

    for i = 1, #App.track do
        App.track[i].mute.on_midi = nil
    end

    self.grid.event = nil
end

function MuteGrid:midi_event (mute, data)
    if data and data.note then
        local note = data.note
        local grid = self.grid
        local target = grid:index_to_grid(note + 1)
        local state
        
        if mute.track.triggered then
            state = mute.active
            note = mute.track.trigger
            target = grid:index_to_grid(note + 1)
        else
            state = mute.state[note] 
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
                grid.led[target.x][target.y] = Grid.rainbow_on[mute.track.id] -- note_on muted.
            elseif data.type == 'note_off' then
                grid.led[target.x][target.y] = Grid.rainbow_off[mute.track.id] -- note_off muted.
            end
        end
            
        grid:refresh()
    end
end

function MuteGrid:grid_event (mute, data)
  local grid = self.grid
    if data.type == 'pad' and data.state then

        local note = grid:grid_to_index(data) - 1
        
        if mute.track.triggered then
            mute.active = data.toggled
        else
            mute.state[note] = data.toggled
        end
        
        if mute.track.triggered then
            
            if mute.active then
                mute.track:kill()
                mute.track.note_on = {}
                grid.led[data.x][data.y] = Grid.rainbow_off[mute.track.id]
            else
                grid.led[data.x][data.y] = 0
            end            
        else
            local state = mute.state[note]
            
            if state then

                grid.led[data.x][data.y] = Grid.rainbow_off[mute.track.id]
                
                local on = mute.track.note_on[note] -- added check to help preserve note on/off while recording
                
                if on then
                    local off = {type='note_off', ch = on.ch, note = on.note, vel = on.vel}
                    mute.track:send_output(off)
                end
            
            else
                grid.led[data.x][data.y] = 0
            end
        end

        grid:refresh('grid event')
    end  
end

return MuteGrid