-- ============================================================================
-- PLAYBACK SOURCE ABSTRACTION
-- Unified interface for different playback sources in the Clip component
--
-- PlaybackSource provides a common interface for:
--   - LiveBufferSource: Live buffer playback (follows buffer.tick)
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

-- ============================================================================
-- BASE PLAYBACK SOURCE
-- ============================================================================

local PlaybackSource = {}
PlaybackSource.__index = PlaybackSource

function PlaybackSource.new(config)
	local self = setmetatable({}, PlaybackSource)
	self.type = config.type or 'base'
	self.events = config.events or {} -- sparse table: tick -> {event1, event2, ...}
	self.loop_start = config.loop_start or 1
	self.loop_length = config.loop_length or 0
	self.tick = config.tick or self.loop_start
	self.loop_enabled = config.loop_enabled ~= false -- default true
	self.active = false
	self.mute_input = config.mute_input or false -- whether this source mutes input
	return self
end

-- Get loop end tick (inclusive)
function PlaybackSource:get_loop_end()
	return self.loop_start + self.loop_length - 1
end

-- Check if tick is within loop boundaries
function PlaybackSource:is_tick_in_loop(tick)
	return tick >= self.loop_start and tick <= self:get_loop_end()
end

-- Wrap tick to loop boundaries
function PlaybackSource:wrap_tick(tick)
	if self.loop_length <= 0 then return self.loop_start end
	local relative = tick - self.loop_start
	local wrapped = relative % self.loop_length
	return self.loop_start + wrapped
end

-- Get events at specific tick
function PlaybackSource:get_events(tick)
	return self.events[tick]
end

-- Get events at current tick
function PlaybackSource:get_current_events()
	return self.events[self.tick]
end

-- Advance tick and return events at the current position (before advancing)
-- Returns: events, loop_boundary_reached
function PlaybackSource:advance()
	if not self.active then return nil, false end

	local current_tick = self.tick
	local events = self.events[current_tick]
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
	if flags.debug_clip then
		print('PlaybackSource activated: ' .. self.type .. ' at tick ' .. self.tick)
	end
end

-- Deactivate source (stop playback)
function PlaybackSource:deactivate()
	self.active = false
	if flags.debug_clip then
		print('PlaybackSource deactivated: ' .. self.type)
	end
end

-- Reset to loop start
function PlaybackSource:reset()
	self.tick = self.loop_start
end

-- Update loop boundaries
function PlaybackSource:set_loop(start_tick, length)
	self.loop_start = start_tick
	self.loop_length = length
	-- Ensure tick is within new boundaries
	if not self:is_tick_in_loop(self.tick) then
		self.tick = self:wrap_tick(self.tick)
	end
end

-- Update events (for sources that need to refresh their data)
function PlaybackSource:set_events(events)
	self.events = events
end

-- Count events in source (for debugging)
function PlaybackSource:event_count()
	local count = 0
	for _, events in pairs(self.events) do
		count = count + #events
	end
	return count
end

-- ============================================================================
-- LIVE BUFFER SOURCE
-- Plays directly from buffer component, follows buffer.tick
-- ============================================================================

local LiveBufferSource = setmetatable({}, { __index = PlaybackSource })
LiveBufferSource.__index = LiveBufferSource

function LiveBufferSource.new(buffer_component)
	local self = setmetatable(PlaybackSource.new({
		type = 'live',
		loop_start = buffer_component.buffer_start,
		loop_length = buffer_component.buffer_length,
		mute_input = false, -- live buffer doesn't mute input
	}), LiveBufferSource)
	self.buffer_component = buffer_component
	return self
end

-- Override: get events from buffer component
function LiveBufferSource:get_events(tick)
	return self.buffer_component.buffer[tick]
end

function LiveBufferSource:get_current_events()
	return self.buffer_component.buffer[self.tick]
end

-- Override: sync loop boundaries from buffer
function LiveBufferSource:sync_from_buffer()
	self.loop_start = self.buffer_component.buffer_start
	self.loop_length = self.buffer_component.buffer_length
end

-- Override: sync tick from buffer
function LiveBufferSource:sync_tick()
	self.tick = self.buffer_component.tick
end

-- ============================================================================
-- FROZEN BUFFER SOURCE
-- Plays from frozen snapshot, independent tick
-- ============================================================================

local FrozenBufferSource = setmetatable({}, { __index = PlaybackSource })
FrozenBufferSource.__index = FrozenBufferSource

function FrozenBufferSource.new(config)
	local self = setmetatable(PlaybackSource.new({
		type = 'frozen',
		events = config.events or {},
		loop_start = config.loop_start or 1,
		loop_length = config.loop_length or 0,
		mute_input = true, -- frozen playback mutes input (AUTO mode)
	}), FrozenBufferSource)
	return self
end

-- Create frozen snapshot from buffer component
function FrozenBufferSource:freeze_from_buffer(buffer_component, start_tick, length)
	self.loop_start = start_tick
	self.loop_length = length
	self.tick = start_tick

	-- Create shallow copy of events in range
	local loop_end = start_tick + length - 1
	self.events = {}
	for tick, events in pairs(buffer_component.buffer) do
		if tick >= start_tick and tick <= loop_end then
			self.events[tick] = events -- shallow copy
		end
	end

	if flags.debug_clip then
		print('FrozenBufferSource: frozen range ' .. start_tick .. '-' .. loop_end .. ' (' .. self:event_count() .. ' events)')
	end
end

-- Update frozen snapshot incrementally (for step-by-step updates)
function FrozenBufferSource:update_step(buffer_component, step_start, step_end)
	local loop_end = self:get_loop_end()

	-- Clamp to loop boundaries
	step_start = math.max(step_start, self.loop_start)
	step_end = math.min(step_end, loop_end)

	-- Update events from buffer
	for tick = step_start, step_end do
		if buffer_component.buffer[tick] then
			self.events[tick] = buffer_component.buffer[tick]
		else
			self.events[tick] = nil
		end
	end
end

-- ============================================================================
-- SCRUB SOURCE
-- Grid-triggered playback of buffer range, separate tick tracking
-- ============================================================================

local ScrubSource = setmetatable({}, { __index = PlaybackSource })
ScrubSource.__index = ScrubSource

function ScrubSource.new(config)
	local self = setmetatable(PlaybackSource.new({
		type = 'scrub',
		events = config.events or {},
		loop_start = config.loop_start or 1,
		loop_length = config.loop_length or 0,
		loop_enabled = config.loop_enabled ~= false,
		mute_input = true, -- scrub always mutes input
	}), ScrubSource)
	return self
end

-- Create scrub buffer from buffer component
function ScrubSource:create_from_buffer(buffer_component, start_tick, end_tick, loop_mode)
	self.loop_start = start_tick
	self.loop_length = end_tick - start_tick + 1
	self.tick = start_tick
	self.loop_enabled = loop_mode

	-- Create shallow copy of events in range
	self.events = {}
	for tick = start_tick, end_tick do
		if buffer_component.buffer[tick] then
			self.events[tick] = buffer_component.buffer[tick]
		end
	end

	if flags.debug_scrub then
		print('ScrubSource: created range ' .. start_tick .. '-' .. end_tick .. ' (loop: ' .. tostring(loop_mode) .. ', events: ' .. self:event_count() .. ')')
	end
end

-- Update scrub range (for multi-pad selection)
function ScrubSource:update_range(buffer_component, start_tick, end_tick)
	local old_start = self.loop_start
	local old_end = self:get_loop_end()

	self.loop_start = start_tick
	self.loop_length = end_tick - start_tick + 1

	-- Clear events outside new range
	for tick, _ in pairs(self.events) do
		if tick < start_tick or tick > end_tick then
			self.events[tick] = nil
		end
	end

	-- Add new events from buffer
	for tick = start_tick, end_tick do
		if buffer_component.buffer[tick] and not self.events[tick] then
			self.events[tick] = buffer_component.buffer[tick]
		end
	end

	-- Ensure tick is within new range
	if self.tick < start_tick or self.tick > end_tick then
		self.tick = start_tick
	end
end

-- ============================================================================
-- CLIP BANK SOURCE
-- Loaded clip playback from clip bank slot
-- ============================================================================

local ClipBankSource = setmetatable({}, { __index = PlaybackSource })
ClipBankSource.__index = ClipBankSource

function ClipBankSource.new(config)
	local self = setmetatable(PlaybackSource.new({
		type = 'clip_bank',
		events = config.events or {},
		loop_start = 1, -- clips always start at tick 1
		loop_length = config.loop_length or 0,
		mute_input = true, -- clip playback mutes input (AUTO mode)
	}), ClipBankSource)
	self.slot = config.slot
	self.name = config.name
	self.original_loop_start = config.original_loop_start -- from when clip was saved
	return self
end

-- Load from clip bank entry
function ClipBankSource:load_from_bank_entry(bank_entry, slot)
	self.slot = slot
	self.name = bank_entry.name
	self.events = bank_entry.buffer
	self.loop_length = bank_entry.length or 0
	self.original_loop_start = bank_entry.loop_start
	self.loop_start = 1 -- clips are always 1-based
	self.tick = 1

	if flags.debug_clip then
		print('ClipBankSource: loaded slot ' .. slot .. ' "' .. (self.name or 'unnamed') .. '" length=' .. self.loop_length)
	end
end

-- ============================================================================
-- MODULE EXPORTS
-- ============================================================================

return {
	PlaybackSource = PlaybackSource,
	LiveBufferSource = LiveBufferSource,
	FrozenBufferSource = FrozenBufferSource,
	ScrubSource = ScrubSource,
	ClipBankSource = ClipBankSource,
}
