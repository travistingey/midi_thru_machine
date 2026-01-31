-- Timing Constants
-- Centralized timing values for buffer, clip, and sequencer operations
-- All tick calculations use 1-based indexing (Lua convention):
--   - First clock event = tick 1
--   - First step (at default step_size) = ticks 1 to step_size
--   - Step index formula: floor((tick - 1) / step_size) + 1

local TimingConstants = {}

-- Step size for buffer overwrite clearing and incremental frozen buffer updates
-- Events are grouped into steps of this many ticks
-- Used in: buffer.lua (overwrite clearing), clip.lua (frozen buffer updates)
TimingConstants.DEFAULT_STEP_SIZE = 8

-- Default buffer length in bars (for new buffers)
TimingConstants.DEFAULT_BUFFER_BARS = 64

-- Calculate buffer length in ticks from bars
-- @param bars number Number of bars
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return number Length in ticks
function TimingConstants.bars_to_ticks(bars, ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	local ticks_per_bar = ppqn * 4 -- 4 beats per bar
	return bars * ticks_per_bar
end

-- Calculate default buffer length in ticks
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return number Default buffer length in ticks
function TimingConstants.get_default_buffer_length(ppqn)
	return TimingConstants.bars_to_ticks(TimingConstants.DEFAULT_BUFFER_BARS, ppqn)
end

-- Convert tick to step index (1-based)
-- Step 1 = ticks 1 to step_size, Step 2 = ticks step_size+1 to 2*step_size, etc.
-- @param tick number Tick position (1-based)
-- @param step_size number Step length in ticks (defaults to DEFAULT_STEP_SIZE)
-- @return number Step index (1-based)
function TimingConstants.tick_to_step(tick, step_size)
	step_size = step_size or TimingConstants.DEFAULT_STEP_SIZE
	return math.floor((tick - 1) / step_size) + 1
end

-- Convert step index to tick range (returns start_tick, end_tick inclusive)
-- @param step_index number Step index (1-based)
-- @param step_size number Step length in ticks (defaults to DEFAULT_STEP_SIZE)
-- @return number, number start_tick, end_tick (both 1-based, inclusive)
function TimingConstants.step_to_tick_range(step_index, step_size)
	step_size = step_size or TimingConstants.DEFAULT_STEP_SIZE
	local start_tick = (step_index - 1) * step_size + 1
	local end_tick = step_index * step_size
	return start_tick, end_tick
end

-- Convert step index to start tick (1-based)
-- @param step_index number Step index (1-based)
-- @param step_size number Step length in ticks (defaults to DEFAULT_STEP_SIZE)
-- @return number Start tick of the step (1-based)
function TimingConstants.step_to_start_tick(step_index, step_size)
	step_size = step_size or TimingConstants.DEFAULT_STEP_SIZE
	return (step_index - 1) * step_size + 1
end

-- Calculate step index relative to a buffer start position
-- @param tick number Current tick position
-- @param buffer_start number Buffer start tick
-- @param step_size number Step length in ticks (defaults to DEFAULT_STEP_SIZE)
-- @return number Step index (1-based) relative to buffer start
function TimingConstants.tick_to_buffer_step(tick, buffer_start, step_size)
	step_size = step_size or TimingConstants.DEFAULT_STEP_SIZE
	return math.floor((tick - buffer_start) / step_size) + 1
end

-- Calculate step tick range relative to a buffer
-- @param step_index number Step index (1-based) relative to buffer start
-- @param buffer_start number Buffer start tick
-- @param buffer_end number Buffer end tick (for clamping)
-- @param step_size number Step length in ticks (defaults to DEFAULT_STEP_SIZE)
-- @return number, number start_tick, end_tick (clamped to buffer bounds)
function TimingConstants.buffer_step_to_tick_range(step_index, buffer_start, buffer_end, step_size)
	step_size = step_size or TimingConstants.DEFAULT_STEP_SIZE
	local step_start = buffer_start + (step_index - 1) * step_size
	local step_end = math.min(step_start + step_size - 1, buffer_end)
	return step_start, step_end
end

-- ============================================================================
-- TIME FORMATTING HELPERS
-- Format tick positions as bars:beats:sixteenths (e.g., "1:1:1")
-- Uses musical time: bar 1 starts at tick 1
-- ============================================================================

-- Convert tick to bars:beats:sixteenths string
-- Format: "bar:beat:sixteenth" (all 1-based)
-- @param tick number Tick position (1-based)
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return string Formatted time string (e.g., "1:1:1")
function TimingConstants.tick_to_time_string(tick, ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	local ticks_per_sixteenth = ppqn / 4
	local ticks_per_beat = ppqn
	local ticks_per_bar = ppqn * 4

	-- Convert 1-based tick to 0-based for math
	local t = tick - 1

	local bar = math.floor(t / ticks_per_bar) + 1
	local beat_offset = t % ticks_per_bar
	local beat = math.floor(beat_offset / ticks_per_beat) + 1
	local sixteenth_offset = beat_offset % ticks_per_beat
	local sixteenth = math.floor(sixteenth_offset / ticks_per_sixteenth) + 1

	return bar .. ':' .. beat .. ':' .. sixteenth
end

-- Format a tick range as "start – end" time string
-- @param start_tick number Start tick (1-based)
-- @param end_tick number End tick (1-based)
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return string Formatted range string (e.g., "1:1:1 – 2:4:4")
function TimingConstants.tick_range_to_time_string(start_tick, end_tick, ppqn)
	return TimingConstants.tick_to_time_string(start_tick, ppqn) .. ' – ' .. TimingConstants.tick_to_time_string(end_tick, ppqn)
end

-- Format step length as note value string
-- @param step_length number Step length in ticks
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return string Note value string (e.g., "1/16", "1/4", "1 bar", "4 bars")
function TimingConstants.step_length_to_note_string(step_length, ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	local ticks_per_bar = ppqn * 4

	-- Check for bar-based values first
	if step_length >= ticks_per_bar then
		local bars = step_length / ticks_per_bar
		if bars == 1 then
			return '1 bar'
		else
			return bars .. ' bars'
		end
	end

	-- Check for beat-based values
	local note_values = {
		{ div = ppqn * 4, name = '1' }, -- whole note
		{ div = ppqn * 2, name = '1/2' }, -- half note
		{ div = ppqn, name = '1/4' }, -- quarter note
		{ div = ppqn / 2, name = '1/8' }, -- eighth note
		{ div = ppqn / 4, name = '1/16' }, -- sixteenth note
		{ div = ppqn / 8, name = '1/32' }, -- thirty-second note
	}

	for _, nv in ipairs(note_values) do
		if step_length == nv.div then
			return nv.name
		end
	end

	-- Fallback: show ticks
	return step_length .. ' ticks'
end

-- Calculate minimum selection resolution (32nd note)
-- @param ppqn number Pulses per quarter note (defaults to App.ppqn or 96)
-- @return number Minimum selection step in ticks
function TimingConstants.get_min_selection_step(ppqn)
	ppqn = ppqn or (App and App.ppqn) or 96
	return ppqn / 8 -- 32nd note
end

return TimingConstants
