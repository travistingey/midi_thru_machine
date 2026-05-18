local path_name = 'Foobar/lib/'
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local musicutil = require(path_name .. 'musicutil-extended')
local Registry = require('Foobar/lib/utilities/registry')

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

-- Hoisted constants for follow_scale's pentatonic detection path. These were
-- previously re-computed via intervals_to_bits on every follow_scale call.
local PENTATONIC_MAJOR_TRIAD_BITS = musicutil.intervals_to_bits({ 0, 4 })
local PENTATONIC_MINOR_TRIAD_BITS = musicutil.intervals_to_bits({ 0, 3 })
local PENTATONIC_MAJOR_BITS = 661
local PENTATONIC_MINOR_BITS = 1193
local PENTATONIC_FALLBACK_BITS = 1
local PLAITS = {
	musicutil.interval_lookup[1],
	musicutil.interval_lookup[129],
	musicutil.interval_lookup[161],
	musicutil.interval_lookup[137],
	musicutil.interval_lookup[1161],
	musicutil.interval_lookup[1165],
	musicutil.interval_lookup[1197],
	musicutil.interval_lookup[661],
	musicutil.interval_lookup[1173],
	musicutil.interval_lookup[2193],
	musicutil.interval_lookup[145],
}

local Scale = {}
Scale.name = 'scale'
Scale.__index = Scale
setmetatable(Scale, { __index = TrackComponent })

function Scale:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
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
		root = 0,
	}

	self.follow_method = o.follow_method or 1
	self.reset_latch = false
	self.latch_notes = {}
	self.intervals = o.intervals or {}
	self.chord_set = o.chord_set or ALL
	self.lock = false
	self.lock_cc = 64

	-- Reusable scratch buffers (avoid per-event table allocations on the
	-- MIDI hot path). These are owned by the scale and never shared.
	self._lock_merge_buf = {} -- merged track.note_on + latch_notes for MIDI_LOCK
	self.notes = {} -- materialized note ladder, rebuilt in place by set_scale

	-- bits → chord_set index map. Rebuilt whenever chord_set changes so
	-- chord_id can short-circuit the linear scan in the common exact-match
	-- case (musicutil.CHORDS has hundreds of entries; the fast-path was
	-- still O(n) before this cache).
	self._chord_set_index = self:_build_chord_set_index(self.chord_set)

	self.event_listeners = {}
	self.current_preset = o.preset or 1
end

-- Build a bits → index lookup for chord_set so chord_id can resolve an exact
-- match in O(1). Only the first index for any given bits value is recorded
-- (matches the original linear-scan behavior, which returned the first match).
function Scale:_build_chord_set_index(chord_set)
	local index = {}
	if not chord_set then return index end
	for i = 1, #chord_set do
		local entry = chord_set[i]
		if entry and entry.bits then
			local masked = entry.bits & 0xFFF
			if index[masked] == nil then index[masked] = i end
		end
	end
	return index
end

function Scale:register_params()
	local scale = 'scale_' .. self.id .. '_'
	params:add_group('Scale ' .. self.id, 5)

	Registry.add('add_number', scale .. 'bits', 'Bits', 0, 4095, 0)
	Registry.set_action(scale .. 'bits', function(bits)
		App.settings[scale .. 'bits'] = bits
		self:set_scale(bits)

		for i = 1, 3 do
			App.scale[i]:follow_scale()
		end
		self:emit('scale_changed', 'bits')
	end)

	Registry.add('add_number', scale .. 'root', 'Root', -24, 24, 0)
	Registry.set_action(scale .. 'root', function(root)
		App.settings[scale .. 'root'] = root
		self.root = root

		for i = 1, 3 do
			App.scale[i]:follow_scale()
		end

		self:emit('scale_changed', 'root')
	end)

	Registry.add('add_number', scale .. 'follow', 'Follow', 0, 16, 0, function(param)
		local v = param:get() or 0
		if v == 0 then return 'off' end
		local method = self.follow_method or 0

		if method > CHORD_MODE then
			return 'Track ' .. v
		else
			return 'Scale ' .. v
		end
	end)
	Registry.set_action(scale .. 'follow', function(d)
		App.settings[scale .. 'follow'] = d
		self.follow = d

		if d > 0 and self.follow_method <= CHORD_MODE then self.follow = util.clamp(self.follow, 1, 3) end

		if self.follow > 0 then
			for i = 1, 3 do
				App.scale[i]:follow_scale()
			end
		end

		self:emit('scale_changed', 'follow')
	end)

	Registry.add('add_option', scale .. 'follow_method', 'Follow Method', { 'transpose', 'scale degree', 'pentatonic', 'chord', 'midi on', 'midi latch', 'midi lock' }, 1)
	Registry.set_action(scale .. 'follow_method', function(d)
		App.settings[scale .. 'follow_method'] = d
		self.follow_method = d

		if d <= CHORD_MODE and self.follow > 0 then self.follow = util.clamp(self.follow, 1, 3) end

		for i = 1, 3 do
			App.scale[i]:follow_scale()
		end

		self:emit('scale_changed', 'follow_method')
	end)

	Registry.add('add_option', scale .. 'chord_set', 'Chord Set', { 'All', 'Plaits', 'Presets' }, 1)
	Registry.set_action(scale .. 'chord_set', function(d)
		App.settings[scale .. 'chord_set'] = d

		if d == 1 then
			self.chord_set = musicutil.CHORDS
			self._chord_set_index = self:_build_chord_set_index(self.chord_set)
		elseif d == 2 then
			self.chord_set = PLAITS
			self._chord_set_index = self:_build_chord_set_index(self.chord_set)
		elseif d == 3 then
			-- Build a chord set from the current preset bank for this scale
			local preset_bank = App.preset or {}
			local collected = {}

			for pid = 1, #preset_bank do
				local root_key = 'scale_' .. self.id .. '_root'
				local bits_key = 'scale_' .. self.id .. '_bits'
				local root = preset_bank[pid][root_key]
				local bits = preset_bank[pid][bits_key]

				if root ~= nil and bits ~= nil then
					local info = musicutil.interval_lookup[bits]
					if info and info.bits then
						local chord = {
							name = info.name or ('Preset ' .. pid),
							intervals = info.intervals or musicutil.bits_to_intervals(info.bits),
							bits = info.bits,
							root = info.root or 0,
						}
						table.insert(collected, chord)
					else
						-- Fallback: derive from bits directly
						table.insert(collected, {
							name = 'Preset ' .. pid,
							intervals = musicutil.bits_to_intervals(bits),
							bits = bits,
							root = 0,
						})
					end
				end
			end

			if #collected > 0 then
				self.chord_set = collected
			else
				-- Fallback to All if nothing was found
				self.chord_set = musicutil.CHORDS
				Registry.set(scale .. 'chord_set', 1, 'chord_set_fallback')
			end
			self._chord_set_index = self:_build_chord_set_index(self.chord_set)
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

					for k, v in pairs(track.note_on) do
						scale.latch_notes[k] = v
					end

					scale:follow_scale(scale.latch_notes)
				end
			end
		end
	end
end

function Scale:set_scale(bits)
	local old_bits = self.bits or 0
	local new_bits = bits

	-- Early exit if bits haven't changed and notes are already built.
	-- This is the common case during MIDI following — a clip retrigger or a
	-- repeated note that happens to map to the same chord shouldn't pay any
	-- rebuild cost.
	if old_bits == new_bits and self.notes and #self.notes > 0 then return end

	local changed_bits = old_bits ~ new_bits
	local changed_notes = musicutil.bits_to_intervals(changed_bits)

	self.bits = bits
	self.intervals = musicutil.bits_to_intervals(bits)

	-- Rebuild the materialized note ladder IN PLACE rather than allocating a
	-- fresh table. This is on the hot path for live following and used to
	-- churn ~70 entries of garbage per scale change. We overwrite up through
	-- the new size and then nil-clear any trailing entries left over from a
	-- previously-larger scale so #self.notes returns the correct length.
	local notes = self.notes
	local intervals = self.intervals
	local interval_count = #intervals
	local new_size = 10 * interval_count
	local idx = 1
	for oct = 1, 10 do
		for i = 1, interval_count do
			notes[idx] = intervals[i] + (oct - 1) * 12
			idx = idx + 1
		end
	end
	-- Trim leftovers from a previous larger scale.
	local prev_size = self._notes_size or 0
	if prev_size > new_size then
		for i = new_size + 1, prev_size do notes[i] = nil end
	end
	self._notes_size = new_size

	Registry.set('scale_' .. self.id .. '_bits', bits, 'scale_bits_update')

	if interval_count > 2 then self.chord = self:chord_id() end

	-- Send interrupt request to stop changed notes
	self:emit('interrupt', changed_notes)
end

function Scale:shift_scale_to_note(n)
	n = util.clamp(n, -24, 24)
	local scale = musicutil.shift_scale(self.bits, n - self.root)
	self.root = n

	self:set_scale(scale)
	Registry.set('scale_' .. self.id .. '_root', n, 'scale_root_note_set')
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
	bits = bits or self.bits
	bits = bits & 0xFFF -- Ensure bits are in 12-bit range

	-- Fast path: exact match against the global interval_lookup table.
	-- The chord_set index resolves the index in self.chord_set in O(1),
	-- replacing what used to be a linear scan over potentially hundreds of
	-- chord entries on every set_scale call.
	local exact_match = musicutil.interval_lookup[bits]
	if exact_match then
		local chord = {}
		for k, v in pairs(exact_match) do chord[k] = v end
		local idx = self._chord_set_index and self._chord_set_index[bits] or nil
		-- If the exact match isn't in the current chord_set (e.g. PLAITS
		-- subset), fall back to index 1 to match the legacy behavior.
		chord.index = idx or 1
		return chord
	end

	-- Fallback to similarity search if no exact match found
	-- This is the expensive path that we're trying to avoid
	local best = { index = nil, score = -1 }
	local bits_count = bit_counts[bits]

	for i = 1, #self.chord_set do
		local set_bits = self.chord_set[i].bits & 0xFFF
		local set_bits_count = bit_counts[set_bits]
		local matching_bits = bits & set_bits
		local matching_bits_count = bit_counts[matching_bits]

		-- Compute the Dice coefficient
		local score = (2 * matching_bits_count) / (bits_count + set_bits_count)

		if best.score and score > best.score or not best.score then best = { index = i, score = score } end

		-- tab.print(self.intervals)
	end

	if best.index then
		local chord = {}
		for k, v in pairs(self.chord_set[best.index]) do
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

		if other.lock and other.follow > 0 and not App.scale[other.follow].lock then other = App.scale[other.follow] end

		if self.follow_method == TRANSPOSE_MODE and not self.lock then
			-- Transpose
			self.root = other.root
			Registry.set(scale .. 'root', other.root, 'scale_follow_transpose')
		elseif self.follow_method == SCALE_DEGREE_MODE and not self.lock then
			-- App.scale Degree
			self:shift_scale_to_note(other.root)
			Registry.set(scale .. 'root', other.root, 'scale_follow_degree')
		elseif self.follow_method == PENTATONIC_MODE and not self.lock then
			if other.bits & PENTATONIC_MAJOR_TRIAD_BITS == PENTATONIC_MAJOR_TRIAD_BITS then
				self:set_scale(PENTATONIC_MAJOR_BITS)
				self.root = other.root
				Registry.set(scale .. 'root', other.root, 'scale_follow_pentatonic_major')
			elseif other.bits & PENTATONIC_MINOR_TRIAD_BITS == PENTATONIC_MINOR_TRIAD_BITS then
				self:set_scale(PENTATONIC_MINOR_BITS)
				self.root = other.root
				Registry.set(scale .. 'root', other.root, 'scale_follow_pentatonic_minor')
			else
				self:set_scale(PENTATONIC_FALLBACK_BITS)
				self.root = other.root
				Registry.set(scale .. 'root', other.root, 'scale_follow_pentatonic_other')
			end
		elseif self.follow_method == CHORD_MODE and not self.lock then
			if #other.intervals > 2 then
				self.root = other.root
				self.chord = self:chord_id(other.bits)
				self:set_scale(self.chord.bits)
				self.root = other.root + self.chord.root
				Registry.set(scale .. 'root', other.root + self.chord.root, 'scale_follow_chord')
			end
		elseif self.follow_method > CHORD_MODE and notes then
			-- MIDI-driven follow. Reuse a per-scale scratch buffer for the
			-- normalized interval list instead of allocating per call.
			local n = self._follow_buf
			if not n then
				n = {}
				self._follow_buf = n
			end
			local count = 0
			local min = nil

			for note in pairs(notes) do
				if not min or note < min then min = note end
				count = count + 1
				n[count] = note
			end
			-- Trim leftovers from a previous larger held set so #n is correct
			-- when intervals_to_bits reads the array length.
			local prev = self._follow_buf_size or 0
			if prev > count then
				for i = count + 1, prev do n[i] = nil end
			end
			self._follow_buf_size = count

			-- Note: when count == 0 we still call intervals_to_bits (returning 0)
			-- and set_scale(0). This is the intended "no scale" state for
			-- MIDI_ON when all keys are released, and quantize_note has a
			-- bits == 0 fast path for it.
			for i = 1, count do n[i] = (n[i] - min) % 12 end

			local s = musicutil.intervals_to_bits(n)
			if s > 0 then self.root = min % 12 end
			Registry.set(scale .. 'root', self.root, 'scale_follow_midi')

			self:set_scale(s)
		end
	end
end

function Scale:transport_event(data, track)
	if data.type == 'start' then self.reset_latch = false end

	return data
end

function Scale:quantize_note(data)
	-- If note_off already has new_note from the original note_on, preserve it
	-- This ensures note_off matches the quantized note that was actually sent
	if data.type == 'note_off' and data.new_note then return data end

	if self.bits == 0 then
		data.new_note = data.note + self.root
		return data
	elseif #self.notes > 0 then
		data.new_note = musicutil.snap_note_to_array(data.note, self.notes) + self.root
		return data
	end
end

-- Process a MIDI event for this scale.
--
-- Two responsibilities, split cleanly:
--   1. FOLLOW STATE UPDATES — only when the event came from LIVE INPUT on the
--      configured follow track. Clip-played notes (data.buffer_sent set) are
--      explicitly excluded so they can't pollute latch state. This is what
--      lets a clip play on the follow track while the user's keyboard
--      continues to drive scale follow without "stumbling".
--   2. NOTE QUANTIZATION — applied to non-follow-track notes (or any note
--      that bypassed the follow logic). The follow track's own notes are
--      passed through unchanged so the keyboard plays its own melody.
--
-- The follow gate is checked once at the top instead of repeated in three
-- per-mode branches; this also makes the live-vs-clip discriminator obvious.
function Scale:midi_event(data, track)
	if not data.note then return data end

	if track.input_type == 'chord' and data.type == 'note_on' then
		data.index = self.chord.index
		data.new_note = self.root + 36
		return data
	end

	-- Follow-track gate: this event might affect scale follow state IF...
	--   - this scale's follow_method is one of the MIDI-driven modes,
	--   - the event is a note on/off,
	--   - the event came from the configured follow track,
	--   - AND the event came from LIVE input (not clip playback).
	-- Anything that fails this gate falls through to quantize_note below,
	-- which is the correct semantic for non-follow tracks AND for clip notes
	-- on the follow track (we still want them to be reharmonized).
	local is_follow_track = (track.id == self.follow)
	local is_note_event = (data.type == 'note_on' or data.type == 'note_off')
	local is_live_input = not data.buffer_sent

	if is_follow_track and is_note_event and is_live_input and self.follow_method >= MIDI_ON_MODE then
		if self.follow_method == MIDI_ON_MODE then
			if self.lock and data.type == 'note_on' then
				for k, v in pairs(track.note_on) do self.latch_notes[k] = v end
				self:follow_scale(self.latch_notes)
			elseif not self.lock then
				self:follow_scale(track.note_on)
			end
			return data
		elseif self.follow_method == MIDI_LOCK_MODE then
			if self.lock and data.type == 'note_on' then
				for k, v in pairs(track.note_on) do self.latch_notes[k] = v end
				self:follow_scale(self.latch_notes)
			elseif not self.lock then
				-- Reuse a per-scale merge buffer instead of allocating a fresh
				-- table on every event. The buffer is built fresh each call
				-- from track.note_on + latch_notes; trailing entries from a
				-- previous larger merge are nil-cleared to keep iteration
				-- accurate when latch_notes shrinks.
				local merged = self._lock_merge_buf
				for k in pairs(merged) do merged[k] = nil end
				for k, v in pairs(track.note_on) do merged[k] = v end
				for k, v in pairs(self.latch_notes) do merged[k] = v end
				self:follow_scale(merged)
			end
			return data
		elseif self.follow_method == MIDI_LATCH_MODE then
			if self.lock and data.type == 'note_on' then
				for k, v in pairs(track.note_on) do self.latch_notes[k] = v end
				self:follow_scale(self.latch_notes)
			elseif not self.lock then
				if data.type == 'note_off' then
					-- Use next() instead of counting via a full pairs() loop;
					-- we only need to know whether ANY live note is held.
					if next(track.note_on) == nil then self.reset_latch = true end
				else
					if self.reset_latch then
						-- Reuse the existing latch_notes table by clearing it
						-- in place rather than allocating a new table.
						for k in pairs(self.latch_notes) do self.latch_notes[k] = nil end
						self.reset_latch = false
					end
					-- Skip follow_scale when the note is already latched: the
					-- note set hasn't changed, so the resulting bits won't
					-- either, and set_scale would early-exit anyway after
					-- doing all the prep work in follow_scale. Save the trip.
					if self.latch_notes[data.note] == nil then
						self.latch_notes[data.note] = data
						self:follow_scale(self.latch_notes)
					end
				end
			end
			return data
		end
	end

	return self:quantize_note(data)
end

return Scale
