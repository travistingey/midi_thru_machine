local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Bitwise = require(path_name .. 'bitwise')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

-- Input Class
-- first component in a Track's process chain that accepts midi or transport events
local Input = {}
Input.name = 'input'
Input.__index = Input
setmetatable(Input,{ __index = TrackComponent })

function Input:new(o)
    o = o or {}
    setmetatable(o, self)
    TrackComponent.set(o,o)
    o:set(o)
    return o
end

function Input:set(o)
    for i,prop in ipairs(Input.params) do
        self[prop] = o[prop]
    end
end

function Input:transport_event(data)
    if self.track.step > 0 and self.track.input_type ~= 'midi' then
        self:clock_trigger(data, self.process)
    end
    return data
end

function Input:midi_trigger(data)
    if self.track.step == 0 and data.ch == self.track.midi_in and data.note == self.track.trigger then
        if data.type == 'note_on' then
            local event = {}
            self.track.step_count = self.track.step_count + 1

            if self.track.step_count == self.track.reset_step then
                self.track.step_count = 0
                self.index = 0
            end

            for prop,v in pairs(data) do
                event[prop] = v
            end

            event = self:process(event)
            
            if self.last_note then
                self.last_note = event
            else
                self.last_note = event
            end
            
            self.track:send_input(event)
        elseif data.type == 'note_off' then
            local event = self.last_note
            local send = {}
            if event then
                for prop,v in pairs(event) do
                    send[prop] = v
                end
                send.type = 'note_off'
                self.track:send_input(send)
            end
        end
    end

end

function Input:clock_trigger(data,process)
    if self.track.step > 0 and self.track.reset_step > 0 and App.tick % (self.track.reset_step * self.track.step) == self.track.reset_tick then
        self.track.reset_tick = App.tick % self.track.step
        self.index = 0
    end
    
    if self.track.step > 0 and App.tick % self.track.step == self.track.reset_tick then
        local event = self:process(data)
        if event then
            clock.run(function()
                self.track:send_input(event)

                local off = { type = 'note_off', note = event.note, vel = event.vel }

                clock.sync(math.ceil(self.track.step/2)/24)
                self.track:send_input(off)
            end)
        end
    end
end



Input.options = {'midi','arpeggio','random','bitwise','chord','crow'}
Input.params = {'midi_in','trigger','crow_in','note_range_upper','note_range_lower','arp','note_range','step','reset_step','chance','voice','step_length'} -- Update this list to dynamically show/hide Track params based on Input type

Input.types = {}

-- MIDI Input
-- Note: Set actions are called from the load_component function.
Input.types['midi'] = {
    props = {'midi_in', 'note_range_upper','note_range_lower'},
    set_action = function(s,track)
        track.triggered = false

        if track.input_cleanup then
            track.input_cleanup()
        end

        track.input_cleanup = track:on('midi_event', function(data)
            s.track:send_input(data)
        end)
    end
}

Input.set_trigger = function (s, track)
    params:set('track_' .. track.id .. '_voice', 2) -- mono
    params:set('track_' .. track.id .. '_note_range_lower', 60) -- mono
    track.triggered = true
    s.index = 0

    if track.input_cleanup then
        track.input_cleanup()
    end
    
    track.input_cleanup = track:on('midi_trigger', function(data) s.midi_trigger(s, data) end)
end

-- Crow Input
-- crow.send('input[1].query()') will query and save values to App.crow_in[1].volts
Input.types['crow'] = {
    props = {'trigger'},
    set_action = function(s, track)
        track:kill()
        Input.set_trigger(s,track)
    end,
    process = function(s, data)
        App.crow:query(s.track.crow_in)
        local note = math.floor(App.crow.input[s.track.crow_in] * 12) + s.track.note_range_lower
        local vel = data.vel
        return {type = 'note_on', note = note, vel = vel }
    end
}

-- Arpeggiator
Input.types['arpeggio'] = {
    props = {'trigger','note_range_lower','note_range'},
    set_action = function(s, track)
        Input.set_trigger(s,track)
        
        if track.scale_select == 0 then
            params:set('track_' .. track.id .. '_scale_select',1)
        end       
    end,
    process = function (s, data)
        local intervals = s.track.scale.intervals
        local note

        if #intervals == 0 then 
            intervals = {0,1,2,3,4,5,6,7,8,9,10,11}
        end
        
        local range = params:get('track_' .. s.track.id .. '_note_range') * #intervals
        local root = s.track.note_range_lower
    
        if s.track.arp == 'up' then                        
            s.index = util.wrap(s.index + 1, 1,range)        
            local octave = (math.ceil( s.index / #intervals) - 1) * 12
            note = root + intervals[(s.index-1) % #intervals + 1 ] + octave
        elseif s.track.arp == 'down' then
            s.index = util.wrap(s.index + 1, 1, range)
            local select = (#intervals + 1) - ((s.index-1) % #intervals + 1)
            local octave = (math.floor( (range -  (s.index)) / #intervals) ) * 12
            note = root + intervals[select] + octave
        elseif s.track.arp == 'up down' then
            s.index = util.wrap(s.index + 1, 1,range * 2 - 2) 

            if s.index <= range then       
                local octave = (math.ceil( s.index / #intervals) - 1) * 12
                note = root + intervals[(s.index-1) % #intervals + 1 ] + octave
            else
                local select = (#intervals + 1) - (s.index % #intervals + 1)
                local octave = (math.ceil( (range - (s.index - range )) / #intervals) - 1) * 12
                note = root + intervals[select] + octave
            end
        elseif s.track.arp == 'down up' then
            s.index = util.wrap(s.index + 1, 1,range * 2 - 2) 

            if s.index <= range then       
                local select = (#intervals + 1) - ((s.index-1) % #intervals + 1)
                local octave = (math.floor( (range -  (s.index)) / #intervals) ) * 12
                note = root + intervals[select] + octave

            else
                local octave = (math.floor( s.index / #intervals) - 2) * 12
                note = root + intervals[(s.index-range) % #intervals + 1 ] + octave
            end
            
        elseif s.track.arp == 'converge' then
            
            s.index = util.wrap(s.index + 1, 1, range)

            local index = 1
            
            if s.index % 2 == 0 then       
                index = range - (s.index - (math.ceil(s.index/2) + 1) )
            else
                index = s.index - (math.ceil(s.index/2) - 1)
            end
            
            local octave = (math.ceil( index / #intervals) - 1) * 12
            note = root + intervals[(index - 1) % #intervals + 1] + octave

        elseif s.track.arp == 'diverge' then
            
            s.index = util.wrap(s.index + 1, 1, range)
            
            local index = 1
            
            if s.index % 2 == 0 then       
                index = range - (s.index - math.ceil(s.index/2) + math.floor(range/2) - 1)
            else
                index = s.index - math.ceil(s.index/2) + math.floor(range/2) + 1
            end

            local octave = (math.ceil( index / #intervals) - 1) * 12
            note = root + intervals[(index - 1) % #intervals + 1] + octave

        end
        return {type = 'note_on', note = note, vel = data.vel }
    end

}

Input.types['chord'] = {
    props = {'trigger','note_range_lower','note_range'},
    set_action = function(s, track)
        Input.set_trigger(s,track)     
    end
}

-- Random Notes
Input.types['random'] = {
    props = {'trigger','note_range_lower','note_range'},
    set_action = function(s, track)
       Input.set_trigger(s,track)
    end,
    process = function (s, data)
        local note = math.random(s.track.note_range_lower, s.track.note_range_upper)
        return {type = 'note_on', note = note, vel = data.vel }
    end
}

-- Bitwise Sequencer
Input.types['bitwise'] = {
    props = {'trigger','note_range_lower','note_range','chance','step_length'},
    set_action = function(s, track)
        Input.set_trigger(s,track)
        track.chance = params:get('track_' .. track.id .. '_chance')
        track.step_length = params:get('track_' .. track.id .. '_step_length')

        s.note = Bitwise:new({
            chance = track.chance,
            format = function(value) 
                return util.wrap(math.floor( value * 127 ), track.note_range_lower, track.note_range_upper)
            end
        })
        
        s.vel = Bitwise:new({
            format = function(value)
                return math.floor( value * 127 )
            end
        })
    end,
    process = function(s, data)
        s.note.chance = s.track.chance
        s.vel.chance = s.track.chance

        s.note.length = s.track.step_length
        s.vel.length = s.track.step_length

        s.index = util.wrap(s.index + 1,1,s.track.step_length)
        
        s.note:mutate(s.index)
        s.vel:mutate(s.index)
        
        if s.note:get(s.index).state and data.type == 'clock' or data.type == 'midi' then
            return {type = 'note_on', note = s.note:get(s.index).value, vel = s.vel:get(s.index).value }
        end
    end
}


return Input