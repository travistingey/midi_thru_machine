local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')
local Grid = require(path_name .. 'grid')


-- Mute controls events just before output

local Mute = TrackComponent:new()
Mute.__base = TrackComponent
Mute.name = 'mute'

function Mute:set(o)
	self.__base.set(self, o) -- call the base set method first   
	o.id = o.id
    o.grid = o.grid
    o.state = {}

    for i= 0, 127 do
        o.state[i] = false
    end
end

function Mute:set_grid()

    self.grid:refresh()
end

function Mute:midi_event(data)
    
    if data.note ~= nil then
        local target = self.grid:index_to_grid(data.note + 1)
        local state = self.state[data.note]
        
        
        if (not state) then
            -- Mute is off
            if data.type == 'note_on' then
                self.grid.led[target.x][target.y] = 3 -- note_on unmuted.
            elseif data.type == 'note_off' then
                self.grid.led[target.x][target.y] = 0 -- note_on unmuted.
            end
            self.grid:refresh()
            return data
        else
            -- Mute is on
            if data.type == 'note_on' then
                self.grid.led[target.x][target.y] = Grid.rainbow_on[self.id] -- note_on muted.
            elseif data.type == 'note_off' then
                self.grid.led[target.x][target.y] = Grid.rainbow_off[self.id] -- note_off muted.
            end
            self.grid:refresh()
        end
        
    end
end

function Mute:grid_event(data)
    if data.type == 'pad' then
        
        local note = self.grid:grid_to_index(data) - 1
        self.state[note] = data.toggled

        local state = data.toggled
        
        if state then 
            self.grid.led[data.x][data.y] = Grid.rainbow_off[self.id]
            
            local on = self.track.seq.note_on[note] -- added check to help preserve note on/off while recording
            
            if on then
                local off = {type='note_off', ch = on.ch, note = on.note, vel = on.vel}
                print('note was on when mute was pressed')
                self.track:process_midi(off)
            end
        else
            self.grid.led[data.x][data.y] = 0
        end
        
        
        
        
        self.grid:refresh()
    end
end

return Mute