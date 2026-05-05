local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')
local EventStore = require(path_name .. 'utilities/event_store')
local Persistence = require(path_name .. 'utilities/persistence')
local SequenceUtils = require(path_name .. 'utilities/sequence_utils')
local TimingConstants = require(path_name .. 'utilities/timing_constants')
local SyncManager = require(path_name .. 'utilities/sync_manager')
local PlaybackSources = require(path_name .. 'utilities/playback_source')

-- Clip component handles playback of MIDI events from buffer
-- Separated from Buffer component for clear separation of concerns:
-- Buffer = Recording, Clip = Playback

local Clip = {}
Clip.name = 'clip'
Clip.__index = Clip
setmetatable(Clip, { __index = TrackComponent })

function Clip:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
	o:set(o)
	return o
end

function Clip:set(o)
	self.id = o.id or 1
	-- Reference to buffer component for live buffer access
	self.buffer = nil -- Will be set after buffer is loaded

	-- Playback state
	self.tick = o.tick or 0 -- Playback position in ticks
	self.playback_mode = o.playback_mode or 1 -- Default is Input
	self.buffer_loop = o.buffer_loop ~= nil and o.buffer_loop or true -- Default to continuous loop

	-- Frozen buffer for playback
	self.buffer_frozen = false -- Whether buffer is frozen
	-- Tracks what source the current frozen snapshot was copied from.
	-- Used so loop endpoint edits can reslice from the same coordinate space/source.
	-- Possible values: 'buffer', 'clip_bank', 'scrub'
	self.frozen_from = nil
	self.playback_start = nil -- Playback loop start (independent of buffer.buffer_start)
	self.playback_length = nil -- Playback loop length

	-- Scrub playback state (redundant - use sources.scrub for state)
	-- Keeping scrub_mode for quick checks, but prefer active_source == sources.scrub
	self.scrub_mode = false
	-- Remember what was playing before we entered scrub mode.
	-- This is important because when we stop scrub we want to restore
	-- playback to the previous surface (frozen snapshot, clip slot, etc.).
	self._active_source_before_scrub = nil

	-- True if we automatically froze from clip_bank at scrub start.
	-- When this happens, we keep the frozen snapshot active after scrub ends.
	self._froze_for_scrub = false

	-- Unified sync manager replaces multiple sync queues
	-- Provides named slots: 'scrub', 'clip', 'general', etc.
	-- Uses App-level launch_sync_length instead of per-track action_sync_length
	self.sync_manager = SyncManager.new(self, function(component) return App.launch_sync_length or (App.ppqn * 4) end)

	-- Clip bank management
	self.clip_bank = {} -- 16 slots: {[1-16] = nil or {filename, name, buffer, playback_settings}}
	self.current_slot = nil -- Which slot is currently playing (nil = live buffer)

	-- PlaybackSource instances (unified abstraction)
	self.sources = {
		frozen = PlaybackSources.FrozenBufferSource.new({}),
		scrub = PlaybackSources.ScrubSource.new({}),
		clip_bank = nil, -- ClipBankSource - created when clip is loaded
	}
	self.active_source = nil -- Reference to currently active PlaybackSource

	-- Notes this clip has dispatched but not yet closed. Populated in run_events
	-- and drained at loop boundaries via close_active_notes(). Lets us emit
	-- precise note_off pairs for the notes WE played without nuking unrelated
	-- output (e.g. notes the user is improvising on the same MIDI device).
	-- Key: ch * 128 + effective_note (post-reharmonization). Value: { ch, note }.
	self._active_notes = {}
end

-- Close only the notes this clip dispatched (vs. kill_notes which is a global
-- panic via output_device:kill that affects user-played notes too).
-- Used at loop boundaries to keep musicality intact: the next tick will
-- typically re-trigger the looping notes, and the device manager's
-- last_note_on closure coalesces the pair so we don't get audible gaps.
function Clip:close_active_notes()
	if not self.track.output_device then return end
	if not next(self._active_notes) then return end
	for k, info in pairs(self._active_notes) do
		self.track.output_device:send({
			type = 'note_off',
			note = info.note,
			vel = 0,
			ch = info.ch,
		})
		self._active_notes[k] = nil
	end
end

-- Set buffer reference
-- Should be called by Track instead of directly setting self.buffer
function Clip:set_buffer(buffer_component) self.buffer = buffer_component end

function Clip:get_next_sync_tick(custom_sync_length)
	local sync_length = custom_sync_length or App.launch_sync_length or (App.ppqn * 4)
	return SequenceUtils.get_next_sync_tick(sync_length)
end

function Clip:should_wait_for_sync(custom_sync_length)
	local sync_length = custom_sync_length or App.launch_sync_length or (App.ppqn * 4)
	return SequenceUtils.should_wait_for_sync(sync_length)
end

-- Get the active PlaybackSource instance
-- Returns the currently active PlaybackSource or nil if no playback is active
function Clip:get_active_source() return self.active_source end

-- Get the current playback source buffer table (for backward compatibility)
-- Returns the buffer table to read from
-- Prefer using get_active_source() and PlaybackSource methods when possible
function Clip:get_playback_source()
	if self.current_slot and self.clip_bank[self.current_slot] then
		-- Return loaded clip buffer
		return self.clip_bank[self.current_slot].buffer
	else
		-- Return frozen buffer if frozen, otherwise buffer (for positioning only, no playback)
		if self.buffer_frozen and self.sources.frozen.events then
			return self.sources.frozen.events
		elseif self.buffer then
			return self.buffer.buffer
		end
		return nil
	end
end

-- Check if clip is actively playing (outputting events)
-- Returns true if clip is actually playing events, false otherwise
-- Note: Scrub mode IS considered "actively playing" - it mutes input and only plays buffer
function Clip:is_actively_playing()
	-- Clip is actively playing if:
	-- 1. Scrub mode is active (grid-triggered playback - mutes input, only buffer playback)
	-- 2. Frozen buffer is active (frozen buffer playback)
	-- 3. A clip is loaded and playing (loaded clip playback)

	return (self.active_source == self.sources.scrub) or self.buffer_frozen or (self.current_slot and self.clip_bank[self.current_slot] ~= nil)
end

-- Get the current playback length (for loop wrapping)
-- Returns the length in ticks for the current playback source
function Clip:get_playback_length()
	-- If we're in frozen editing/playback mode, loop boundaries must come from the frozen snapshot.
	-- Otherwise tick-wrap can keep using the loaded clip_bank length, producing silence after edits.
	if self.buffer_frozen then
		if self.playback_length then return self.playback_length end
		if self.sources and self.sources.frozen and self.sources.frozen.loop_length then
			return self.sources.frozen.loop_length
		end
		return 0
	end

	-- Not frozen: when a clip is loaded, loop boundaries come from the clip_bank entry.
	if self.current_slot and self.clip_bank[self.current_slot] then
		local clip_entry = self.clip_bank[self.current_slot]
		if clip_entry.length then return clip_entry.length end
		-- Fallback: calculate from buffer if length not stored
		if clip_entry.buffer then
			local max_tick = 0
			for tick, _ in pairs(clip_entry.buffer) do
				if tick > max_tick then max_tick = tick end
			end
			return max_tick
		end
		return 0
	end

	-- Live/unfrozen fallback
	if self.buffer then
		return self.buffer.buffer_length
	end
	return 0
end

-- Get the current playback start (for loop wrapping)
-- Returns the start tick for the current playback source
function Clip:get_playback_start()
	-- If we're in frozen mode, loop start must come from the frozen snapshot.
	if self.buffer_frozen then
		if self.playback_start then return self.playback_start end
		if self.sources and self.sources.frozen and self.sources.frozen.loop_start then
			return self.sources.frozen.loop_start
		end
		return 0
	end

	-- Not frozen: when a clip is loaded, clip_bank playback always starts at 1.
	if self.current_slot and self.clip_bank[self.current_slot] then
		return 1
	end

	-- Live/unfrozen fallback
	if self.buffer then
		return self.buffer.buffer_start
	end
	return 0
end

-- Queue a scrub action (replaces any existing pending scrub action)
-- pad_check_fn: function to call to verify pad is still held
-- sync_length: optional custom sync length (defaults to minimum 1/16th note)
function Clip:queue_scrub_action(start_tick, end_tick, loop_mode, pad_check_fn, sync_length, initial_tick)
	-- Calculate scrub range length
	local scrub_range_length = end_tick - start_tick + 1

	-- Use provided sync_length or default to minimum 1/16th note
	local min_sync_length = App.ppqn / 4 -- 1/16th note minimum (24 ticks at 96 ppqn)
	sync_length = sync_length or min_sync_length
	sync_length = math.max(sync_length, min_sync_length)

	-- Default initial_tick to start_tick if not provided
	initial_tick = initial_tick or start_tick

	local action_fn = function(component, action_data)
		-- Check if pad is still held before executing
		if action_data.pad_check_fn and action_data.pad_check_fn() then
			component:start_scrub(action_data.start_tick, action_data.end_tick, action_data.loop_mode, action_data.initial_tick)
			if flags.debug_scrub then
				print('Scrub started (synced to ' .. action_data.sync_length .. ' ticks): ' .. action_data.start_tick .. '-' .. action_data.end_tick .. ', initial_tick: ' .. action_data.initial_tick)
			end
			-- Emit event so bufferseq can update its state
			component:emit('scrub_started', {
				start_tick = action_data.start_tick,
				end_tick = action_data.end_tick,
			})
		else
			component:stop_scrub()
			-- Pad was released, cancel the action
			if flags.debug_scrub then print('Scrub cancelled: pad no longer held') end
			component:emit('scrub_stopped', {
				start_tick = action_data.start_tick,
				end_tick = action_data.end_tick,
			})
		end
	end

	local action_data = {
		start_tick = start_tick,
		end_tick = end_tick,
		loop_mode = loop_mode,
		pad_check_fn = pad_check_fn,
		sync_length = sync_length,
		scrub_range_length = scrub_range_length,
		initial_tick = initial_tick,
	}

	-- Queue in the 'scrub' slot with provided sync_length
	self.sync_manager:queue('scrub', action_fn, action_data, sync_length)
end

-- Clear pending scrub action (called when pad is released)
function Clip:clear_pending_scrub() self.sync_manager:clear('scrub') end

-- Queue a scrub stop action (for synced scrub ending)
-- sync_length: sync length for the stop action
function Clip:queue_scrub_stop(sync_length)
	if self.active_source ~= self.sources.scrub then return end

	local min_sync_length = App.ppqn / 4 -- 1/16th note minimum
	sync_length = sync_length or min_sync_length
	sync_length = math.max(sync_length, min_sync_length)

	local action_fn = function(component, action_data)
		if flags.debug_scrub then print('Scrub stopped (synced to ' .. action_data.sync_length .. ' ticks)') end
		component:stop_scrub()
		component:emit('scrub_stopped', {})
	end

	local action_data = {
		sync_length = sync_length,
	}

	-- Queue in the 'scrub_stop' slot
	self.sync_manager:queue('scrub_stop', action_fn, action_data, sync_length)
end

-- Freeze the buffer (create snapshot of current playback range).
--
-- Defensive guard: this re-slices a fresh snapshot from the live buffer and
-- DISCARDS any existing frozen content. When the buffer is already frozen
-- with the same range and the same source ('buffer'), this is a no-op so
-- repeated calls (e.g. from upstream UI gestures) cannot wipe user edits
-- such as quantize or transpose. Callers that genuinely need to discard a
-- snapshot and re-slice should call unfreeze_buffer() first.
function Clip:freeze_buffer()
	if not self.buffer or not self.playback_start or not self.playback_length then return end

	if self.buffer_frozen and self.frozen_from == 'buffer'
		and self.sources.frozen.loop_start == self.playback_start
		and self.sources.frozen.loop_length == self.playback_length then
		if flags.debug_clip then
			print('Clip: freeze_buffer skipped — already frozen at same range, preserving edits')
		end
		return
	end

	-- Use FrozenBufferSource to create snapshot
	self.sources.frozen:freeze_from_buffer(self.buffer, self.playback_start, self.playback_length)
	self.sources.frozen:activate()
	self.active_source = self.sources.frozen

	self.buffer_frozen = true
	self.frozen_from = 'buffer'
	if flags.debug_clip then
		local loop_end = self.playback_start + self.playback_length - 1
		print('Clip: Buffer frozen at playback range ' .. self.playback_start .. '-' .. loop_end)
	end

	-- Kill notes when freezing buffer to prevent stuck notes from previous playback
	if App.playing then self:kill_notes() end

	-- Update monitor state to respect monitoring settings (AUTO mutes)
	self.track:update_monitor_state()

	-- Emit event for UI updates (e.g., row pad visualization)
	self:emit('buffer_frozen', { track_id = self.track.id })
end

-- Unfreeze the buffer (clear frozen snapshot)
function Clip:unfreeze_buffer()
	local was_frozen = self.buffer_frozen

	-- Deactivate FrozenBufferSource
	self.sources.frozen:deactivate()
	if self.active_source == self.sources.frozen then self.active_source = nil end

	self.buffer_frozen = false
	self.frozen_from = nil
	-- Reset playback loop boundaries
	self.playback_start = nil
	self.playback_length = nil

	-- Kill notes when unfreezing buffer to prevent stuck notes from frozen playback
	if was_frozen and App.playing then self:kill_notes() end

	-- Update monitor state to restore input monitoring
	self.track:update_monitor_state()

	-- Emit event for UI updates (e.g., row pad visualization)
	if was_frozen then
		self:emit('buffer_unfrozen', { track_id = self.track.id })
	end
end

-- Freeze from active source (scrub or clip_bank)
-- Generalizes freeze to work from any playback source.
-- Performs a deep copy so subsequent edits on the frozen surface cannot
-- mutate the original source (clip bank or scrub) data.
function Clip:freeze_from_source()
	if not self.active_source then return false end

	-- If already frozen, no-op
	if self.active_source == self.sources.frozen then return true end

	local source = self.active_source
	local frozen = self.sources.frozen

	local source_sparse = EventStore.deep_copy_sparse_all(source.store.events)
	frozen.store:from_sparse_table(source_sparse)
	frozen.events = frozen.store.events -- keep alias
	
	-- Copy loop boundaries and tick position
	frozen.loop_start = source.loop_start
	frozen.loop_length = source.loop_length
	frozen.tick = source.tick
	
	-- Update playback_start/playback_length for compatibility
	self.playback_start = source.loop_start
	self.playback_length = source.loop_length
	
	-- If freezing from scrub, stop scrub
	if source == self.sources.scrub then
		self:stop_scrub()
	end
	
	-- Activate frozen source
	frozen:activate()
	self.active_source = frozen
	self.buffer_frozen = true
	self.frozen_from = source.type
	
	-- Preserve clip.tick position
	self.tick = frozen.tick
	
	-- Kill notes when switching sources
	if App.playing then self:kill_notes() end
	
	-- Update monitor state
	self.track:update_monitor_state()
	
	-- Emit event
	self:emit('buffer_frozen', { track_id = self.track.id })
	
	if flags.debug_clip then
		print('Clip: Frozen from source ' .. source.type .. ' at tick ' .. frozen.tick)
	end
	
	return true
end

-- Get the editable EventStore (frozen source)
-- If clip is loaded but not frozen, implicitly freeze it first
-- Returns nil if no editable source is available
function Clip:get_edit_store()
	-- If already frozen, return frozen store
	if self.buffer_frozen then
		return self.sources.frozen.store
	end
	
	-- If clip is loaded, freeze it first (implicit freeze for editing)
	if self.current_slot and self.sources.clip_bank then
		if self:freeze_from_source() then
			return self.sources.frozen.store
		end
	end
	
	-- No editable source available
	return nil
end

-- Set playback loop boundaries (for frozen buffer playback).
--
-- When the buffer is already frozen, the new loop range is reconciled against
-- the existing frozen snapshot:
--   * Ticks that fall OUTSIDE the new range are trimmed.
--   * Ticks that are NEWLY-ADDED to the range (extending past the old range)
--     are filled from the underlying source (live buffer / clip bank / scrub).
--   * Ticks that exist in BOTH the old and new range are PRESERVED — they may
--     contain user edits (quantize, transpose, manual nudges) that must not
--     be overwritten by another adjust-loop gesture.
--
-- This is the difference between "drag loop endpoints to reframe what plays"
-- (preserving edits) and "re-slice a fresh region from source" (which only
-- happens for the genuinely new ticks).
function Clip:set_playback_loop(start_tick, length)
	local new_end = start_tick + length - 1

	self.playback_start = start_tick
	self.playback_length = length

	if not self.buffer_frozen then
		if flags.debug_clip then print('Clip: Playback loop set to ' .. start_tick .. '-' .. new_end) end
		return
	end

	local store = self.sources.frozen.store
	local old_start = self.sources.frozen.loop_start
	local old_end = self.sources.frozen:get_loop_end()
	local has_old_range = (old_start and old_end and old_end >= old_start and self.sources.frozen.loop_length and self.sources.frozen.loop_length > 0)

	-- Trim entries that are now outside the new range.
	-- delete_range(s, e) is exclusive-end; delete [old_start, start_tick) trims
	-- the old head, and [new_end+1, old_end+1) trims the old tail.
	if has_old_range then
		if old_start < start_tick then store:delete_range(old_start, start_tick) end
		if old_end > new_end then store:delete_range(new_end + 1, old_end + 1) end
	end

	-- Resolve the underlying source for any newly-exposed ticks. Editing on a
	-- frozen snapshot derived from clip_bank/scrub must reslice from the same
	-- coordinate space the snapshot was originally taken from.
	local source_events = nil
	if self.frozen_from == 'clip_bank' then
		if self.sources.clip_bank and self.sources.clip_bank.store and self.sources.clip_bank.store.events then
			source_events = self.sources.clip_bank.store.events
		end
	elseif self.frozen_from == 'scrub' then
		if self.sources.scrub and self.sources.scrub.events then
			source_events = self.sources.scrub.events
		end
	else
		if self.buffer and self.buffer.buffer then source_events = self.buffer.buffer end
	end

	-- Local helper: deep-copy [s, e] from source_events and write into the
	-- frozen store. Deep copy keeps the frozen snapshot independent of the
	-- source so subsequent edits can't mutate the original.
	local function fill_range(s, e)
		if not source_events or s > e then return end
		local fresh = EventStore.deep_copy_sparse(source_events, s, e)
		for tick = s, e do
			local evs = fresh[tick]
			if evs then store:set(tick, evs) end
		end
	end

	if not has_old_range then
		-- No prior range to compare against — fill the whole new range from source.
		fill_range(start_tick, new_end)
	else
		-- Compute intersection of old and new ranges. The intersection is
		-- preserved (those ticks may contain user edits). Only the regions of
		-- the new range that fall OUTSIDE the intersection are filled from source.
		local intersect_start = old_start
		if start_tick > intersect_start then intersect_start = start_tick end
		local intersect_end = old_end
		if new_end < intersect_end then intersect_end = new_end end

		if intersect_start > intersect_end then
			-- Old and new ranges are disjoint. The trim above already cleared
			-- the old range; fill the entire new range from source.
			fill_range(start_tick, new_end)
		else
			-- Fill the regions before and after the intersection.
			-- The intersection itself is left untouched to preserve edits.
			if start_tick < intersect_start then fill_range(start_tick, intersect_start - 1) end
			if intersect_end < new_end then fill_range(intersect_end + 1, new_end) end
		end
	end

	-- Update frozen source loop boundaries
	self.sources.frozen:set_loop(start_tick, length)

	if flags.debug_clip then print('Clip: Playback loop set to ' .. start_tick .. '-' .. new_end) end
end

-- Execute pending sync actions (should be called on each clock tick)
function Clip:execute_sync_actions() self.sync_manager:execute_all() end

-- Queue load bank slot on next launch-sync boundary (clip_slot param / transport start)
function Clip:queue_clip_slot_load(bank_slot)
	if bank_slot < 1 or not self.clip_bank[bank_slot] then return end
	if self.current_slot == bank_slot then return end
	local sync_length = App.launch_sync_length or (App.ppqn * 4)
	self.sync_manager:queue('clip_slot_param', function(component, action_data)
		component:load_clip_from_bank(action_data.bank_slot)
	end, { bank_slot = bank_slot }, sync_length)
end

-- Queue unload (live) on next launch-sync boundary
function Clip:queue_clip_slot_unload()
	if not self.current_slot and not self.buffer_frozen then return end
	local sync_length = App.launch_sync_length or (App.ppqn * 4)
	self.sync_manager:queue('clip_slot_param', function(component, _)
		component:unload_clip()
	end, {}, sync_length)
end

-- On transport start: apply track clip_slot param (0 = live, N = bank slot)
-- Only acts on the loaded clip slot. A manually-frozen buffer is an independent
-- user action and is preserved across transport stop/start.
function Clip:apply_clip_slot_on_transport_start()
	local pid = 'track_' .. self.track.id .. '_clip_slot'
	local slot = params:get(pid) or 0
	if slot < 0 then slot = 0 end
	if slot > 16 then slot = 16 end
	if slot == 0 then
		-- Only queue an unload when an actual clip is loaded; never touch buffer_frozen here.
		if self.current_slot then self:queue_clip_slot_unload() end
		return
	end
	if not self.clip_bank[slot] then
		print('Clip: clip_slot ' .. slot .. ' is empty (track ' .. self.track.id .. ')')
		return
	end
	if self.current_slot == slot then return end
	self:queue_clip_slot_load(slot)
end

-- Transport Event Handling
function Clip:transport_event(data)
	if not self.buffer then return data end

	-- Timing tracking (conditional on flag)
	local transport_start = flags.buffer_timing_stats and util.time() or nil

	if data.type == 'start' then
		-- Start playback at appropriate position
		-- For clips: start at loop_start; for frozen buffer: start at playback_start
		if not self.scrub_mode then
			if self.current_slot and self.clip_bank[self.current_slot] then
				self.tick = 1
				-- Emit event for mode components
				self:emit('clip_playback_started', { bank_slot = self.current_slot })
			else
				-- Frozen buffer: start at playback_start; otherwise sync to buffer.tick (for positioning)
				if self.buffer_frozen and self.playback_start then
					self.tick = self.playback_start
				elseif self.buffer then
					self.tick = self.buffer.tick
				end
				-- Emit event for mode components (no active playback)
				self:emit('clip_playback_started', { bank_slot = nil })
			end
		end
		-- Clear any lingering buffer notes from previous playback
		self:kill_notes()
		-- Update monitor state when starting playback
		self.track:update_monitor_state()
		-- Launch clip from clip_slot param on next sync (if not already that slot)
		self:apply_clip_slot_on_transport_start()
	elseif data.type == 'stop' then
		-- Don't reset tick - buffer is continuously running
		-- Kill all active buffer notes to prevent stuck notes
		self:kill_notes()
		-- Emit event for mode components
		if self.current_slot then
			self:emit('clip_playback_stopped', { bank_slot = self.current_slot })
		else
			self:emit('clip_playback_stopped', { bank_slot = nil })
		end
		-- Update monitor state when stopping
		self.track:update_monitor_state()
	elseif data.type == 'clock' and App.playing then
		-- Execute any pending sync actions that have reached their boundary
		-- SyncManager handles all sync slots: scrub, clip, general, etc.
		self:execute_sync_actions()

		-- Ensure tick is within loop bounds (safety check for normal playback)
		-- This handles cases where loop points changed during playback or tick got out of sync
		if self.active_source ~= self.sources.scrub then
			local playback_start = self:get_playback_start()
			local playback_length = self:get_playback_length()

			if not SequenceUtils.is_tick_in_loop(self.tick, playback_start, playback_length) then self.tick = SequenceUtils.wrap_tick_to_loop(self.tick, playback_start, playback_length) end
		end

		-- Always update clip.tick based on normal playback rules (even during scrub mode)
		-- This ensures playback can seamlessly resume when scrub stops
		local playback_start = self:get_playback_start()
		local playback_length = self:get_playback_length()

		-- Look up events at current tick BEFORE incrementing (events were recorded at this tick)
		-- This matches the buffer recording behavior where events are stored at self.tick after incrementing
		local lookup_tick = self.tick

		-- Calculate the next tick for loop boundary checking
		local next_tick = self.tick + 1

		if next_tick >= playback_start + playback_length then
			-- Handle clip playback modes at loop boundary.
			-- Surgical close: only emit note_off for notes THIS clip dispatched.
			-- The device manager's last_note_on closure coalesces with the
			-- immediately-following loop-start note_on, so musicality stays
			-- intact and notes the user is playing live aren't interrupted.
			self:close_active_notes()

			-- Emit loop boundary event
			if self.current_slot then
				self:emit('clip_loop_boundary', { bank_slot = self.current_slot })
			else
				self:emit('clip_loop_boundary', { bank_slot = nil })
			end

			-- One-shot mode: stop clip playback after completing loop
			if not self.buffer_loop then
				-- Emit playback stopped event for one-shot mode
				if self.current_slot then
					self:emit('clip_playback_stopped', { bank_slot = self.current_slot, reason = 'oneshot' })
				else
					self:emit('clip_playback_stopped', { bank_slot = nil, reason = 'oneshot' })
				end
				-- Update monitor state when playback stops (one-shot mode)
				self.track:update_monitor_state()
			end

			-- Wrap to start of loop AFTER reading events at current tick
			-- Don't overwrite lookup_tick - we need to read events at the last tick before wrapping
			self.tick = playback_start
		else
			-- Increment tick after looking up events
			self.tick = self.tick + 1
		end

		-- Handle scrub mode separately from normal playback
		if self.active_source == self.sources.scrub then
			-- Look up events at current scrub tick BEFORE incrementing (events were recorded at this tick)
			local scrub_lookup_tick = self.sources.scrub.tick

			-- Play events from current position FIRST (before boundary check)
			-- This ensures we play the current tick before wrapping, preventing doubling at boundaries
			if self.sources.scrub.events[scrub_lookup_tick] then self:run_events(self.sources.scrub.events[scrub_lookup_tick]) end

			-- Calculate next scrub tick for loop boundary checking
			local next_scrub_tick = scrub_lookup_tick + 1
			local scrub_end = self.sources.scrub:get_loop_end()

			-- Now handle boundary wrapping (after playing current position).
			-- Use surgical close_active_notes for boundary transitions so we
			-- don't nuke unrelated notes the user may be playing live.
			if self.sources.scrub.loop_enabled and next_scrub_tick > scrub_end then
				-- Loop back to scrub start
				self:close_active_notes()
				self.sources.scrub.tick = self.sources.scrub.loop_start
			elseif not self.sources.scrub.loop_enabled then
				-- Play-thru mode
				if next_scrub_tick > scrub_end then
					-- Completed one pass through scrub range
					if not self.buffer_loop then
						-- One-shot mode: stop scrub after one loop through range
						self:close_active_notes()
						self:stop_scrub()
					else
						-- Continuous loop mode: continue playing through full buffer
						-- Wrap at buffer end
						local buffer_end = self.buffer.buffer_start + self.buffer.buffer_length - 1
						if next_scrub_tick > buffer_end then
							self:close_active_notes()
							self.sources.scrub.tick = self.buffer.buffer_start
						else
							self.sources.scrub.tick = next_scrub_tick
						end
					end
				else
					-- Still within scrub range, continue playing
					self.sources.scrub.tick = next_scrub_tick
				end
			else
				self.sources.scrub.tick = next_scrub_tick
			end
		else
			-- Update monitor state based on playback/recording state
			self.track:update_monitor_state()

			-- Use active source to get events
			local active_source = self:get_active_source()
			if active_source then
				-- Look up events at the current tick (before incrementing)
				local events = active_source:get_events(lookup_tick)
				if events then self:run_events(events) end
			end
		end

		-- Record transport timing (conditional on flag)
		if flags.buffer_timing_stats and transport_start then
			local transport_elapsed = (util.time() - transport_start) * 1000 -- Note: timing stats would need to be added to Clip if needed
		end
	end

	return data
end

-- Playback buffer events
-- Handles scrub mode, frozen buffer playback, and loaded clip playback
function Clip:run_events(events)
	if not self.track.output_device then return end

	-- Check if scrub mode is active (grid-triggered playback)
	-- OR if frozen buffer is active (frozen buffer playback)
	-- OR if a clip is loaded and playing (clip playback)
	local playback_enabled = false

	if self.active_source == self.sources.scrub or self.buffer_frozen then
		-- Scrub mode or frozen buffer: update monitor state (may mute input based on monitor setting)
		playback_enabled = true
		self.track:update_monitor_state()
	elseif App.playing and self.current_slot and self.clip_bank[self.current_slot] then
		-- Loaded clip is playing: update monitor state (may mute input based on monitor setting)
		playback_enabled = true
		self.track:update_monitor_state()
	end

	if not playback_enabled then return end

	for _, event in ipairs(events) do
		local midi_msg = {}

		for k, v in pairs(event) do
			midi_msg[k] = v
		end

		-- Set buffer_sent to prevent Output component from also recording these events
		-- (we'll record them explicitly in the clip component to control when/how they're recorded)
		midi_msg.buffer_sent = App.tick

		if self.playback_mode == 1 then
			self.track:send(midi_msg)
		elseif self.playback_mode == 2 then
			self.track:send_input(midi_msg)
		elseif self.playback_mode == 3 then
			self.track:send_output(midi_msg)
		elseif self.playback_mode == 4 then
			self.track:send_scale(midi_msg)
		end

		-- Track which notes are currently sounding so loop-boundary cleanup
		-- can be surgical. Uses the post-reharmonization note (event.new_note)
		-- when present so the off matches what the device actually heard.
		if event.note then
			local effective_note = event.new_note or event.note
			local ch = event.ch or 1
			local key = ch * 128 + effective_note
			if event.type == 'note_on' then
				local entry = self._active_notes[key]
				if entry then
					entry.ch = ch
					entry.note = effective_note
				else
					self._active_notes[key] = { ch = ch, note = effective_note }
				end
			elseif event.type == 'note_off' then
				self._active_notes[key] = nil
			end
		end

		-- Don't record clip playback events back into buffer
		-- Buffer records continuously from live input only
		-- Recording playback events would cause feedback loops and doubling
		-- Clip playback is separate from buffer recording - they don't interact
	end
end

-- Send note_off for all active buffer notes (prevents stuck notes).
-- This is the global panic via DeviceMethods:kill — it closes ALL pending
-- note_on closures registered with the device manager (across triggers and
-- input). Use Clip:close_active_notes() at loop boundaries instead, since
-- this can interrupt notes the user is playing live on the same output.
function Clip:kill_notes()
	if not self.track.output_device then return end
	self.track.output_device:kill()
	-- The device-side panic invalidates our per-clip tracking too.
	for k in pairs(self._active_notes) do self._active_notes[k] = nil end
end

-- Scrub playback: temporarily play a range of the buffer
-- Creates shallow copy of buffer range for isolated playback
-- Always blocks input regardless of monitoring setting
-- loop_mode: true = loop the range, false = play through once then stop
function Clip:start_scrub(start_tick, end_tick, loop_mode, initial_tick)
	-- Kill any currently playing buffer notes before scrub
	self:kill_notes()

	-- Reset per-scrub flags
	self._froze_for_scrub = false

	-- Default initial_tick to start_tick if not provided
	initial_tick = initial_tick or start_tick

	-- Save what was playing so we can restore it when scrub stops.
	self._active_source_before_scrub = self.active_source

	-- If a clip is loaded but we are not in frozen edit mode yet,
	-- copy the clip playback source into the frozen editing surface first.
	-- This makes scrub operate on the same content the user is viewing.
	if self.current_slot and (not self.buffer_frozen) and self.active_source == self.sources.clip_bank then
		local ok = self:freeze_from_source()
		if ok then
			self._froze_for_scrub = true
		end
	end

	-- Initialize ScrubSource and activate it
	if self.buffer_frozen and self.sources.frozen and self.sources.frozen.store then
		-- When scrubbing on a frozen editing surface, the gesture coordinates
		-- should stay within the frozen loop boundaries; clamp to avoid creating
		-- an empty scrub source (which would look like "scrub is silent").
		local frozen_loop_start = self.sources.frozen.loop_start or self.playback_start or start_tick
		local frozen_loop_end = self.sources.frozen:get_loop_end() or (frozen_loop_start + (self.playback_length or 1) - 1)

		start_tick = math.max(start_tick, frozen_loop_start)
		end_tick = math.min(end_tick, frozen_loop_end)

		if end_tick < start_tick then
			-- Gesture didn't intersect the frozen loop (likely due to coordinate mismatch).
			-- Fall back to scrubbing the entire frozen loop rather than doing nothing.
			start_tick = frozen_loop_start
			end_tick = frozen_loop_end
		end

		-- When editing on the frozen surface, scrub should read from the frozen snapshot,
		-- not from the live buffer (which may be unrelated to the clip content).
		-- Deep copy so scrub-time edits cannot mutate the frozen source.
		local sparse_events = EventStore.deep_copy_sparse(self.sources.frozen.store.events, start_tick, end_tick)
		sparse_events = EventStore.fix_note_pairs_in_sparse(sparse_events, start_tick, end_tick)

		self.sources.scrub.loop_start = start_tick
		self.sources.scrub.loop_length = end_tick - start_tick + 1
		self.sources.scrub.loop_enabled = loop_mode
		if initial_tick and initial_tick >= start_tick and initial_tick <= end_tick then
			self.sources.scrub.tick = initial_tick
		else
			self.sources.scrub.tick = start_tick
		end

		self.sources.scrub.store:from_sparse_table(sparse_events)
		-- Re-wire backward-compatible alias after store:clear() replaced events table.
		self.sources.scrub.events = self.sources.scrub.store.events
		self.sources.scrub:activate()
		self.active_source = self.sources.scrub
	elseif self.buffer then
		self.sources.scrub:create_from_buffer(self.buffer, start_tick, end_tick, loop_mode, initial_tick)
		self.sources.scrub:activate()
		self.active_source = self.sources.scrub
	end

	-- Keep scrub_mode flag for quick checks (redundant but convenient)
	self.scrub_mode = true

	-- Scrub mode always blocks input regardless of monitoring setting
	-- Use emit to ensure the event system is notified
	self.track:emit('mute_input', true)

	if flags.debug_scrub then
		print('Scrub started: ' .. start_tick .. '-' .. end_tick .. ' (loop: ' .. tostring(loop_mode) .. ', initial_tick: ' .. initial_tick .. ', events: ' .. self:count_scrub_events() .. ')')
	end
end

-- Helper to count events in scrub buffer (for debugging)
function Clip:count_scrub_events()
	local count = 0
	if self.sources.scrub and self.sources.scrub.events then
		for _, events in pairs(self.sources.scrub.events) do
			count = count + #events
		end
	end
	return count
end

-- Update scrub range (for multi-pad selection)
-- If current tick is outside new range, jump to stay within boundaries
function Clip:update_scrub(start_tick, end_tick)
	if self.active_source ~= self.sources.scrub then return end

	-- Kill notes to prevent stuck notes when range changes
	self:kill_notes()

	-- Update ScrubSource range
	if self.buffer_frozen and self.sources.frozen and self.sources.frozen.store then
		-- Clamp to frozen loop boundaries so we don't end up with an empty scrub source.
		local frozen_loop_start = self.sources.frozen.loop_start or self.playback_start or start_tick
		local frozen_loop_end = self.sources.frozen:get_loop_end() or (frozen_loop_start + (self.playback_length or 1) - 1)
		start_tick = math.max(start_tick, frozen_loop_start)
		end_tick = math.min(end_tick, frozen_loop_end)
		if end_tick < start_tick then
			-- Fall back to full frozen loop.
			start_tick = frozen_loop_start
			end_tick = frozen_loop_end
		end

		-- Rebuild scrub source events from frozen snapshot.
		-- Deep copy so scrub-time edits cannot mutate the frozen source.
		local sparse_events = EventStore.deep_copy_sparse(self.sources.frozen.store.events, start_tick, end_tick)
		sparse_events = EventStore.fix_note_pairs_in_sparse(sparse_events, start_tick, end_tick)

		self.sources.scrub.loop_start = start_tick
		self.sources.scrub.loop_length = end_tick - start_tick + 1
		-- Preserve current loop enabled state while updating range.
		local loop_enabled = self.sources.scrub.loop_enabled
		self.sources.scrub.loop_enabled = loop_enabled
		self.sources.scrub.store:from_sparse_table(sparse_events)
		-- Re-wire backward-compatible alias after store:clear() replaced events table.
		self.sources.scrub.events = self.sources.scrub.store.events

		-- Clamp scrub tick into new bounds.
		if self.sources.scrub.tick < start_tick or self.sources.scrub.tick > end_tick then
			self.sources.scrub.tick = start_tick
		end
	else
		if self.buffer then self.sources.scrub:update_range(self.buffer, start_tick, end_tick) end
	end
end

-- Stop scrub and restore normal playback
function Clip:stop_scrub()
	if self.active_source ~= self.sources.scrub then return end

	-- Kill any scrub notes
	self:kill_notes()

	-- Restore what was playing before scrub started.
	local restore_source = self._active_source_before_scrub
	local froze_for_scrub = self._froze_for_scrub
	self._active_source_before_scrub = nil
	self._froze_for_scrub = false

	-- Fallback: if we scrubbed from a surface but didn't capture it,
	-- restore to the most likely source.
	if not restore_source then
		if self.buffer_frozen then
			restore_source = self.sources.frozen
		elseif self.current_slot and self.sources.clip_bank then
			restore_source = self.sources.clip_bank
		end
	end

	-- Deactivate ScrubSource
	self.sources.scrub:deactivate()
	if self.active_source == self.sources.scrub then
		self.active_source = restore_source
	end

	-- Clear scrub_mode flag
	self.scrub_mode = false

	-- Clear any pending scrub action
	self.sync_manager:clear('scrub')

	-- Restore input monitoring
	self.track:update_monitor_state()

	-- Scrub should not be considered a destructive edit.
	-- If we auto-froze from clip_bank at scrub start, immediately unfreeze after
	-- scrub stops to restore playback behavior from the clip source.
	if froze_for_scrub then
		self:unfreeze_buffer()
	end
end

--==============================================================================
-- Clip Bank Management
--==============================================================================

--- Save a clip from buffer to bank slot.
-- The saved clip is a deep copy of the source range so destructive edits on the
-- bank entry (or on a clip later loaded from it) cannot mutate the live buffer
-- or frozen source.
--
-- Cutover semantics (controlled by `opts.cutover`):
--   * cutover = true (default, used by clipgrid quick-save / empty-pad save):
--       After saving, if the buffer was frozen-from-buffer (no clip loaded),
--       unfreeze the buffer so monitoring/recording resumes from the live
--       source. The caller is expected to then load the saved clip if it wants
--       seamless playback continuity.
--   * cutover = false (used by bufferseq / default-mode menu save):
--       Leave the frozen state untouched so the user can continue saving
--       additional clips from the same frozen snapshot.
--
-- @param bank_slot number The bank slot (positive integer)
-- @param loop_start number The start tick of the loop
-- @param loop_end number The end tick of the loop
-- @param name string Optional name for the clip
-- @param opts table Optional. Recognized keys: cutover (boolean, default true)
-- @return boolean True if save succeeded
function Clip:save_clip_to_bank(bank_slot, loop_start, loop_end, name, opts)
	if not self.buffer then
		print('Clip: Cannot save clip - buffer not available')
		return false
	end

	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

	-- Default to cutover=true so existing call sites that omit opts retain
	-- their prior auto-unfreeze behavior. Bufferseq's multi-save flow opts out.
	local cutover = true
	if opts ~= nil and opts.cutover == false then cutover = false end

	-- Performance optimization: Use frozen buffer if available and range matches
	local source_buffer = nil

	if self.buffer_frozen and self.sources.frozen.events then
		-- Use frozen buffer - already filtered to exact range we need!
		source_buffer = self.sources.frozen.events
		loop_start = self.playback_start
		loop_end = self.playback_start + self.playback_length - 1
	else
		source_buffer = self.buffer.buffer
	end

	-- Deep copy the range so the saved clip owns its events. Without this,
	-- the bank entry's events would alias the live buffer / frozen source and
	-- editing the saved clip would silently mutate the original recording.
	local range_sparse = EventStore.deep_copy_sparse(source_buffer, loop_start, loop_end)
	range_sparse = EventStore.fix_note_pairs_in_sparse(range_sparse, loop_start, loop_end)

	local clip_buffer = {}
	local clip_length = loop_end - loop_start + 1
	for tick, events in pairs(range_sparse) do
		local remapped_tick = tick - loop_start + 1
		clip_buffer[remapped_tick] = events
	end

	-- Create clip data structure
	local clip_data = {
		name = name or string.format('Clip %03d', bank_slot),
		length = clip_length,
		loop_start = loop_start, -- Store original loop start for playback
		buffer = clip_buffer,
	}

	-- Save to file
	local filename = string.format('track_%d_clip_%03d.lua', self.track.id, bank_slot)
	local success = Persistence.save_clip_file(self.track.id, bank_slot, clip_data)

	if success then
		-- Update clip bank
		self.clip_bank[bank_slot] = {
			filename = filename,
			name = clip_data.name,
			length = clip_length,
			loop_start = loop_start, -- Store original loop start
			buffer = clip_buffer,
			playback_settings = {},
		}

		-- Save bank metadata
		self:save_bank_metadata()

		-- Emit event for mode components
		self:emit('clip_saved', { bank_slot = bank_slot, name = clip_data.name })

		-- Cutover behavior. Only auto-unfreeze when:
		--   * cutover was requested by the caller, AND
		--   * the buffer was frozen-from-buffer (current_slot is nil — the
		--     "dirty editing of a loaded clip" case stays frozen).
		-- Bufferseq's multi-save menu passes cutover=false to keep the frozen
		-- snapshot in place across successive saves.
		if cutover and self.buffer_frozen and not self.current_slot then
			self:unfreeze_buffer()
			self.track:update_monitor_state()
		end

		print('Clip: Saved clip to bank slot ' .. bank_slot)
		return true
	else
		print('Clip: Failed to save clip to bank slot ' .. bank_slot)
		return false
	end
end

--- Load a clip from bank slot into playback
-- @param bank_slot number The bank slot (positive integer)
-- @return boolean True if load succeeded
function Clip:load_clip_from_bank(bank_slot)
	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

	if not self.clip_bank[bank_slot] then
		print('Clip: No clip in bank slot ' .. bank_slot)
		return false
	end

	-- Kill notes when loading a clip to prevent stuck notes from previous playback
	if App.playing then self:kill_notes() end

	-- Create and activate ClipBankSource
	self.sources.clip_bank = PlaybackSources.ClipBankSource.new({
		slot = bank_slot,
	})
	self.sources.clip_bank:load_from_bank_entry(self.clip_bank[bank_slot], bank_slot)
	self.sources.clip_bank:activate()
	self.active_source = self.sources.clip_bank

	-- Set as current playback source (backward compatibility)
	self.current_slot = bank_slot

	-- Reset tick to 1 (clips are 1-based) - backward compatibility
	self.tick = 1

	-- Emit event for mode components
	self:emit('clip_loaded', { bank_slot = bank_slot })
	self.track:update_monitor_state()
	self.track:sync_clip_slot_param()
	print('Clip: Loaded clip from bank slot ' .. bank_slot)
	return true
end

--- Load a clip by filename into a bank slot
-- @param filename string The filename
-- @param bank_slot number The bank slot (positive integer)
-- @param load_as_current boolean If true, load as current clip
-- @return boolean True if load succeeded
function Clip:load_clip_by_filename(filename, bank_slot, load_as_current)
	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

	-- Load clip file
	local clip_data = Persistence.load_clip_file(self.track.id, filename)

	if not clip_data then
		print('Clip: Failed to load clip file ' .. filename)
		return false
	end

	-- Store in clip bank
	self.clip_bank[bank_slot] = {
		filename = filename,
		name = clip_data.name or string.format('Clip %03d', bank_slot),
		length = clip_data.length or 0,
		loop_start = clip_data.loop_start or 0, -- Store loop_start from loaded data
		buffer = clip_data.buffer,
		playback_settings = {},
	}

	-- Save bank metadata
	self:save_bank_metadata()

	-- Optionally load as current clip
	if load_as_current then
		-- Kill notes when loading a new clip to prevent stuck notes from previous playback
		if App.playing then self:kill_notes() end
		self.current_slot = bank_slot
		-- Clips are 1-based, start at tick 1
		self.tick = 1
		-- Emit event for mode components
		self:emit('clip_loaded', { bank_slot = bank_slot, filename = filename })
		self.track:sync_clip_slot_param()
	end

	print('Clip: Loaded clip ' .. filename .. ' into bank slot ' .. bank_slot)
	return true
end

--- Unload current clip and return to no active playback
-- Also unfreezes buffer if frozen
-- @return boolean True if unload succeeded
function Clip:unload_clip()
	local had_clip = (self.current_slot ~= nil)
	local was_frozen = self.buffer_frozen

	-- Kill notes when unloading clip to prevent stuck notes
	if had_clip and App.playing then self:kill_notes() end

	if self.current_slot then
		local previous_slot = self.current_slot

		-- Deactivate ClipBankSource
		if self.sources.clip_bank then self.sources.clip_bank:deactivate() end
		if self.active_source == self.sources.clip_bank then self.active_source = nil end
		self.sources.clip_bank = nil

		self.current_slot = nil
		-- Sync clip.tick to buffer.tick (buffer is continuously running, don't reset)
		if self.buffer then self.tick = self.buffer.tick end
		-- Emit event for mode components
		self:emit('clip_unloaded', { bank_slot = previous_slot })
	end

	-- Unfreeze buffer if frozen (allows returning to live playback)
	if self.buffer_frozen then
		self:unfreeze_buffer()
		-- Sync clip.tick to buffer.tick when unfreezing (buffer is continuously running)
		if self.buffer then self.tick = self.buffer.tick end
	end

	-- Update monitor state after unloading/unfreezing (restores input monitoring if AUTO mode)
	if had_clip or was_frozen then
		self.track:update_monitor_state()
		self.track:sync_clip_slot_param()
		if had_clip then print('Clip: Unloaded clip, returning to no active playback') end
		if was_frozen then print('Clip: Unfroze buffer, returning to no active playback') end
		return true
	end

	return false
end

--- Clear a clip slot
-- @param bank_slot number The bank slot (positive integer)
-- @return boolean True if clear succeeded
function Clip:clear_clip_slot(bank_slot)
	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

	local had_playing = (self.current_slot == bank_slot)
	-- If currently playing, stop playback
	if had_playing then
		if self.sources.clip_bank then self.sources.clip_bank:deactivate() end
		if self.active_source == self.sources.clip_bank then self.active_source = nil end
		self.sources.clip_bank = nil
		self.current_slot = nil
		if self.buffer then self.tick = self.buffer.tick end
		self.track:update_monitor_state()
	end

	-- Delete the clip file if it exists
	if self.clip_bank[bank_slot] and self.clip_bank[bank_slot].filename then Persistence.delete_clip_file(self.track.id, self.clip_bank[bank_slot].filename) end

	-- Remove from clip bank
	self.clip_bank[bank_slot] = nil

	-- Save bank metadata
	self:save_bank_metadata()

	-- Emit event for mode components
	self:emit('clip_cleared', { bank_slot = bank_slot })

	if had_playing then self.track:sync_clip_slot_param() end
	print('Clip: Cleared bank slot ' .. bank_slot)
	return true
end

--- Save bank metadata to file
function Clip:save_bank_metadata()
	local bank_data = {
		slots = {},
	}

	-- Collect slot metadata
	for slot = 1, 16 do
		if self.clip_bank[slot] then
			bank_data.slots[slot] = {
				filename = self.clip_bank[slot].filename,
				name = self.clip_bank[slot].name,
				loop_start = self.clip_bank[slot].loop_start, -- Save loop_start
				playback_settings = self.clip_bank[slot].playback_settings or {},
			}
		end
	end

	Persistence.save_clip_bank(self.track.id, bank_data)
end

--- Load bank metadata from file
function Clip:load_bank_metadata()
	local bank_data = Persistence.load_clip_bank(self.track.id)

	if not bank_data or not bank_data.slots then return end

	-- Load clips from metadata
	for slot = 1, 16 do
		if bank_data.slots[slot] then
			local slot_data = bank_data.slots[slot]
			local clip_data = Persistence.load_clip_file(self.track.id, slot_data.filename)

			if clip_data then
				self.clip_bank[slot] = {
					filename = slot_data.filename,
					name = slot_data.name or clip_data.name,
					length = clip_data.length or 0,
					loop_start = slot_data.loop_start or clip_data.loop_start or 0, -- Restore loop_start
					buffer = clip_data.buffer,
					playback_settings = slot_data.playback_settings or {},
				}
			end
		end
	end
end

--==============================================================================
-- Editing Operations (only on frozen source)
--==============================================================================

-- Quantize events in frozen source
-- @param grid_size number Grid size in ticks (e.g., 24 for 1/16 note at 96 ppqn)
-- @param start_tick number Optional start of range (default: loop start)
-- @param end_tick number Optional end of range (default: loop end)
-- @return number Count of events moved
function Clip:quantize_frozen(grid_size, start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	-- Use loop boundaries as default range
	if not start_tick then start_tick = self:get_playback_start() end
	if not end_tick then end_tick = self:get_playback_start() + self:get_playback_length() end

	return store:quantize(grid_size, start_tick, end_tick)
end

-- Unquantize events in frozen source using raw_tick
-- @param start_tick number Optional start of range (default: loop start)
-- @param end_tick number Optional end of range (default: loop end)
-- @return number Count of events moved
function Clip:unquantize_frozen(start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end

	-- Use loop boundaries as default range
	if not start_tick then start_tick = self:get_playback_start() end
	if not end_tick then end_tick = self:get_playback_start() + self:get_playback_length() end

	return store:unquantize_from_raw(start_tick, end_tick)
end

-- Transpose MIDI note events in frozen source
-- @param semitones number Number of semitones to transpose (positive = up, negative = down)
-- @param start_tick number Optional start of range (default: loop start)
-- @param end_tick number Optional end of range (default: loop end)
-- @return number Count of events transposed
function Clip:transpose_frozen(semitones, start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	-- Use loop boundaries as default range
	if not start_tick then start_tick = self:get_playback_start() end
	if not end_tick then end_tick = self:get_playback_start() + self:get_playback_length() end
	
	return store:transpose(semitones, start_tick, end_tick)
end

-- Scale event velocities in frozen source
-- @param factor number Velocity multiplier (e.g., 0.5 = half, 2.0 = double)
-- @param start_tick number Optional start of range (default: loop start)
-- @param end_tick number Optional end of range (default: loop end)
-- @return number Count of events scaled
function Clip:scale_velocity_frozen(factor, start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	-- Use loop boundaries as default range
	if not start_tick then start_tick = self:get_playback_start() end
	if not end_tick then end_tick = self:get_playback_start() + self:get_playback_length() end
	
	return store:scale_velocity(factor, start_tick, end_tick)
end

-- Set velocities to an absolute value in frozen source
-- @param value number Velocity value (0-127)
-- @param start_tick number Optional start of range (default: loop start)
-- @param end_tick number Optional end of range (default: loop end)
-- @return number Count of events updated
function Clip:set_velocity_frozen(value, start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end

	-- Use loop boundaries as default range
	if not start_tick then start_tick = self:get_playback_start() end
	if not end_tick then end_tick = self:get_playback_start() + self:get_playback_length() end

	return store:set_velocity(value, start_tick, end_tick)
end

-- Shift events in frozen source
-- @param from_tick number Shift events at or after this tick
-- @param offset number Amount to shift (positive = forward, negative = backward)
-- @return number Count of events shifted
function Clip:shift_events_frozen(from_tick, offset)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	return store:shift_events(from_tick, offset)
end

-- Insert empty time in frozen source
-- @param insert_tick number Position to insert time
-- @param duration number Amount of time to insert (in ticks)
-- @return number Count of events shifted
function Clip:insert_time_frozen(insert_tick, duration)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	return store:insert_time(insert_tick, duration)
end

-- Delete time range in frozen source
-- @param start_tick number Start of range to delete (inclusive)
-- @param end_tick number End of range to delete (exclusive)
-- @return number Count of events deleted
function Clip:delete_time_frozen(start_tick, end_tick)
	local store = self:get_edit_store()
	if not store then return 0 end
	
	return store:delete_time(start_tick, end_tick)
end

-- Revert edits: drop frozen and resume from clip bank
-- Only valid when dirty (frozen from clip)
-- @return boolean True if reverted
function Clip:revert_edits()
	-- Only valid when dirty (frozen from clip)
	if not self.buffer_frozen or not self.current_slot or not self.sources.clip_bank then
		return false
	end
	
	-- Deactivate frozen
	self.sources.frozen:deactivate()
	
	-- Switch back to clip_bank source
	self.active_source = self.sources.clip_bank
	self.sources.clip_bank:activate()
	
	-- Restore tick position from clip_bank
	self.tick = self.sources.clip_bank.tick
	
	-- Clear frozen flag (but keep current_slot - clip stays loaded)
	self.buffer_frozen = false
	self.playback_start = nil
	self.playback_length = nil
	
	-- Update monitor state
	self.track:update_monitor_state()
	
	-- Emit event
	self:emit('buffer_unfrozen', { track_id = self.track.id })
	
	if flags.debug_clip then
		print('Clip: Reverted edits, resuming from clip slot ' .. self.current_slot)
	end
	
	return true
end

-- Save edits to current slot (overwrite)
-- Only valid when dirty (frozen from clip).
-- Performs a deep copy of the frozen content so the saved clip owns its events
-- and remains independent of the live frozen-editing surface.
-- @return boolean True if saved
function Clip:save_edits_to_current_slot()
	-- Only valid when dirty
	if not self.buffer_frozen or not self.current_slot then
		return false
	end

	local frozen = self.sources.frozen
	local loop_start = frozen.loop_start
	local loop_end = frozen:get_loop_end()
	local clip_length = frozen.loop_length

	local frozen_sparse = EventStore.deep_copy_sparse(frozen.store.events, loop_start, loop_end)

	-- Remap ticks to 1-based (clips are always 1-based)
	local clip_buffer = {}
	for tick, events in pairs(frozen_sparse) do
		local remapped_tick = tick - loop_start + 1
		clip_buffer[remapped_tick] = events
	end
	
	-- Create clip data structure
	local clip_data = {
		name = self.clip_bank[self.current_slot].name or string.format('Clip %03d', self.current_slot),
		length = clip_length,
		loop_start = loop_start, -- Store original loop start
		buffer = clip_buffer,
	}
	
	-- Save to file
	local filename = string.format('track_%d_clip_%03d.lua', self.track.id, self.current_slot)
	local success = Persistence.save_clip_file(self.track.id, self.current_slot, clip_data)
	
	if success then
		-- Update clip bank entry
		self.clip_bank[self.current_slot] = {
			filename = filename,
			name = clip_data.name,
			length = clip_length,
			loop_start = loop_start,
			buffer = clip_buffer,
			playback_settings = self.clip_bank[self.current_slot].playback_settings or {},
		}
		
		-- Update clip_bank source if it exists
		if self.sources.clip_bank then
			self.sources.clip_bank:load_from_bank_entry(self.clip_bank[self.current_slot], self.current_slot)
		end
		
		-- Save bank metadata
		self:save_bank_metadata()
		
		-- Emit event
		self:emit('clip_saved', { bank_slot = self.current_slot, name = clip_data.name })
		
		-- Do NOT unfreeze - keep playing from frozen to maintain playback position
		-- User can continue editing or revert later
		
		if flags.debug_clip then
			print('Clip: Saved edits to slot ' .. self.current_slot .. ' (frozen playback continues)')
		end
		
		return true
	else
		print('Clip: Failed to save edits to slot ' .. self.current_slot)
		return false
	end
end

-- Save edits to a new slot (Save As).
-- Deep-copies the frozen content so the new bank entry is independent of the
-- ongoing frozen-editing surface.
-- @param bank_slot number The bank slot to save to
-- @return boolean True if saved
function Clip:save_edits_as(bank_slot)
	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

	if not self.buffer_frozen then
		print('Clip: No frozen content to save')
		return false
	end

	local frozen = self.sources.frozen
	local loop_start = frozen.loop_start
	local loop_end = frozen:get_loop_end()
	local clip_length = frozen.loop_length

	local frozen_sparse = EventStore.deep_copy_sparse(frozen.store.events, loop_start, loop_end)

	-- Remap ticks to 1-based (clips are always 1-based)
	local clip_buffer = {}
	for tick, events in pairs(frozen_sparse) do
		local remapped_tick = tick - loop_start + 1
		clip_buffer[remapped_tick] = events
	end
	
	-- Create clip data structure
	local clip_data = {
		name = string.format('Clip %03d', bank_slot),
		length = clip_length,
		loop_start = loop_start,
		buffer = clip_buffer,
	}
	
	-- Save to file
	local filename = string.format('track_%d_clip_%03d.lua', self.track.id, bank_slot)
	local success = Persistence.save_clip_file(self.track.id, bank_slot, clip_data)
	
	if success then
		-- Update clip bank entry
		self.clip_bank[bank_slot] = {
			filename = filename,
			name = clip_data.name,
			length = clip_length,
			loop_start = loop_start,
			buffer = clip_buffer,
			playback_settings = {},
		}
		
		-- Save bank metadata
		self:save_bank_metadata()
		
		-- Emit event
		self:emit('clip_saved', { bank_slot = bank_slot, name = clip_data.name })
		
		-- Do NOT change current_slot or unfreeze - keep playing from frozen
		-- User can continue editing or load the new slot later
		
		if flags.debug_clip then
			print('Clip: Saved edits as slot ' .. bank_slot .. ' (frozen playback continues)')
		end
		
		return true
	else
		print('Clip: Failed to save edits as slot ' .. bank_slot)
		return false
	end
end

return Clip
