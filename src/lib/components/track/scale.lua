local path_name = 'Foobar/lib/'
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local musicutil = require(path_name .. 'musicutil-extended')
local param_trace = require('Foobar/lib/utilities/param_trace')

-- CONSTANTS
local NO_FOLLOW = 0
local TRANSPOSE_MODE = 1
local SCALE_DEGREE_MODE = 2
local PENTATONIC_MODE = 3
local CHORD_MODE = 4
local MIDI_ON_MODE = 5
local MIDI_LATCH_MODE = 6
local MIDI_LOCK_MODE = 7

local ALL = musicutil.CHORDS
local PLAITS = {musicutil.interval_lookup[1],musicutil.interval_lookup[129],musicutil.interval_lookup[161],musicutil.interval_lookup[137],musicutil.interval_lookup[1161],musicutil.interval_lookup[1165],musicutil.interval_lookup[1197],musicutil.interval_lookup[661],musicutil.interval_lookup[1173],musicutil.interval_lookup[2193],musicutil.interval_lookup[145]}	



local Scale = {}
Scale.name = 'scale'
Scale.__index = Scale
setmetatable(Scale,{ __index = TrackComponent })

function Scale:new(o)
    o = o or {}
    setmetatable(o, self)
    TrackComponent.set(o,o)
    o:set(o)
	o:register_params()
    return o
end

function Scale:set(o)
	
	if not self.id then error('Scale initialized without ID') end
	
	self.root = o.root or 0
	self.bits = o.bits or 0
	self.follow = o.follow or 0
	
	self.chord = {
		index = 1,
		name = '',
		root = 0
	}

	self.follow_method = o.follow_method or 1
	self.reset_latch = false
	self.latch_notes = {}
	self.intervals = o.intervals or {}
	self.chord_set = o.chord_set or ALL
	self.lock = false
	self.lock_cc = 64

	self.event_listeners = {}
	self.current_preset = o.preset or 1

end


function Scale:register_params()
	local scale = 'scale_' .. self.id .. '_'
	params:add_group('Scale ' .. self.id, 5 ) 

	param_trace.add_with_trace('add_number', scale .. 'bits', 'Bits',0,4095,0)
	param_trace.set_action_with_trace(scale .. 'bits', function(bits)
		App.settings[scale .. 'bits'] = bits
		self:set_scale(bits)
		
		for i = 1, 3 do
			App.scale[i]:follow_scale()
		end
		self:emit('scale_changed', 'bits')
	end)
	
	param_trace.add_with_trace('add_number', scale .. 'root', 'Root',-24,24,0)
	param_trace.set_action_with_trace(scale .. 'root', function(root)
		App.settings[scale .. 'root'] = root
		self.root = root

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		self:emit('scale_changed', 'root')
	end)

	param_trace.add_with_trace('add_number', scale .. 'follow', 'Follow',0,16,0)
	param_trace.set_action_with_trace(scale .. 'follow', function(d)
		App.settings[scale .. 'follow'] = d
		self.follow = d
		
		if self.follow_method <= CHORD_MODE then
			self.follow = util.clamp(self.follow,1,3)	
		end
		if d > 0 then
			for i = 1, 3 do 
				App.scale[i]:follow_scale()
			end
		end
		
		self:emit('scale_changed', 'follow')
	end)

	param_trace.add_with_trace('add_option', scale .. 'follow_method', 'Follow Method',{'transpose','scale degree','pentatonic','chord','midi on', 'midi latch','midi lock'},1)
	param_trace.set_action_with_trace(scale .. 'follow_method', function(d)
		App.settings[scale .. 'follow_method'] = d
		self.follow_method = d

		if d <= CHORD_MODE then
			self.follow = util.clamp(self.follow,1,3)	
		end

		for i = 1, 3 do 
			App.scale[i]:follow_scale()
		end

		self:emit('scale_changed', 'follow_method')
	end)

	param_trace.add_with_trace('add_option', scale .. 'chord_set', 'Chord Set', {'All', 'Plaits', 'EO'}, 1)
	param_trace.set_action_with_trace(scale .. 'chord_set', function(d) 
		App.settings[scale .. 'chord_set'] = d
		
		if d == 1 then
			self.chord_set = musicutil.CHORDS
		elseif d == 2 then
			self.chord_set = PLAITS
		elseif d == 3 then
			self.chord_set = {1} -- Insert EO logic
		end
	end)


	local function lock_event(data)

		local scale = self
		
		if scale.follow_method > CHORD_MODE then
			
			local track = App.track[scale.follow]

			if data.ch == track.midi_in then
				
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
		
	end

end


function Scale:set_scale(bits)
	-- Store the old bits
    local old_bits = self.bits or 0
    local new_bits = bits

    -- Identify changed bits using XOR
    local changed_bits = old_bits ~ new_bits
	local changed_notes = musicutil.bits_to_intervals(changed_bits)

	-- for i, note in ipairs(changed_notes) do
	-- 	changed_notes[i] = (note + self.root) % 12
	-- end

	
	

	self.bits = bits
	self.intervals = musicutil.bits_to_intervals(bits)
	self.notes = {}

	param_trace.set('scale_'..self.id..'_bits', bits, 'scale_bits_update')

	local i = 0
	for oct=1,10 do
		-- Create a list of notes that changed in scale change
		for i=1,#self.intervals do
			self.notes[(oct - 1) * #self.intervals + i] = self.intervals[i] + (oct-1) * 12
		end
	end

	if #self.intervals > 2 then
		self.chord = self:chord_id()
	end

	-- Send interrupt request to stop changed notes
	self:emit('interrupt', changed_notes)
end

function Scale:shift_scale_to_note(n)
	n = util.clamp(n,-24,24)
	local scale = musicutil.shift_scale(self.bits, n - self.root)
	self.root = n

	self:set_scale(scale)
	param_trace.set('scale_'..self.id..'_root', n, 'scale_root_note_set')
end


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



function Scale:chord_id(bits)
    local best = {index = nil, score = -1}
	bits = bits or self.bits
	
    bits = bits & 0xFFF  -- Ensure bits are in 12-bit range
	local bits_count = bit_counts[bits]
	
	
    for i = 1, #self.chord_set do
		
        local set_bits = self.chord_set[i].bits & 0xFFF
        local set_bits_count = bit_counts[set_bits]
        local matching_bits = bits & set_bits
        local matching_bits_count = bit_counts[matching_bits]

        -- Compute the Dice coefficient
        local score = (2 * matching_bits_count) / (bits_count + set_bits_count)

        if best.score and score > best.score or not best.score then
            best = {index = i, score = score}
        end

		-- tab.print(self.intervals)
    end

    if best.index then
		local chord = {}
		for k,v in pairs(self.chord_set[best.index]) do
			chord[k] = v
		end
		
		chord.index = best.index

        return chord
    end
end


function Scale:follow_scale(notes)
	local scale = 'scale_' .. self.id .. '_'
	
	if self.follow > 0 then
		local other = App.scale[self.follow]

		if other.lock and other.follow > 0 and not  App.scale[other.follow].lock then
			other = App.scale[other.follow]
		end
		
		if self.follow_method == TRANSPOSE_MODE and not self.lock then
			-- Transpose
			self.root = other.root
			param_trace.set(scale .. 'root', other.root, 'scale_follow_transpose')
		elseif self.follow_method == SCALE_DEGREE_MODE and not self.lock then
			-- App.scale Degree
			self:shift_scale_to_note(other.root)
			param_trace.set(scale .. 'root', other.root, 'scale_follow_degree')
		elseif self.follow_method == PENTATONIC_MODE and not self.lock then
			-- Pentatonic
			local major = musicutil.intervals_to_bits({0,4})
			local minor = musicutil.intervals_to_bits({0,3})

			if other.bits & major == major then
				self:set_scale(661)
				self.root = other.root
				param_trace.set(scale .. 'root', other.root, 'scale_follow_pentatonic_major') -- We need to keep the params silent to avoid a loop
			elseif other.bits & minor == minor then
				self:set_scale(1193)
				self.root = other.root
				param_trace.set(scale .. 'root', other.root, 'scale_follow_pentatonic_minor')
			else
				self:set_scale(1)
				self.root = other.root
				param_trace.set(scale .. 'root', other.root, 'scale_follow_pentatonic_other')
			end
		elseif self.follow_method == CHORD_MODE and not self.lock then
				if #other.intervals > 2 then
					self.root = other.root
					self.chord = self:chord_id(other.bits)
					self:set_scale(self.chord.bits)
									self.root = other.root + self.chord.root
				param_trace.set(scale .. 'root', other.root + self.chord.root, 'scale_follow_chord')
				end
		elseif self.follow_method > CHORD_MODE and notes then
			-- MIDI controlled
			local n = {}
			local min = nil

			for note in pairs(notes) do
				if not min or note < min then
					min = note
				end
				n[#n + 1] = note
			end

			for i= 1, #n do
				n[i] = (n[i] - min) % 12
			end
			
			local s = musicutil.intervals_to_bits(n)
			if s > 0 then
				self.root = min % 12
			end
			param_trace.set(scale .. 'root', self.root, 'scale_follow_midi')
			
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

function Scale:quantize_note(data)


	if self.bits == 0 then
		data.new_note = data.note + self.root
		return data
	elseif #self.notes > 0 then
		data.new_note = musicutil.snap_note_to_array(data.note, self.notes) + self.root
		return data
	else
		print(#self.notes)
		print(self.bits)
	end
end

function Scale:midi_event(data, track)    
	if data.note then

		if track.input_type == 'chord' and data.type == 'note_on' then

			
			data.index = self.chord.index
			data.new_note = self.root + 36
			
			return data
		elseif self.follow_method == MIDI_ON_MODE and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
			
			if self.lock and data.type == 'note_on' then
				for k,v in pairs(track.note_on) do
					self.latch_notes[k] = v
				end

				self:follow_scale(self.latch_notes)

			elseif not self.lock then
				self:follow_scale(track.note_on)
			end

			return data
		
		elseif self.follow_method == MIDI_LOCK_MODE  and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
			
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
		elseif self.follow_method == MIDI_LATCH_MODE and (data.type == 'note_on' or data.type == 'note_off') and track.id == self.follow then
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
			return self:quantize_note(data)
		end
		
  	else
		
		  return data
	end
end

return Scale