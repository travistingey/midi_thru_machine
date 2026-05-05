-- ============================================================================
-- PLAYBACK SOURCE ABSTRACTION
-- Unified interface for different playback sources in the Clip component
--
-- PlaybackSource provides a common interface for:
--   - FrozenBufferSource: Frozen snapshot playback
--   - ScrubSource: Grid-triggered scrub playback
--   - ClipBankSource: Loaded clip playback
--
-- All sources share:
--   - Event lookup by tick
--   - Loop boundaries (start, length)
--   - Loop behavior (continuous vs one-shot)
--   - Tick management (current position, advancement, wrapping)
-- ============================================================================

local flags = require('Foobar/lib/utilities/flags')
local EventStore = require('Foobar/lib/utilities/event_store')

-- ============================================================================
-- BASE PLAYBACK SOURCE
-- ============================================================================

local PlaybackSource = {}
PlaybackSource.__index = PlaybackSource

function PlaybackSource.new(config)
	local self = setmetatable({}, PlaybackSource)
	self.type = config.type or 'base'
	
	-- Create EventStore for event storage
	self.store = EventStore.new()
	
	-- If config.events is provided, import into store
	if config.events then
		self.store:from_sparse_table(config.events)
	end
	
	-- Backward compatibility: self.events points to store's events table
	-- This allows existing code that reads source.events to continue working
	self.events = self.store.events
	
	self.loop_start = config.loop_start or 1
	self.loop_length = config.loop_length or 0
	self.tick = config.tick or self.loop_start
	self.loop_enabled = config.loop_enabled ~= false -- default true
	self.active = false
	self.mute_input = config.mute_input or false -- whether this source mutes input
	return self
end

-- Get loop end tick (inclusive)
function PlaybackSource:get_loop_end() return self.loop_start + self.loop_length - 1 end

-- Check if tick is within loop boundaries
function PlaybackSource:is_tick_in_loop(tick) return tick >= self.loop_start and tick <= self:get_loop_end() end

-- Wrap tick to loop boundaries
function PlaybackSource:wrap_tick(tick)
	if self.loop_length <= 0 then return self.loop_start end
	local relative = tick - self.loop_start
	local wrapped = relative % self.loop_length
	return self.loop_start + wrapped
end

-- Get events at specific tick
function PlaybackSource:get_events(tick) return self.store:get(tick) end

-- Get events at current tick
function PlaybackSource:get_current_events() return self.store:get(self.tick) end

-- Advance tick and return events at the current position (before advancing)
-- Returns: events, loop_boundary_reached
function PlaybackSource:advance()
	if not self.active then return nil, false end

	local current_tick = self.tick
	local events = self.store:get(current_tick)
	local next_tick = current_tick + 1
	local loop_boundary = false

	-- Check for loop boundary
	if next_tick > self:get_loop_end() then
		loop_boundary = true
		if self.loop_enabled then
			-- Wrap to start
			self.tick = self.loop_start
		else
			-- One-shot: deactivate after completing
			self:deactivate()
		end
	else
		self.tick = next_tick
	end

	return events, loop_boundary
end

-- Jump to specific tick (clamped to loop boundaries)
function PlaybackSource:jump_to(tick)
	if self:is_tick_in_loop(tick) then
		self.tick = tick
	else
		self.tick = self:wrap_tick(tick)
	end
end

-- Activate source (start playback)
function PlaybackSource:activate()
	self.active = true
	if flags.debug_clip then print('PlaybackSource activated: ' .. self.type .. ' at tick ' .. self.tick) end
end

-- Deactivate source (stop playback)
function PlaybackSource:deactivate()
	self.active = false
	if flags.debug_clip then print('PlaybackSource deactivated: ' .. self.type) end
end

-- Reset to loop start
function PlaybackSource:reset() self.tick = self.loop_start end

-- Update loop boundaries
function PlaybackSource:set_loop(start_tick, length)
	self.loop_start = start_tick
	self.loop_length = length
	-- Ensure tick is within new boundaries
	if not self:is_tick_in_loop(self.tick) then self.tick = self:wrap_tick(self.tick) end
end

-- Update events (for sources that need to refresh their data)
function PlaybackSource:set_events(events)
	self.store:from_sparse_table(events)
	-- Keep backward compatibility alias
	self.events = self.store.events
end

-- Count events in source (for debugging)
function PlaybackSource:event_count()
	return self.store:event_count()
end

-- ============================================================================
-- FROZEN BUFFER SOURCE
-- Plays from frozen snapshot, independent tick
-- ============================================================================

local FrozenBufferSource = setmetatable({}, { __index = PlaybackSource })
FrozenBufferSource.__index = FrozenBufferSource

function FrozenBufferSource.new(config)
	local self = setmetatable(
		PlaybackSource.new({
			type = 'frozen',
			events = config.events or {},
			loop_start = config.loop_start or 1,
			loop_length = config.loop_length or 0,
			mute_input = true, -- frozen playback mutes input (AUTO mode)
		}),
		FrozenBufferSource
	)
	return self
end

-- Create frozen snapshot from buffer component.
-- Performs a deep copy of buffer events so destructive edits on the frozen
-- snapshot (and any clip later derived from it) never leak back into the live
-- recording buffer.
function FrozenBufferSource:freeze_from_buffer(buffer_component, start_tick, length)
	self.loop_start = start_tick
	self.loop_length = length
	self.tick = start_tick

	local loop_end = start_tick + length - 1
	local sparse_events = EventStore.deep_copy_sparse(buffer_component.buffer, start_tick, loop_end)
	sparse_events = EventStore.fix_note_pairs_in_sparse(sparse_events, start_tick, loop_end)

	self.store:from_sparse_table(sparse_events)
	self.events = self.store.events

	if flags.debug_clip then print('FrozenBufferSource: frozen range ' .. start_tick .. '-' .. loop_end .. ' (' .. self:event_count() .. ' events)') end
end

-- Update frozen snapshot incrementally (for step-by-step updates).
-- Deep-copies the events from the live buffer so the snapshot remains
-- independent of subsequent buffer recording.
function FrozenBufferSource:update_step(buffer_component, step_start, step_end)
	local loop_end = self:get_loop_end()

	step_start = math.max(step_start, self.loop_start)
	step_end = math.min(step_end, loop_end)

	local fresh = EventStore.deep_copy_sparse(buffer_component.buffer, step_start, step_end)
	for tick = step_start, step_end do
		local events = fresh[tick]
		if events then
			self.store:set(tick, events)
		else
			self.store:delete(tick)
		end
	end
	self.events = self.store.events
end

-- ============================================================================
-- SCRUB SOURCE
-- Grid-triggered playback of buffer range, separate tick tracking
-- ============================================================================

local ScrubSource = setmetatable({}, { __index = PlaybackSource })
ScrubSource.__index = ScrubSource

function ScrubSource.new(config)
	local self = setmetatable(
		PlaybackSource.new({
			type = 'scrub',
			events = config.events or {},
			loop_start = config.loop_start or 1,
			loop_length = config.loop_length or 0,
			loop_enabled = config.loop_enabled ~= false,
			mute_input = true, -- scrub always mutes input
		}),
		ScrubSource
	)
	return self
end

-- Create scrub buffer from buffer component.
-- Deep-copies events so scrub-time edits cannot mutate the live buffer.
function ScrubSource:create_from_buffer(buffer_component, start_tick, end_tick, loop_mode, initial_tick)
	self.loop_start = start_tick
	self.loop_length = end_tick - start_tick + 1
	if initial_tick and initial_tick >= start_tick and initial_tick <= end_tick then
		self.tick = initial_tick
	else
		self.tick = start_tick
	end
	self.loop_enabled = loop_mode

	local sparse_events = EventStore.deep_copy_sparse(buffer_component.buffer, start_tick, end_tick)
	sparse_events = EventStore.fix_note_pairs_in_sparse(sparse_events, start_tick, end_tick)

	self.store:from_sparse_table(sparse_events)
	self.events = self.store.events

	if flags.debug_scrub then print('ScrubSource: created range ' .. start_tick .. '-' .. end_tick .. ' (loop: ' .. tostring(loop_mode) .. ', initial_tick: ' .. self.tick .. ', events: ' .. self:event_count() .. ')') end
end

-- Update scrub range (for multi-pad selection).
-- Deep-copies fresh events into the scrub source on every range change so
-- the scrub data remains independent of the live buffer.
function ScrubSource:update_range(buffer_component, start_tick, end_tick)
	local old_start = self.loop_start
	local old_end = self:get_loop_end()

	self.loop_start = start_tick
	self.loop_length = end_tick - start_tick + 1

	if old_start < start_tick then
		self.store:delete_range(old_start, start_tick)
	end
	if old_end > end_tick then
		self.store:delete_range(end_tick + 1, old_end + 1)
	end

	local sparse_events = EventStore.deep_copy_sparse(buffer_component.buffer, start_tick, end_tick)
	sparse_events = EventStore.fix_note_pairs_in_sparse(sparse_events, start_tick, end_tick)
	for tick, events in pairs(sparse_events) do
		self.store:set(tick, events)
	end

	self.events = self.store.events

	if self.tick < start_tick or self.tick > end_tick then self.tick = start_tick end
end

-- ============================================================================
-- CLIP BANK SOURCE
-- Loaded clip playback from clip bank slot
-- ============================================================================

local ClipBankSource = setmetatable({}, { __index = PlaybackSource })
ClipBankSource.__index = ClipBankSource

function ClipBankSource.new(config)
	local self = setmetatable(
		PlaybackSource.new({
			type = 'clip_bank',
			events = config.events or {},
			loop_start = 1, -- clips always start at tick 1
			loop_length = config.loop_length or 0,
			mute_input = true, -- clip playback mutes input (AUTO mode)
		}),
		ClipBankSource
	)
	self.slot = config.slot
	self.name = config.name
	self.original_loop_start = config.original_loop_start -- from when clip was saved
	return self
end

-- Load from clip bank entry.
-- Deep-copies bank_entry.buffer so the playback source owns its events.
-- This keeps the bank entry on disk authoritative: edits made through the
-- frozen editing surface flow back to the bank entry only via the explicit
-- save_edits_* paths, never via accidental aliasing.
function ClipBankSource:load_from_bank_entry(bank_entry, slot)
	self.slot = slot
	self.name = bank_entry.name

	local fresh_buffer = EventStore.deep_copy_sparse_all(bank_entry.buffer)
	self.store:from_sparse_table(fresh_buffer)
	self.events = self.store.events

	self.loop_length = bank_entry.length or 0
	self.original_loop_start = bank_entry.loop_start
	self.loop_start = 1 -- clips are always 1-based
	self.tick = 1

	if flags.debug_clip then print('ClipBankSource: loaded slot ' .. slot .. ' "' .. (self.name or 'unnamed') .. '" length=' .. self.loop_length) end
end

-- ============================================================================
-- MODULE EXPORTS
-- ============================================================================

return {
	PlaybackSource = PlaybackSource,
	FrozenBufferSource = FrozenBufferSource,
	ScrubSource = ScrubSource,
	ClipBankSource = ClipBankSource,
}
