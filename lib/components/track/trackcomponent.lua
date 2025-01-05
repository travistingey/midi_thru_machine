--- Base Class
local TrackComponent = {}
TrackComponent.__index = TrackComponent

function TrackComponent:new(o)
	o = o or {}
	setmetatable(o, self)
	self:set(o)
	return o
end

function TrackComponent:set(o)
	-- Set up default methods if none are provided
	self.transport_event = o.transport_event or function(s,data) return data end
	self.midi_event = o.midi_event or function(s,data) return data end
	self.type = o.type
	self.track = o.track

	if self.types and self.type and self.types[self.type] then
		local type = self.types[self.type]
		-- if TrackComponent type has certain events, register them
		if type.transport_event ~= nil then
			self.transport_event = type.transport_event
		end

		if type.midi_event ~= nil then
			self.midi_event = type.midi_event
		end

		if type.process ~= nil then
			self.process = type.process
		end

		if type.set_action ~= nil then
			self.set_action = type.set_action
			self:set_action(self.track)
		end

		
	end
end

function TrackComponent:process_transport(data, track)
	if data ~= nil then
		local send = data

		if self.transport_event ~= nil then
			send = self:transport_event(data, track)
		end

		self:emit('transport_event', data, track)
		
		return send
	end
end

function TrackComponent:process_midi(data, track)
	if data ~= nil then
		local send

		if self.midi_event ~= nil then
			send = self:midi_event(data, track)
		end

		self:emit('midi_event', data, self)

		return send
	end
end


function TrackComponent:on(event_name, listener)
    if not self.event_listeners then
        self.event_listeners = {}
    end
	if not self.event_listeners[event_name] then
        self.event_listeners[event_name] = {}
    end
    table.insert(self.event_listeners[event_name], listener)

	return function()
		self:off(event_name, listener)
	end
end

function TrackComponent:off(event_name, listener)
    if self.event_listeners and self.event_listeners[event_name] then
        for i, l in ipairs(self.event_listeners[event_name]) do
            if l == listener then
                table.remove(self.event_listeners[event_name], i)
                break
            end
        end
    end
end

function TrackComponent:emit(event_name, ...)
    if self.event_listeners and self.event_listeners[event_name]then
        for _, listener in ipairs(self.event_listeners[event_name]) do
            listener(...)
        end
    end
end

return TrackComponent