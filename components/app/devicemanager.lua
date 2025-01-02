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
    self.manager:on(self.id, event_name, func)
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

function MIDIDevice:add_trigger(trigger)
    table.insert(self.triggers, trigger)
end

function MIDIDevice:remove_trigger(track)
    for i,t in ipairs(self.triggers) do
        if t.track.id == track.id then
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
            local note_handle_events = { 'note_on', 'note_off', 'stop', 'kill' }
            
            local off = {
                type = 'note_off',
                note = data.note,
                vel = data.vel,
                ch = data.ch,
            }

            -- One-time listener
            local function last_note_on (next)
                
                local remove_event = false
                
                -- This will trigger for all subsequent note events on the device's channel
                if next.note == data.note and next.ch == data.ch then

                    -- If we recieve duplicate events
                    if next.type == 'note_on' then
                        self.device:send(off)
                    elseif next.type == 'note_off' then
                        -- If this is executing, standard note_off should resolve open note
                        -- Watching off events is needed for killing the listener
                    end

                    remove_event = true
                elseif next.type == 'stop' then
                    -- If stop is recieved, then a note_off wasn't processed
                    self.device:send(off)
                    remove_event = true
                end

                -- Remove listener
                if remove_event then
                    for i,event in ipairs(note_handle_events) do
                        self.manager:off(self.id, event, last_note_on)
                    end
                end
                
            end
            
            -- Bind on-time listener
            for i,event in ipairs(note_handle_events) do
                self.manager:on(self.id, event, last_note_on)
            end
            
        end
    end

    self.device:send(data)
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
    self.device_names[new_device.id] = props.trimmed_name or new_device.name

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
    

    -- Register MIDI devices
    for i = 1, #midi.vports do
        d:register_midi_device(i)
    end

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

        for _, listener in ipairs(self.event_listeners[device_id][event_name]) do
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
        print("Failed to connect to MIDI port " .. port)
        return
    end

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
    -- Assign the trimmed name directly based on device.id
    -- Already handled in add method

    -- Setup MIDI event handler
    midi_device.event = function(msg)
        local event = midi.to_msg(msg)
        
        if device.event then
            device.event(msg) -- Call device's event method if it exists eg. Midi Grid
        else
            -- if event and event.type then
            --     local send = true

            --     -- Run through devices triggers to determine if we should send the event
            --     if event.note then
            --         for i, trigger in ipairs(device.triggers) do
            --             if trigger.track.trigger == event.note and trigger.track.midi_in == event.ch then
            --                 self:emit(self.virtual.id, 'trigger', {track = trigger.track, trigger.callback, data = event})
            --                 send = false
            --             end
            --         end
            --     end

            --     -- This prevents device from sending an event
            --     if send then
            --         self:emit(device.id, event.type, event)
            --     end

            -- end

            self:emit(device.id, 'event', event)
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