local path_name = 'Foobar/lib/'
local TrackComponent = require(path_name .. 'trackcomponent')
local Grid = require(path_name .. 'grid')
local musicutil = require(path_name .. 'musicutil-extended')

-- 

local Scale = TrackComponent:new()
Scale.__base = TrackComponent
Scale.name = 'scale'

function Scale:set(o)
	self.__base.set(self, o) -- call the base set method first   
	
	self.grid = o.grid
	self.root = o.root or 0
	self.bits = o.bits or 0
	self.follow = o.follow or 0
	self.follow_method = o.follow_method or 1
	self.scale_select = o.scale_select or 0
	self.reset_latch = false
	self.latch_notes = {}
	self.intervals = o.intervals or {}
end


function Scale:register_params(id)
	local scale = 'scale_' .. id .. '_'
	params:add_group('Scale ' .. id, 4 ) 

	params:add_number(scale .. 'bits', 'Bits',0,4095,0)
	params:set_action(scale .. 'bits',function(bits)
		
		App.scale[id]:set_scale(bits)
		
		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)
	
	params:add_number(scale .. 'root', 'Root',-24,24,0)
	params:set_action(scale .. 'root', function(root)
		App.scale[id].root = root

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)

	params:add_number(scale .. 'follow', 'Follow',0,3,0)
	params:set_action(scale .. 'follow', function(d)
		App.scale[id].follow = d

		if d > 0 then
			for i = 1, 3 do 
				App.scale[i]:follow_scale()
			end
		end
		
		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)

	params:add_option(scale .. 'follow_method', 'Follow Method',{'transpose','scale degree','pentatonic','midi on', 'midi latch'},1)
	params:set_action(scale .. 'follow_method', function(d)
		App.scale[id].follow_method = d

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)

end


function Scale:set_scale(bits)
	self.bits = bits
	self.intervals = musicutil.bits_to_intervals(bits)
	self.notes = {}

	params:set('scale_'..self.id..'_bits', bits, true)

	local i = 0
  
	for oct=1,10 do
		for i=1,#self.intervals do
			self.notes[(oct - 1) * #self.intervals + i] = self.intervals[i] + (oct-1) * 12
		end
	end
	
end


function Scale:shift_scale_to_note(n)
	local scale = musicutil.shift_scale(self.bits, n - self.root)
	self.root = n

	self:set_scale(scale)
	params:set('scale_'..self.id..'_root', n)
end

function Scale:follow_scale(notes)
	local scale = 'scale_' .. self.id .. '_'
	if self.follow > 0 then
		local other = App.scale[self.follow]
		
		if self.follow_method == 1 then
			-- Transpose			
			self.root = other.root
			params:set(scale .. 'root', other.root, true)
		elseif self.follow_method == 2 then
			-- App.scale Degree
			self:shift_scale_to_note(other.root)
			params:set(scale .. 'root', other.root, true)
		elseif self.follow_method == 3 then
			-- Pentatonic
			local major = musicutil.intervals_to_bits({0,4})
			local minor = musicutil.intervals_to_bits({0,3})

			if other.bits & major == major then
				self:set_scale(661)
				self.root = other.root
				params:set(scale .. 'root', other.root, true)
				
			elseif other.bits & minor == minor then
				self:set_scale(1193)
				self.root = other.root
				params:set(scale .. 'root', other.root, true)
			else
				self:set_scale(1)
				self.root = other.root
				params:set(scale .. 'root', other.root, true)
			end
		end
	elseif self.follow_method > 3 and notes then
		
		-- MIDI controlled
		local b = 0
		local n = {}
		local min = 0
		
		for note in pairs(notes)do
			if min == 0 or note < min then
				min = note
			end
			n[#n + 1] = notes[note].note
		end

		for i= 1, #n do
			n[i] = (n[i] - min) % 12
		end
		
		local s = musicutil.intervals_to_bits(n)
		self.root = min % 12
		params:set(scale .. 'root', self.root, true)
		
		self:set_scale(s)

	end
end

function Scale:transport_event(data,track)
	if data.type == 'start' then
		self.reset_latch = false
	end

	return data
end

function Scale:midi_event(data, track)
    local root = self.root
    
    if data.note then
		if self.follow_method == 4  and (data.type == 'note_on' or data.type == 'note_off') then
			self:follow_scale(track.note_on)
			return data
		elseif self.follow_method == 5 and (data.type == 'note_on' or data.type == 'note_off') then
			local count = 0
			
			for n in pairs(track.note_on) do 
				count = count + 1
			end

			if data.type == 'note_off' and count == 0 then
				self.reset_latch = true
			elseif data.type == 'note_on' then
				if self.reset_latch then
					self.latch_notes = {}
					self.reset_latch = false
				end
				self.latch_notes[data.note] = data
				self:follow_scale(self.latch_notes)
			end

			for i=1,3 do
				App.scale[i]:follow_scale()
			end

			return data
		else

			if self.bits == 0 then
				return data
			elseif data.type == 'note_on' then

				data.note = musicutil.snap_note_to_array(data.note, self.notes) + root
				track.note_on[data.note] = data
				
				return data
			elseif data.type == 'note_off' then

				if track.note_on[data.note] then
					data.note = track.note_on[data.note].note
				end
				return data
			end
		end
  	else
		
		  return data
    end
end

return Scale