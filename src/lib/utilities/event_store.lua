-- ============================================================================
-- SEQUENTIAL INDEX EVENT STORAGE
-- Optimized for: insert, delete, range queries on sparse tick-based events
--
-- All ticks are 1-based (Lua convention):
--   - First clock event = tick 1
--   - Events stored at tick positions within buffer boundaries
--
-- Events at each tick are stored as arrays (multiple events per tick supported)
-- ============================================================================

local EventStore = {}
EventStore.__index = EventStore

function EventStore.new()
	local self = setmetatable({}, EventStore)
	self.events = {} -- sparse table: events[tick] = {event1, event2, ...}
	self.ticks = {} -- sorted sequential array of tick indices
	return self
end

-- ============================================================================
-- BINARY SEARCH UTILITIES
-- ============================================================================

-- Find exact match or insertion position
-- Returns: index (if found), insert_pos (for insertion)
function EventStore:_binary_search(tick)
	local ticks = self.ticks
	local len = #ticks

	if len == 0 then return nil, 1 end -- empty, insert at position 1

	local low, high = 1, len

	while low <= high do
		local mid = math.floor((low + high) / 2)
		local mid_val = ticks[mid]

		if mid_val == tick then
			return mid, mid -- exact match
		elseif mid_val < tick then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	return nil, low -- not found, return insert position
end

-- Find first tick >= target (for range start)
function EventStore:_binary_search_ge(tick)
	local ticks = self.ticks
	local len = #ticks

	if len == 0 or ticks[len] < tick then return nil end -- no ticks >= target

	local low, high = 1, len
	local result = nil

	while low <= high do
		local mid = math.floor((low + high) / 2)

		if ticks[mid] >= tick then
			result = mid
			high = mid - 1 -- keep searching left
		else
			low = mid + 1
		end
	end

	return result
end

-- ============================================================================
-- INSERT
-- Time: O(log n) search + O(n) worst-case insert (if not exists)
-- Time: O(1) if tick already exists (append to existing array)
-- ============================================================================

-- Insert a single event at a tick
-- @param tick number The tick position (1-based)
-- @param event table The event data to store
function EventStore:insert(tick, event)
	local idx, insert_pos = self:_binary_search(tick)

	if idx then
		-- Tick already exists - append to event array
		table.insert(self.events[tick], event)
	else
		-- New tick - insert into sorted position
		table.insert(self.ticks, insert_pos, tick)
		self.events[tick] = { event }
	end
end

-- Insert multiple events at a tick (replaces existing events)
-- @param tick number The tick position (1-based)
-- @param events table Array of events to store
function EventStore:set(tick, events)
	local idx, insert_pos = self:_binary_search(tick)

	if idx then
		-- Tick already exists - replace event array
		self.events[tick] = events
	else
		-- New tick - insert into sorted position
		table.insert(self.ticks, insert_pos, tick)
		self.events[tick] = events
	end
end

-- Batch insert (more efficient for multiple events)
-- @param events_array table Array of {tick=number, event=table} or {tick=number, events=table[]}
function EventStore:batch_insert(events_array)
	-- Sort input by tick
	table.sort(events_array, function(a, b) return a.tick < b.tick end)

	-- Merge sorted arrays
	local new_ticks = {}
	local i, j = 1, 1
	local old_ticks = self.ticks

	while i <= #old_ticks or j <= #events_array do
		if i > #old_ticks then
			-- Append remaining new events
			local ev = events_array[j]
			table.insert(new_ticks, ev.tick)
			if ev.events then
				self.events[ev.tick] = ev.events
			else
				self.events[ev.tick] = { ev.event }
			end
			j = j + 1
		elseif j > #events_array then
			-- Append remaining old ticks
			table.insert(new_ticks, old_ticks[i])
			i = i + 1
		else
			local old_tick = old_ticks[i]
			local new_event = events_array[j]

			if old_tick < new_event.tick then
				table.insert(new_ticks, old_tick)
				i = i + 1
			elseif old_tick > new_event.tick then
				table.insert(new_ticks, new_event.tick)
				if new_event.events then
					self.events[new_event.tick] = new_event.events
				else
					self.events[new_event.tick] = { new_event.event }
				end
				j = j + 1
			else
				-- Same tick - merge or replace
				table.insert(new_ticks, old_tick)
				if new_event.events then
					self.events[old_tick] = new_event.events
				else
					table.insert(self.events[old_tick], new_event.event)
				end
				i = i + 1
				j = j + 1
			end
		end
	end

	self.ticks = new_ticks
end

-- ============================================================================
-- DELETE
-- Time: O(log n) search + O(n) worst-case removal
-- ============================================================================

-- Delete all events at a specific tick
-- @param tick number The tick position
-- @return boolean True if tick existed and was deleted
function EventStore:delete(tick)
	local idx = self:_binary_search(tick)

	if not idx then return false end -- tick doesn't exist

	-- Remove from both structures
	table.remove(self.ticks, idx)
	self.events[tick] = nil

	return true
end

-- Delete range [start_tick, end_tick) (end_tick exclusive)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return number Count of ticks deleted
function EventStore:delete_range(start_tick, end_tick)
	local start_idx = self:_binary_search_ge(start_tick)

	if not start_idx then return 0 end -- no events in range

	local count = 0
	local ticks = self.ticks

	-- Collect indices to remove (backwards to avoid index shifting issues)
	local to_remove = {}

	for i = start_idx, #ticks do
		local tick = ticks[i]
		if tick >= end_tick then break end
		table.insert(to_remove, 1, i) -- insert at front for reverse order
		self.events[tick] = nil
		count = count + 1
	end

	-- Remove from ticks array (in reverse order)
	for _, idx in ipairs(to_remove) do
		table.remove(ticks, idx)
	end

	return count
end

-- Delete range [start_tick, end_tick] (both inclusive)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (inclusive)
-- @return number Count of ticks deleted
function EventStore:delete_range_inclusive(start_tick, end_tick) return self:delete_range(start_tick, end_tick + 1) end

-- ============================================================================
-- RANGE QUERIES
-- Time: O(log n) search + O(m) where m = events in range
-- ============================================================================

-- Get shallow copy of events in range [start_tick, end_tick)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return table Sparse table of tick -> events
function EventStore:get_range(start_tick, end_tick)
	local start_idx = self:_binary_search_ge(start_tick)

	if not start_idx then return {} end -- no events >= start_tick

	local result = {}
	local ticks = self.ticks

	for i = start_idx, #ticks do
		local tick = ticks[i]
		if tick >= end_tick then break end
		result[tick] = self.events[tick]
	end

	return result
end

-- Get events as sorted array (useful for iteration)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return table Array of {tick=number, events=table}
function EventStore:get_range_array(start_tick, end_tick)
	local start_idx = self:_binary_search_ge(start_tick)

	if not start_idx then return {} end

	local result = {}
	local ticks = self.ticks

	for i = start_idx, #ticks do
		local tick = ticks[i]
		if tick >= end_tick then break end
		table.insert(result, { tick = tick, events = self.events[tick] })
	end

	return result
end

-- Iterator for range (memory efficient - no copy)
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @return function Iterator returning tick, events
function EventStore:iter_range(start_tick, end_tick)
	local start_idx = self:_binary_search_ge(start_tick)

	if not start_idx then
		return function() return nil end -- empty iterator
	end

	local ticks = self.ticks
	local i = start_idx - 1
	local len = #ticks

	return function()
		i = i + 1
		if i > len then return nil end

		local tick = ticks[i]
		if tick >= end_tick then return nil end

		return tick, self.events[tick]
	end
end

-- ============================================================================
-- UTILITY METHODS
-- ============================================================================

-- Get events at specific tick
-- @param tick number The tick position
-- @return table|nil Array of events or nil if no events
function EventStore:get(tick) return self.events[tick] end

-- Check if tick has events
-- @param tick number The tick position
-- @return boolean True if events exist at tick
function EventStore:has(tick) return self.events[tick] ~= nil end

-- Get total count of ticks with events
-- @return number Count of ticks
function EventStore:count() return #self.ticks end

-- Get total count of events across all ticks
-- @return number Total event count
function EventStore:event_count()
	local count = 0
	for _, events in pairs(self.events) do
		count = count + #events
	end
	return count
end

-- Get all ticks (copy)
-- @return table Array of tick positions
function EventStore:get_all_ticks()
	local result = {}
	for i, tick in ipairs(self.ticks) do
		result[i] = tick
	end
	return result
end

-- Clear all events
function EventStore:clear()
	self.events = {}
	self.ticks = {}
end

-- Get earliest tick
-- @return number|nil First tick or nil if empty
function EventStore:first_tick() return self.ticks[1] end

-- Get latest tick
-- @return number|nil Last tick or nil if empty
function EventStore:last_tick() return self.ticks[#self.ticks] end

-- ============================================================================
-- COPY OPERATIONS
-- ============================================================================

-- Create a shallow copy of the store
-- @return EventStore New store with same events (shared references)
function EventStore:shallow_copy()
	local copy = EventStore.new()
	for i, tick in ipairs(self.ticks) do
		copy.ticks[i] = tick
		copy.events[tick] = self.events[tick] -- shallow: same event references
	end
	return copy
end

-- Create a shallow copy of a range
-- @param start_tick number Start of range (inclusive)
-- @param end_tick number End of range (exclusive)
-- @param tick_offset number Optional offset to apply to ticks in copy (default 0)
-- @return EventStore New store with events from range
function EventStore:copy_range(start_tick, end_tick, tick_offset)
	tick_offset = tick_offset or 0
	local copy = EventStore.new()

	local start_idx = self:_binary_search_ge(start_tick)
	if not start_idx then return copy end

	for i = start_idx, #self.ticks do
		local tick = self.ticks[i]
		if tick >= end_tick then break end

		local new_tick = tick + tick_offset
		table.insert(copy.ticks, new_tick)
		copy.events[new_tick] = self.events[tick] -- shallow copy
	end

	return copy
end

-- ============================================================================
-- SPARSE TABLE COMPATIBILITY
-- For backward compatibility with existing buffer[tick] = events usage
-- ============================================================================

-- Import from a sparse table (buffer[tick] = events)
-- @param sparse_table table Sparse table with tick keys
function EventStore:from_sparse_table(sparse_table)
	self:clear()

	-- Collect all ticks
	local ticks = {}
	for tick, _ in pairs(sparse_table) do
		table.insert(ticks, tick)
	end

	-- Sort ticks
	table.sort(ticks)

	-- Build index
	self.ticks = ticks
	for _, tick in ipairs(ticks) do
		self.events[tick] = sparse_table[tick]
	end
end

-- Export to a sparse table (for backward compatibility)
-- @return table Sparse table with tick keys
function EventStore:to_sparse_table()
	local result = {}
	for tick, events in pairs(self.events) do
		result[tick] = events
	end
	return result
end

-- ============================================================================
-- BAR-BASED HELPERS (for convenience)
-- ============================================================================

-- Get events in bar range
-- @param bar_start number Start bar (0-based)
-- @param bar_end number End bar (exclusive)
-- @param ppqn number Pulses per quarter note (default App.ppqn or 96)
-- @return table Sparse table of tick -> events
function EventStore:get_bar_range(bar_start, bar_end, ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	local ticks_per_bar = ppqn * 4
	local start_tick = bar_start * ticks_per_bar + 1 -- 1-based
	local end_tick = bar_end * ticks_per_bar + 1
	return self:get_range(start_tick, end_tick)
end

-- Delete events in bar range
-- @param bar_start number Start bar (0-based)
-- @param bar_end number End bar (exclusive)
-- @param ppqn number Pulses per quarter note (default App.ppqn or 96)
-- @return number Count of ticks deleted
function EventStore:delete_bar_range(bar_start, bar_end, ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	local ticks_per_bar = ppqn * 4
	local start_tick = bar_start * ticks_per_bar + 1 -- 1-based
	local end_tick = bar_end * ticks_per_bar + 1
	return self:delete_range(start_tick, end_tick)
end

-- ============================================================================
-- EDITING OPERATIONS
-- For clip editing functionality (insert, delete, shift)
-- ============================================================================

-- Shift all events at or after a tick by an offset
-- Positive offset moves events forward (later in time)
-- Negative offset moves events backward (earlier in time)
-- @param from_tick number Shift events at or after this tick
-- @param offset number Amount to shift (positive = forward, negative = backward)
-- @return number Count of events shifted
function EventStore:shift_events(from_tick, offset)
	if offset == 0 then return 0 end

	local start_idx = self:_binary_search_ge(from_tick)
	if not start_idx then return 0 end

	local count = 0

	-- Build new events table and ticks array
	local new_events = {}
	local new_ticks = {}

	-- Copy events before from_tick unchanged
	for i = 1, start_idx - 1 do
		local tick = self.ticks[i]
		table.insert(new_ticks, tick)
		new_events[tick] = self.events[tick]
	end

	-- Shift events at or after from_tick
	for i = start_idx, #self.ticks do
		local old_tick = self.ticks[i]
		local new_tick = old_tick + offset

		-- Only include if new tick is valid (>= 1)
		if new_tick >= 1 then
			table.insert(new_ticks, new_tick)
			new_events[new_tick] = self.events[old_tick]
			count = count + 1
		end
	end

	self.events = new_events
	self.ticks = new_ticks

	return count
end

-- Insert empty time at a position (shift events forward)
-- Events at or after insert_tick are shifted by duration
-- @param insert_tick number Position to insert time
-- @param duration number Amount of time to insert (in ticks)
-- @return number Count of events shifted
function EventStore:insert_time(insert_tick, duration)
	if duration <= 0 then return 0 end
	return self:shift_events(insert_tick, duration)
end

-- Delete time range and shift remaining events backward
-- Events in the range are deleted, events after are shifted back
-- @param start_tick number Start of range to delete (inclusive)
-- @param end_tick number End of range to delete (exclusive)
-- @return number Count of events deleted
function EventStore:delete_time(start_tick, end_tick)
	local duration = end_tick - start_tick
	if duration <= 0 then return 0 end

	-- First delete the range
	local deleted = self:delete_range(start_tick, end_tick)

	-- Then shift remaining events backward
	self:shift_events(end_tick, -duration)

	return deleted
end

-- Quantize events to a grid
-- @param grid_size number Grid size in ticks (e.g., 24 for 1/16 note at 96 ppqn)
-- @param start_tick number Optional start of range (default: all events)
-- @param end_tick number Optional end of range (exclusive)
-- @return number Count of events moved
function EventStore:quantize(grid_size, start_tick, end_tick)
	if grid_size <= 0 then return 0 end

	start_tick = start_tick or 1
	end_tick = end_tick or (self:last_tick() and self:last_tick() + 1) or 1

	local start_idx = self:_binary_search_ge(start_tick)
	if not start_idx then return 0 end

	local count = 0
	local moves = {} -- {old_tick, new_tick, events}

	-- Collect events to move
	for i = start_idx, #self.ticks do
		local tick = self.ticks[i]
		if tick >= end_tick then break end

		-- Quantize to nearest grid position
		local relative = tick - 1 -- 0-based for math
		local quantized = math.floor((relative + grid_size / 2) / grid_size) * grid_size + 1

		if quantized ~= tick then
			table.insert(moves, { old_tick = tick, new_tick = quantized, events = self.events[tick] })
			count = count + 1
		end
	end

	-- Apply moves (delete old, insert new)
	for _, move in ipairs(moves) do
		self.events[move.old_tick] = nil
		-- Remove from ticks array (will rebuild)
	end

	-- Rebuild ticks array and merge quantized events
	local new_ticks = {}
	local seen = {}

	for tick, events in pairs(self.events) do
		if not seen[tick] then
			table.insert(new_ticks, tick)
			seen[tick] = true
		end
	end

	-- Add quantized events (merge if tick already exists)
	for _, move in ipairs(moves) do
		if self.events[move.new_tick] then
			-- Merge events at same tick
			for _, event in ipairs(move.events) do
				table.insert(self.events[move.new_tick], event)
			end
		else
			self.events[move.new_tick] = move.events
			if not seen[move.new_tick] then
				table.insert(new_ticks, move.new_tick)
				seen[move.new_tick] = true
			end
		end
	end

	table.sort(new_ticks)
	self.ticks = new_ticks

	return count
end

-- Transpose MIDI note events by semitones
-- @param semitones number Number of semitones to transpose (positive = up, negative = down)
-- @param start_tick number Optional start of range (default: all events)
-- @param end_tick number Optional end of range (exclusive)
-- @return number Count of events transposed
function EventStore:transpose(semitones, start_tick, end_tick)
	if semitones == 0 then return 0 end

	start_tick = start_tick or 1
	end_tick = end_tick or (self:last_tick() and self:last_tick() + 1) or 1

	local count = 0

	for tick, events in self:iter_range(start_tick, end_tick) do
		for _, event in ipairs(events) do
			-- Check if this is a note event (has note field)
			if event.note then
				local new_note = event.note + semitones
				-- Clamp to valid MIDI range (0-127)
				if new_note >= 0 and new_note <= 127 then
					event.note = new_note
					count = count + 1
				end
			end
		end
	end

	return count
end

-- Scale event velocities
-- @param factor number Velocity multiplier (e.g., 0.5 = half, 2.0 = double)
-- @param start_tick number Optional start of range (default: all events)
-- @param end_tick number Optional end of range (exclusive)
-- @return number Count of events scaled
function EventStore:scale_velocity(factor, start_tick, end_tick)
	if factor == 1.0 then return 0 end

	start_tick = start_tick or 1
	end_tick = end_tick or (self:last_tick() and self:last_tick() + 1) or 1

	local count = 0

	for tick, events in self:iter_range(start_tick, end_tick) do
		for _, event in ipairs(events) do
			-- Check if this is a note event with velocity
			if event.vel then
				local new_vel = math.floor(event.vel * factor + 0.5)
				-- Clamp to valid MIDI range (1-127, 0 is note-off)
				event.vel = math.max(1, math.min(127, new_vel))
				count = count + 1
			end
		end
	end

	return count
end

return EventStore
