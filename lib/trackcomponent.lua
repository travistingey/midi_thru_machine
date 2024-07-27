--- Base Class
local TrackComponent = {}

function TrackComponent:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	-- common functionality here
	self.set(o,o)
	
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

		
		if self.on_transport ~= nil then
			self:on_transport(data, track)
		end
		
		return send
	end
end

function TrackComponent:process_midi(data, track)
	if data ~= nil then
		local send

		if self.midi_event ~= nil then
			send = self:midi_event(data, track)
		end
		
		if self.on_midi ~= nil then
			self:on_midi(data, track)
		end

		return send
	end
end


return TrackComponent