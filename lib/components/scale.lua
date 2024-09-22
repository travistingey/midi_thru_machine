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
	
	self.chord = {
		index = 1,
		name = '',
		root = 0
	}

	self.follow_method = o.follow_method or 0
	self.scale_select = o.scale_select or 0
	self.reset_latch = false
	self.latch_notes = {}
	self.intervals = o.intervals or {}

	self.lock = false
end


function Scale:register_params(id)
	local scale = 'scale_' .. id .. '_'
	params:add_group('Scale ' .. id, 5 ) 

	params:add_number(scale .. 'bits', 'Bits',0,4095,0)
	params:set_action(scale .. 'bits',function(bits)
		App.settings[scale .. 'bits'] = bits
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
		App.settings[scale .. 'root'] = root
		App.scale[id].root = root

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)

	params:add_number(scale .. 'follow', 'Follow',0,16,0)
	params:set_action(scale .. 'follow', function(d)
		App.settings[scale .. 'follow'] = d
		App.scale[id].follow = d
		
		if App.scale[id].follow_method < 4 then
			App.scale[id].follow = util.clamp(App.scale[id].follow,0,3)	
		end
		if d > 0 then
			for i = 1, 3 do 
				App.scale[i]:follow_scale()
			end
		end
		
		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)

	params:add_option(scale .. 'follow_method', 'Follow Method',{'transpose','scale degree','pentatonic','midi on', 'midi latch','midi lock'},1)
	params:set_action(scale .. 'follow_method', function(d)
		App.settings[scale .. 'follow_method'] = d
		App.scale[id].follow_method = d

		if d < 4 then
			App.scale[id].follow = util.clamp(App.scale[id].follow,0,3)	
		end

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		if App.current_mode and App.mode[App.current_mode] then
			App.mode[App.current_mode]:enable()
		end
	end)


	params:add_number(scale .. 'lock_cc', 'Lock CC',0,127,64)
	params:set_action(scale .. 'lock_cc', function(cc)
		App:subscribe_cc(cc, function(data)
			if App.scale[id].follow == 0 then
				return
			end

			local track = App.track[App.scale[id].follow]
			local scale = App.scale[id]

			if data.ch == track.midi_in then
				if scale.follow_method > 3 then
					scale.lock = (data.val == 127)

					if scale.lock then
						scale.reset_latch = true
						scale.latch_notes = {}

						for k,v in pairs(track.note_on) do
							scale.latch_notes[k] = v
						end

						scale:follow_scale(scale.latch_notes)
					end
				end
			end
		end)
	end)
end


function Scale:set_scale(bits)
	self.bits = bits
	self.intervals = musicutil.bits_to_intervals(bits)
	self.notes = {}

	params:set('scale_'..self.id..'_bits', bits)

	local i = 0
  
	for oct=1,10 do
		for i=1,#self.intervals do
			self.notes[(oct - 1) * #self.intervals + i] = self.intervals[i] + (oct-1) * 12
		end
	end


	
end


function Scale:shift_scale_to_note(n)
	n = util.clamp(n,-24,24)
	local scale = musicutil.shift_scale(self.bits, n - self.root)
	self.root = n

	self:set_scale(scale)
	params:set('scale_'..self.id..'_root', n)
end


local PLAITS = {1,129,161,137,1161,1165,1197,661,1173,2193,145}	

function count_bits(n)
    -- Efficiently count bits using Kernighan's algorithm
    local count = 0
    while n > 0 do
        n = n & (n - 1)
        count = count + 1
    end
    return count
end

-- Precompute bit counts for all 12-bit numbers (0 to 4095)
local bit_counts = {}
for i = 0, 4095 do
    bit_counts[i] = count_bits(i)
end



function Scale.chord_id(bits, CHORDS)
    local best = {index = nil, score = -1}

	if type(bits) == 'table' then
		bits = bits.bits
	end
	
    bits = bits & 0xFFF  -- Ensure bits are in 12-bit range
    local bits_count = bit_counts[bits]
	
    for i = 1, #CHORDS do
        local set_bits = CHORDS[i] & 0xFFF
        local set_bits_count = bit_counts[set_bits]
        local matching_bits = bits & set_bits
        local matching_bits_count = bit_counts[matching_bits]

        -- Compute the Dice coefficient
        local score = (2 * matching_bits_count) / (bits_count + set_bits_count)

        if score > best.score then
            best = {index = i, score = score}
        end
    end

    if best.index then
        return best.index
    else
        return 1  -- Default to index 1 if no match is found
    end
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
		elseif self.follow_method > 3 and notes then
			-- MIDI controlled
			local b = 0
			local n = {}
			local min = 0
			
			for note in pairs(notes)do
				if min == 0 or note < min then
					min = note
				end
				n[#n + 1] = notes[note].note -- lol wut?
			end

			for i= 1, #n do
				n[i] = (n[i] - min) % 12
			end
			
			local s = musicutil.intervals_to_bits(n)
			if s > 0 then
				self.root = min % 12
			end
			params:set(scale .. 'root', self.root, true)
			
			self:set_scale(s)
		end
	end
end

function Scale:transport_event(data,track)
	if data.type == 'start' then
		self.reset_latch = false
	end

	return data
end


function Scale:midi_event(data, track)    
	if data.note then
		
		if data.type == 'note_on' then
			local current_chord = self:chord_id(PLAITS)

			if bit_counts[self.bits] > 2 then
				local chord = musicutil.interval_lookup[PLAITS[current_chord]]
				if chord then 
					self.chord = {}
					for k,v in pairs(chord) do
						self.chord[k] = v
					end

					self.chord.root = self.root + chord.root
					self.chord.index = current_chord
				end
			end
		end

		if track.input_type == 'chord' and data.type == 'note_on' then

			
			data.index = self.chord.index
			data.note = self.chord.root + 36
			
			return data
		elseif self.follow_method == 4 and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
			
			if self.lock and data.type == 'note_on' then
				for k,v in pairs(track.note_on) do
					self.latch_notes[k] = v
				end

				self:follow_scale(self.latch_notes)

			elseif not self.lock then
				self:follow_scale(track.note_on)
			end

			return data
		
		elseif self.follow_method == 6  and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
			
			if self.lock and data.type == 'note_on' then
				for k,v in pairs(track.note_on) do
					self.latch_notes[k] = v
				end

				self:follow_scale(self.latch_notes)

			elseif not self.lock then
				local notes = {}
				for k,v in pairs(track.note_on) do
					notes[k] = v
				end

				for k,v in pairs(self.latch_notes) do
					notes[k] = v
				end

				self:follow_scale(notes)
			end

			return data
		elseif self.follow_method == 5 and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
			local count = 0
			if self.lock and data.type == 'note_on' then
				for k,v in pairs(track.note_on) do
					self.latch_notes[k] = v
					count = count + 1
				end

				self:follow_scale(self.latch_notes)

			elseif not self.lock then
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
			end

			return data
		else

			if self.bits == 0 then
				return data
			elseif data.type == 'note_on' then

				data.note = musicutil.snap_note_to_array(data.note, self.notes) + self.root
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