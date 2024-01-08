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
	self.id = o.id or 0
	self.track = o.track
	self.on_transport = o.on_transport or function(s,data) return data end
	self.on_midi = o.on_midi or function(s,data) return data end
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