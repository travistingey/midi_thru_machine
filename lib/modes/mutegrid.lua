local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local MuteGrid = ModeComponent:new()
MuteGrid.__base = ModeComponent
MuteGrid.name = 'Mode Name'

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
    local current = App.track[self.track]
    --[[
        Prior to on_enable running, the parent mode script will apply the following to the specified track and component:
        track.mute.grid.event = mode.grid_event
        mode.set_grid(component)
        component.on_midi = mode.midi_event
        component.on_transport = mode.transport_event 
    ]]


    -- If the mode's current track is a trigger we need to find the base track
    if current.triggered then
        for i = 1, #App.track do
            --check each track, if we find a track that is not triggered and has the same midi_in, we'll set that to the base
            if not App.track[i].triggered and App.track[i].midi_in == current.midi_in and App.track[i].active then
                self.base = App.track[i]
            end 
        end
    else
        self.base = current -- self.track is the base track
    end
    
    if self.base == nil then
        print('no base')
    end

    -- for each track find the triggers matching the base track
    if self.base ~= nil then
        for i = 1, #App.track do
            local track = App.track[i]

            if self.base ~= track and track.midi_in == self.base.midi_in  and track.triggered then
                -- store the trigger in the mode
                self.triggers[track.trigger] = track
                
                -- and assign the mode's midi event to the trigger
                track.mute.on_midi = function(s, data)
                    self:midi_event(s, data)
                end
            elseif self.base == track then
                track.mute.on_midi = function(s,data)
                    self:midi_event(s,data)
                end
            end
        end
    end

    self.grid.event = function(s,d)
        if self.grid:in_bounds(d) then
            if self.base then
                self:grid_event(self.base.mute, d)
            end

            local note = self.grid:grid_to_index(d) - 1

            if self.triggers[note] ~= nil and self.triggers[note] ~= self.base then
                self:grid_event(self.triggers[note].mute, d)
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
            target = grid:index_to_grid(mute.track.trigger + 1)
            state = mute.state[mute.track.trigger]
        else
            state = self.base.mute.state[note] 
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
                
                for n,e in pairs(mute.track.note_on) do
                    print('note was on')
                    local off = {type='note_off', ch = e.ch, note = e.note, vel = e.vel}
                    mute.track:process_midi(off)
                    mute.track:kill()
                end
               
                mute.track.note_on = {}
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