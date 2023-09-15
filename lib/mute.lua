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

function Mute:midi_event(data)
    
    if data.note ~= nil then
        local grid = self.grid      
        local note = data.note

        local state = self.state[note] 
        
        if self.track.triggered then
          state = self.state[self.track.trigger]
        end

        for i = 1, #App.track do
            local track = App.track[i]

            if not self.track.triggered and self.track.midi_in == track.midi_in and note == track.trigger then
                goto continue
            end
        end
        

        if grid then
            
            local target = self.grid:index_to_grid(note + 1)
            
            if self.track.triggered then
                target = self.grid:index_to_grid(self.track.trigger + 1)
            end

            

            if (not state) then
                -- Mute is off
                if data.type == 'note_on' then
                    self.grid.led[target.x][target.y] = 3 -- note_on unmuted.
                elseif data.type == 'note_off' then
                    self.grid.led[target.x][target.y] = 0 -- note_on unmuted.
                end
            else
                -- Mute is on
                if data.type == 'note_on' then
                    self.grid.led[target.x][target.y] = Grid.rainbow_on[self.track.id] -- note_on muted.
                elseif data.type == 'note_off' then
                    self.grid.led[target.x][target.y] = Grid.rainbow_off[self.track.id] -- note_off muted.
                end
            end
            
            if self.grid.active then
                self.grid:refresh()
            end
        end

        if (not state) then
            return data
        end
        
        ::continue::
    end
end


function Mute:grid_event(data)
    if data.type == 'pad' and data.state then
        local note = self.grid:grid_to_index(data) - 1
        self.state[note] = data.toggled
        
        local state = data.toggled

        for i = 1, #App.track do
            local track = App.track[i]
         
            if self.track.id ~= track.id and track.triggered and track.trigger == note then
                state = self.state[self.track.trigger]
            end
        end
        
        if self.track.triggered then
        
            if state then
                for n,e in pairs(self.track.seq.note_on) do
                    local off = {type='note_off', ch = e.ch, note = e.note, vel = e.vel,penis = 'big'}
                    self.track:process_midi(off)
                    self.track.output:kill()
                end
               
                self.track.seq.note_on = {}

                self.grid.led[data.x][data.y] = Grid.rainbow_off[self.track.id]
            else
                self.grid.led[data.x][data.y] = 0
            end
            
            self.grid:refresh('grid event')
        elseif state then

            self.grid.led[data.x][data.y] = Grid.rainbow_off[self.track.id]
            self.grid:refresh('grid event')
            local on = self.track.seq.note_on[note] -- added check to help preserve note on/off while recording
            
            if on then
                local off = {type='note_off', ch = on.ch, note = on.note, vel = on.vel}
                self.track:process_midi(off)
            end
            
        else
            self.grid.led[data.x][data.y] = 0
            self.grid:refresh('grid event')
        end

    end
end

return Mute