local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local MuteGrid = ModeComponent:new()
MuteGrid.__base = ModeComponent
MuteGrid.name = 'Mode Name'

function MuteGrid:set(o)
	self.__base.set(self, o) -- call the base set method first   

   o.component = 'mute'
   o.register = {'on_load'} -- list events outside of transport, midi and grid events

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
    local base = App.track[self.track]

    for i = 1, #App.track do
        local track = App.track[i]

        if base ~= track and track.midi_in == self.track then
            if track.triggered then
                self.triggers[track.trigger] = track
                print('set the trigger for ' .. track.id)
            end

            track.mute.on_midi = function(s, data)
               self:midi_event(s, data)
            end

        end
    end

    local component = self:get_component()

    self.grid.event = function(s,d)
        
        self:grid_event(component, d)
        
        local note = self.grid:grid_to_index(d) - 1

        if self.triggers[note] ~= nil then
            self:grid_event(self.triggers[note].mute, d)
        end
        
    end
end

function MuteGrid:on_disable()
    local base = App.track[self.track]
    
    for i = 1, #App.track do
        local track = App.track[i]
        if base ~= track and track.midi_in == self.track then           
            track.mute.on_midi = nil
        end
    end

    self.grid.event = nil
end

function MuteGrid:midi_event (mute, data)
    local base = App.track[self.track]

    if data and data.note then
        local note = data.note
        local grid = self.grid
        local target = grid:index_to_grid(note + 1)
        local state = base.mute.state[note] 

        if mute.track.triggered then
            target = grid:index_to_grid(mute.track.trigger + 1)
            state = base.mute.state[mute.track.trigger] 
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
        
        mute.state[note] = data.toggled
        
        if mute.track.triggered then
            local state = mute.state[mute.track.trigger] 
            if state then
                for n,e in pairs(mute.track.seq.note_on) do
                    local off = {type='note_off', ch = e.ch, note = e.note, vel = e.vel}
                    mute.track:process_midi(off)
                    mute.track.output:kill()
                end
               
                mute.track.seq.note_on = {}
                if mute.track.exclude_trigger then
                    grid.led[data.x][data.y] = Grid.rainbow_off[mute.track.id]
                end
            else
                if mute.track.exclude_trigger then
                    grid.led[data.x][data.y] = 0
                end
            end            
        else
            local state = mute.state[note]
            
            if state then

                grid.led[data.x][data.y] = Grid.rainbow_off[mute.track.id]
                
                local on = mute.track.seq.note_on[note] -- added check to help preserve note on/off while recording
                
                if on then
                    local off = {type='note_off', ch = on.ch, note = on.note, vel = on.vel}
                    mute.track:process_midi(off)
                end
            
            else
                grid.led[data.x][data.y] = 0
            end
        end

        grid:refresh('grid event')
    end  
end

return MuteGrid