local path_name = 'Foobar/lib/'
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Grid = require(path_name .. 'grid')

-- Mute controls events just before output

local Mute = {}
Mute.name = 'mute'
Mute.__index = Mute
setmetatable(Mute, { __index = TrackComponent })

function Mute:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
	o:set(o)
	return o
end

function Mute:set(o)
	self.id = o.id
	self.grid = o.grid
	self.state = {}
	self.active = false

	for i = 0, 127 do
		self.state[i] = false
	end

	-- set the mute state of a note
	self:on('set_mute', function(note, state) self.state[note] = state end)

	-- set the mute state of entire track (used for triggers)
	self:on('set_all', function(state) self.active = state end)
end

function Mute:midi_event(data)
	if data.note ~= nil then
		local grid = self.grid
		local note = data.note
		local state = self.state[note]

		-- active will mute all notes. used for trigger mutes and buffer recording.
		if self.active == true then state = true end

		if not state then return data end
	end
end

return Mute
