
-- device_manager.lua
local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')

local DeviceManager = {}
DeviceManager.__index = DeviceManager

-- Define the base Device with no-op methods
local Device = {
    on = function() end,
    off = function() end,
    emit = function() end,
    send = function() end,
    device = {
        send = function() end,
        start = function() end,
        stop = function() end,
        continue = function() end,
        clock = function() end,
        program_change = function() end
    }
}

-- DeviceMethods inherit from Device and provide methods to interact with the manager
local DeviceMethods = {}
setmetatable(DeviceMethods, {__index = Device})

function DeviceMethods:on(event_name, func)
    return self.manager:on(self.id, event_name, func)
end

function DeviceMethods:off(event_name, func)
    self.manager:off(self.id, event_name, func)
end

function DeviceMethods:emit(event_name, data)
    self.manager:emit(self.id, event_name, data)
end

function DeviceMethods:send() end

-- MIDIDevice inherits from DeviceMethods and adds MIDI-specific methods
local MIDIDevice = {}
setmetatable(MIDIDevice, {__index = DeviceMethods})

function MIDIDevice:start()
    self.device:start()
end

function MIDIDevice:stop()
    self.device:stop()
end

function MIDIDevice:continue()
    self.device:continue()
end

function MIDIDevice:clock()
    self.device:clock()
end

-- Register track trigger on midi device
function MIDIDevice:add_trigger(track)

    for i,t in ipairs(self.triggers) do
        if t.id == track.id then
            table.remove(self.triggers,i)
        end
    end

    table.insert(self.triggers, track)
end

function MIDIDevice:remove_trigger(track)
    for i,t in ipairs(self.triggers) do
        if t.id == track.id then
            table.remove(self.triggers,i)
        end
    end
end

function MIDIDevice:program_change(...)
    self.device:program_change(...)
end

function MIDIDevice:send(data)
    -- Perform note handling check here

    if data.type then
        self.manager:emit(self.id, data.type, data)

        if data.type == 'note_on' then
            -- Create one-time listener that waits for subsequent events on device
            local note_handle_events = { 'note_on', 'note_off', 'stop', 'kill', 'interrupt' }
            
            local off = {
                type = 'note_off',
                note_id = data.note,
                note = data.note,
                vel = data.vel,
                ch = data.ch,
            }

            if data.new_note then
                off.note = data.new_note
            end

            -- One-time listener
            local function last_note_on (next)
                local remove_event = false

                if not next then -- no 'next' note data means kill triggered callback
                    self.device:send(off)
                    remove_event = true
                elseif next.type == 'stop' then
                    -- If stop is recieved, and a note_off wasn't processed (might cause double note_off events)
                    print('stop recieved')
                    self.device:send(off)
                    remove_event = true
                elseif next.ch == off.ch then
                    -- This will trigger for all subsequent note events on the device's channel
                    
                    if next.note == off.note_id then
                        self.device:send(off) -- If we recieve duplicate events
                        remove_event = true
                    elseif next.type == 'interrupt' and next.note_class == off.note_id % 12 then
                        self.device:send(off)
                        remove_event = true

                    end
                
                end

                -- Remove listener
                if remove_event then
                    for i,event in ipairs(note_handle_events) do
                        self.manager:off(self.id, event, last_note_on)
                    end
                end
            end -- End last_note_on
            
            -- Bind on-time listener
            for i,event in ipairs(note_handle_events) do
                self.manager:on(self.id, event, last_note_on)
            end
        end
    end

    local send = {}
    for key, value in pairs(data) do
        send[key] = value
    end
    
    if data.new_note then
        send.note = data.new_note
    end

    self.device:send(send)
end

function MIDIDevice:kill()
    self.manager:emit(self.id, 'kill')
end

-- CrowDevice inherits from DeviceMethods and adds Crow-specific methods
local CrowDevice = {}
setmetatable(CrowDevice, {__index = DeviceMethods})

function CrowDevice:query(input)
    crow.input[input].query()
end

function CrowDevice:send(data)
    if data.action then
        crow.output[data.ch].action = data.action
        
        if data.dyn then
            for k,v in pairs(data.dyn) do
                crow.output[data.ch].dyn[k] = v
            end
        end

        crow.send('output[' .. data.ch .. ']()')
    elseif data.volts then
        crow.output[data.ch].volts = data.volts
    end

end

local VirtualDevice = {}
setmetatable(VirtualDevice, {__index = DeviceMethods})


-- DeviceManager:add method to add any device type
function DeviceManager:add(props, methods)
    props = props or {}
    methods = methods or Device

    -- Initialize device properties
    local new_device = setmetatable({
        type = props.type or 'none',
        name = props.name or 'None',
        manager = self,
        id = props.id or #self.devices + 1,
        device = props.device or {
            send = function() end,
            start = function() end,
            stop = function() end,
            continue = function() end,
            clock = function() end,
            program_change = function() end
        }
    }, { __index = methods })

    -- Add the new device to the devices list
    table.insert(self.devices, new_device)

    -- Assign the trimmed name directly based on device.id
    self.device_names[new_device.id] = new_device.name

    return new_device
end

-- Device Manager:new method to initialize the DeviceManager
function DeviceManager:new()
    local d = setmetatable({}, self)
    d.devices = {} -- List of devices
    d.midi = {}
    d.virtual = {}
    d.crow = {input = {}, output = {}}
    d.event_listeners = {}

    d.device_names = {} -- Indexed by device.id
    d.midi_device_names = {}
    
    print('Registering Devices:')
    -- Register MIDI devices
    for i = 1, #midi.vports do
        d:register_midi_device(i)
    end

    print('\n')
    -- Register Crow device
    d:register_crow_device()

    -- Register Virtual Device
    d:register_virtual_device()

    d.none = d:add({id = 0})
    
    return d
end

-- Event Management Methods
function DeviceManager:on(device_id, event_name, callback)
    if device_id == 0 then return end -- Prevent adding events for "None" device

    if not self.event_listeners[device_id] then
        self.event_listeners[device_id] = {}
    end

    if not self.event_listeners[device_id][event_name] then
        self.event_listeners[device_id][event_name] = {}
    end

    table.insert(self.event_listeners[device_id][event_name], callback)

    local cleanup = function()
        self:off(device_id, event_name, callback)
    end

    return cleanup
end

function DeviceManager:off(device_id, event_name, listener)
    if device_id == 0 then return end -- Prevent removing events for "None" device

    if self.event_listeners
       and self.event_listeners[device_id]
       and self.event_listeners[device_id][event_name] then

        for i, l in ipairs(self.event_listeners[device_id][event_name]) do
            if l == listener then
                table.remove(self.event_listeners[device_id][event_name], i)
                break
            end
        end
    end
end

function DeviceManager:emit(device_id, event_name, data)
    -- Emit device event to subscribers
    if self.event_listeners
       and self.event_listeners[device_id]
       and self.event_listeners[device_id][event_name] then

        -- Create a shallow copy of the listeners to prevent issues during iteration
        local listeners = { table.unpack(self.event_listeners[device_id][event_name]) }

        for _, listener in ipairs(listeners) do
            listener(data)
        end
    end
end

function DeviceManager:send(device_id, event_data)
    -- Send events out to a device (e.g., MIDI out)
    local dev = self.devices[device_id]
    if not dev then
        return
    end

    dev:send(event_data)

end

function DeviceManager:get(n)
    return self.devices[n]
end

-- Register a MIDI Device
function DeviceManager:register_midi_device(port)
    local midi_device = midi.connect(port)
    

    if not midi_device or midi_device.name == 'none' then
        return -- Skip if no MIDI device is connected
    end

    print("MIDI " .. port .. "\t\t" .. midi_device.name)

    local trimmed_name = util.trim_string_to_width(midi_device.name, 70)

    table.insert( -- register its name:
		  self.midi_device_names, -- table to insert to
		  trimmed_name
		)

    local props = {
        type = 'midi',
        name = midi_device.name,
        port = port,
        device = midi_device,
        trimmed_name = trimmed_name,
    }

    local device = self:add(props, MIDIDevice)
    device.triggers = {}

    table.insert(self.midi,device)

    -- Setup MIDI event handler
    midi_device.event = function(msg)
        local event = midi.to_msg(msg)
        
        if device.event then
            device.event(msg) -- Call device's event method if it exists eg. Midi Grid
        else
            if event.type == 'start' or event.type == 'stop' or event.type == 'continue' or event.type == 'clock' then
                self:emit(device.id, 'transport_event', event)
            elseif event.type == 'program_change' then
                self:emit(device.id, 'program_change', event)
            elseif event.type == 'cc' then
                self:emit(device.id, 'cc', event)
            else
                local send = true
                local midi_tracks = {}
                
                -- Check for single note triggers
                for i,track in ipairs(device.triggers) do
                    if track.midi_in == event.ch then
                        if track.input_type ~= 'midi' and event.note == track.trigger then
                            if track.step == 0 then track:emit('midi_trigger', event) end
                            send = false
                        elseif track.input_type == 'midi' then
                            table.insert(midi_tracks, track)
                        end
                    end
                end

                -- If no triggers are found, send event to all MIDI tracks
                if send then
                    for i,track in ipairs(midi_tracks) do
                        track:emit('midi_event', event)
                    end
                end

                self:emit(device.id, event.type, event)
            end
        end

    end

end



-- Register a Virtual Device
function DeviceManager:register_virtual_device()

    local props = {
        type = 'virtual',
        name = 'Virtual Device'
    }

    local new_device = self:add(props, VirtualDevice)
    
    self.virtual = new_device

    self:on(new_device.id, 'trigger', function(event)
        print('Virtual Device Triggered: ' .. event.track.id)
        
        if event and event.callback then
            event.callback(event.data)
        end
    end)
end

-- Register a Crow Device
function DeviceManager:register_crow_device()
    local props = {
        type = 'crow',
        name = 'Crow',
        device = crow,
    }

    local crow_device = self:add(props,CrowDevice)
    self.crow = crow_device

    crow_device.input = {}
    crow_device.output = {}

    -- Crow Setup
    local CROW_INPUTS = 2
    for index = 1, CROW_INPUTS do
        -- Initialize state for each input
        crow_device.input[index] = { volts = 0 }

        -- Set up Crow input handlers
        crow.send("input[" .. index .. "].query = function() stream_handler(1, input[" .. index .. "].volts) end")

        crow_device.device.input[index].stream = function(v)
            crow_device.input[index].volts = v -- Update the state
            self:emit(crow_device.id, 'stream', { input = index, volts = v }) -- Include input index in the event
        end

        crow_device.device.input[index].mode('none')

    end

    -- Register a default stream event listener
    self:on(crow_device.id, 'stream', function(data)
        print("Crow input " .. data.input .. " stream event: " .. data.volts .. "V")
    end)

end

return DeviceManager