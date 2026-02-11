local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')
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
	self.playback_start = nil -- Playback loop start (independent of buffer.buffer_start)
	self.playback_length = nil -- Playback loop length

	-- Scrub playback state (redundant - use sources.scrub for state)
	-- Keeping scrub_mode for quick checks, but prefer active_source == sources.scrub
	self.scrub_mode = false

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
	if self.current_slot and self.clip_bank[self.current_slot] then
		-- Return loaded clip length
		local clip_entry = self.clip_bank[self.current_slot]
		if clip_entry.length then return clip_entry.length end
		-- Fallback: calculate from buffer if length not stored
		-- Clips are 1-based, so the max_tick is the last tick (inclusive length)
		if clip_entry.buffer then
			local max_tick = 0
			for tick, _ in pairs(clip_entry.buffer) do
				if tick > max_tick then max_tick = tick end
			end
			-- Return max_tick as the length (1-based inclusive: tick 1 to tick max_tick = max_tick ticks)
			return max_tick
		end
		return 0
	else
		-- Return playback loop length if buffer is frozen and playback_length is set, otherwise buffer length
		if self.buffer_frozen and self.playback_length then
			return self.playback_length
		elseif self.buffer then
			return self.buffer.buffer_length
		end
		return 0
	end
end

-- Get the current playback start (for loop wrapping)
-- Returns the start tick for the current playback source
function Clip:get_playback_start()
	if self.current_slot and self.clip_bank[self.current_slot] then
		-- Clips are stored with ticks starting at 1, so they start at tick 1
		return 1
	else
		-- Return playback loop start if buffer is frozen and playback_start is set, otherwise buffer start
		if self.buffer_frozen and self.playback_start then
			return self.playback_start
		elseif self.buffer then
			return self.buffer.buffer_start
		end
		return 0
	end
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

-- Freeze the buffer (create snapshot of current playback range)
function Clip:freeze_buffer()
	if not self.buffer or not self.playback_start or not self.playback_length then return end

	-- Use FrozenBufferSource to create snapshot
	self.sources.frozen:freeze_from_buffer(self.buffer, self.playback_start, self.playback_length)
	self.sources.frozen:activate()
	self.active_source = self.sources.frozen

	self.buffer_frozen = true
	if flags.debug_clip then
		local loop_end = self.playback_start + self.playback_length - 1
		print('Clip: Buffer frozen at playback range ' .. self.playback_start .. '-' .. loop_end)
	end

	-- Kill notes when freezing buffer to prevent stuck notes from previous playback
	if App.playing then self:kill_notes() end

	-- Update monitor state to respect monitoring settings (AUTO mutes)
	self.track:update_monitor_state()
end

-- Unfreeze the buffer (clear frozen snapshot)
function Clip:unfreeze_buffer()
	local was_frozen = self.buffer_frozen

	-- Deactivate FrozenBufferSource
	self.sources.frozen:deactivate()
	if self.active_source == self.sources.frozen then self.active_source = nil end

	self.buffer_frozen = false
	-- Reset playback loop boundaries
	self.playback_start = nil
	self.playback_length = nil

	-- Kill notes when unfreezing buffer to prevent stuck notes from frozen playback
	if was_frozen and App.playing then self:kill_notes() end

	-- Update monitor state to restore input monitoring
	self.track:update_monitor_state()
end

-- Set playback loop boundaries (for frozen buffer playback)
function Clip:set_playback_loop(start_tick, length)
	local new_end = start_tick + length - 1

	self.playback_start = start_tick
	self.playback_length = length

	-- If buffer is frozen and loop boundaries changed, update FrozenBufferSource
	if self.buffer_frozen and self.buffer and self.buffer.buffer then
		-- Clear entries that are now outside the new range
		for tick, _ in pairs(self.sources.frozen.events) do
			if tick < start_tick or tick > new_end then self.sources.frozen.events[tick] = nil end
		end
		-- Add new entries from buffer for the new range
		for tick = start_tick, new_end do
			if self.buffer.buffer[tick] and not self.sources.frozen.events[tick] then self.sources.frozen.events[tick] = self.buffer.buffer[tick] end
		end
	end

	if flags.debug_clip then print('Clip: Playback loop set to ' .. start_tick .. '-' .. new_end) end
end

-- Execute pending sync actions (should be called on each clock tick)
function Clip:execute_sync_actions() self.sync_manager:execute_all() end

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
			-- Handle clip playback modes at loop boundary
			-- Kill all active notes before looping to prevent stuck notes
			self:kill_notes()

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

			-- Now handle boundary wrapping (after playing current position)
			if self.sources.scrub.loop_enabled and next_scrub_tick > scrub_end then
				-- Loop back to scrub start
				self:kill_notes()
				self.sources.scrub.tick = self.sources.scrub.loop_start
			elseif not self.sources.scrub.loop_enabled then
				-- Play-thru mode
				if next_scrub_tick > scrub_end then
					-- Completed one pass through scrub range
					if not self.buffer_loop then
						-- One-shot mode: stop scrub after one loop through range
						self:kill_notes()
						self:stop_scrub()
					else
						-- Continuous loop mode: continue playing through full buffer
						-- Wrap at buffer end
						local buffer_end = self.buffer.buffer_start + self.buffer.buffer_length - 1
						if next_scrub_tick > buffer_end then
							self:kill_notes()
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

		-- Don't record clip playback events back into buffer
		-- Buffer records continuously from live input only
		-- Recording playback events would cause feedback loops and doubling
		-- Clip playback is separate from buffer recording - they don't interact
	end
end

-- Send note_off for all active buffer notes (prevents stuck notes)
function Clip:kill_notes()
	if not self.track.output_device then return end
	self.track.output_device:kill()
end

-- Scrub playback: temporarily play a range of the buffer
-- Creates shallow copy of buffer range for isolated playback
-- Always blocks input regardless of monitoring setting
-- loop_mode: true = loop the range, false = play through once then stop
function Clip:start_scrub(start_tick, end_tick, loop_mode, initial_tick)
	-- Kill any currently playing buffer notes before scrub
	self:kill_notes()

	-- Default initial_tick to start_tick if not provided
	initial_tick = initial_tick or start_tick

	-- Initialize ScrubSource and activate it
	if self.buffer then
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
	if self.buffer then self.sources.scrub:update_range(self.buffer, start_tick, end_tick) end
end

-- Stop scrub and restore normal playback
function Clip:stop_scrub()
	if self.active_source ~= self.sources.scrub then return end

	-- Kill any scrub notes
	self:kill_notes()

	-- Deactivate ScrubSource
	self.sources.scrub:deactivate()
	if self.active_source == self.sources.scrub then self.active_source = nil end

	-- Clear scrub_mode flag
	self.scrub_mode = false

	-- Clear any pending scrub action
	self.sync_manager:clear('scrub')

	-- Restore input monitoring
	self.track:update_monitor_state()
end

--==============================================================================
-- Clip Bank Management
--==============================================================================

--- Save a clip from buffer to bank slot
-- @param bank_slot number The bank slot (positive integer)
-- @param loop_start number The start tick of the loop
-- @param loop_end number The end tick of the loop
-- @param name string Optional name for the clip
-- @return boolean True if save succeeded
function Clip:save_clip_to_bank(bank_slot, loop_start, loop_end, name)
	if not self.buffer then
		print('Clip: Cannot save clip - buffer not available')
		return false
	end

	if bank_slot < 1 then
		print('Clip: Invalid bank slot ' .. bank_slot .. ' (must be positive)')
		return false
	end

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

	-- Extract clip data from buffer or frozen buffer
	local clip_buffer = {}
	local clip_length = loop_end - loop_start + 1

	-- Copy events from source buffer, remapping ticks to start at 1
	for tick, events in pairs(source_buffer) do
		if tick >= loop_start and tick <= loop_end then
			-- Remap tick: tick - loop_start + 1 (so clip starts at tick 1)
			local remapped_tick = tick - loop_start + 1
			-- Attempting shallow copy to improve performance
			-- Assumption is that the buffer is only written to once per cycle
			clip_buffer[remapped_tick] = events
		end
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

		-- Unfreeze buffer after saving (if it was frozen)
		-- This restores normal monitoring behavior (input can be heard when no clip is playing)
		if self.buffer_frozen then
			self:unfreeze_buffer()
			-- Update monitor state to restore input monitoring
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

	-- If currently playing, stop playback
	if self.current_slot == bank_slot then
		self.current_slot = nil
		-- Sync clip.tick to buffer.tick (buffer is continuously running, don't reset)
		if self.buffer then self.tick = self.buffer.tick end
	end

	-- Delete the clip file if it exists
	if self.clip_bank[bank_slot] and self.clip_bank[bank_slot].filename then Persistence.delete_clip_file(self.track.id, self.clip_bank[bank_slot].filename) end

	-- Remove from clip bank
	self.clip_bank[bank_slot] = nil

	-- Save bank metadata
	self:save_bank_metadata()

	-- Emit event for mode components
	self:emit('clip_cleared', { bank_slot = bank_slot })

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

return Clip
