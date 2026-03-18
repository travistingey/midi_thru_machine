local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local SequenceUtils = require(path_name .. 'utilities/sequence_utils')
local Registry = require(path_name .. 'utilities/registry')
local flags = require(path_name .. 'utilities/flags')

local ClipGrid = ModeComponent:new()

ClipGrid.__base = ModeComponent
ClipGrid.name = 'clipgrid'

function ClipGrid:set(o)
	self.__base.set(self, o)

	o.component = 'clip'
	o.register = {} -- No additional events to register
	o.track = o.track or 1

	o.grid = Grid:new({
		name = 'Clip Grid',
		grid_start = o.grid_start or { x = 1, y = 1 },
		grid_end = o.grid_end or { x = 16, y = 1 },
		display_start = o.display_start or { x = 1, y = 1 },
		display_end = o.display_end or { x = 16, y = 1 },
		offset = o.offset or { x = 0, y = 0 },
		midi = App.midi_grid,
	})

	-- Recording state
	self.recording_slot = nil -- Which slot is currently being recorded to
	self.recording_start_tick = nil -- When recording started (absolute tick)
	self.recording_pending = nil -- Pending recording action (queued for sync)
	self.next_recording_slot = nil -- Slot to start recording to after stopping current recording

	-- Max recording length (default 4 bars = 4 * 16 beats * 24ppqn = 1536 ticks at 24ppqn, but we use App.ppqn)
	-- Default to 4 bars: 4 * 16 beats = 64 beats = 64 * App.ppqn ticks
	self.max_recording_length = o.max_recording_length or (App.ppqn * 64)
end

function ClipGrid:enable_event()
	local clip = self:get_component()
	if not clip then return end

	-- Update row pads on enable
	self:update_row_pads()

	-- Initial grid display
	self:set_grid(clip)

	-- Listen for clip bank changes
	table.insert(self.cleanup_functions, clip:on('clip_saved', function() self:set_grid(clip) end))

	-- Listen for clip loaded
	table.insert(self.cleanup_functions, clip:on('clip_loaded', function() self:set_grid(clip) end))

	-- Listen for clip unloaded
	table.insert(self.cleanup_functions, clip:on('clip_unloaded', function() self:set_grid(clip) end))

	-- Listen for clip cleared (deleted)
	table.insert(self.cleanup_functions, clip:on('clip_cleared', function() self:set_grid(clip) end))

	-- Listen for playback state changes
	table.insert(self.cleanup_functions, clip:on('clip_playback_started', function() self:set_grid(clip) end))
	table.insert(self.cleanup_functions, clip:on('clip_playback_stopped', function() self:set_grid(clip) end))
	table.insert(self.cleanup_functions, clip:on('clip_loop_boundary', function() self:set_grid(clip) end))

	-- Listen for buffer freeze/unfreeze events from all tracks to update row pad visualization
	for track_id = 1, 8 do
		local track = App.track[track_id]
		if track and track.clip then
			-- Listen for buffer frozen event
			table.insert(
				self.cleanup_functions,
				track.clip:on('buffer_frozen', function(data)
					-- Update row pads to show frozen state
					self:update_row_pads()
				end)
			)
			-- Listen for buffer unfrozen event
			table.insert(
				self.cleanup_functions,
				track.clip:on('buffer_unfrozen', function(data)
					-- Update row pads to clear frozen state
					self:update_row_pads()
				end)
			)
		end
	end

	-- Listen for transport clock to check recording timeout
	table.insert(
		self.cleanup_functions,
		App:on('transport_event', function(data)
			if data.type == 'clock' and App.playing then
				-- Check if recording has exceeded max length
				if self.recording_slot and self.recording_start_tick and clip.buffer then
					local current_tick = clip.buffer.tick
					local loop_start = clip.buffer.buffer_start
					local loop_length = clip.buffer.buffer_length

					-- Calculate elapsed ticks since recording started
					-- Handle case where buffer has looped: recording_start_tick might be in a previous loop
					local elapsed = 0
					if current_tick >= self.recording_start_tick then
						-- Same loop: simple subtraction
						elapsed = current_tick - self.recording_start_tick
					else
						-- Buffer has looped: calculate from recording_start to loop_end, then from loop_start to current_tick
						local loop_end = loop_start + loop_length - 1
						elapsed = (loop_end - self.recording_start_tick + 1) + (current_tick - loop_start)
					end

					if elapsed >= self.max_recording_length then
						-- Max recording length reached: stop and save
						if flags.debug_clip then print('ClipGrid: Max recording length reached for slot ' .. self.recording_slot .. ' (elapsed: ' .. elapsed .. ' ticks)') end
						-- Clear any pending slot switch since we're stopping due to max length
						self.next_recording_slot = nil
						self:stop_recording_and_save(clip, self.recording_slot)
					end
				end
			end
		end)
	)
end

function ClipGrid:grid_event(clip, data)
	if not clip then return end
	if not clip.buffer then return end

	local grid = self.grid

	if data.type == 'pad' and data.state then
		local bank_slot = grid:grid_to_index(data)

		if bank_slot < 1 then return end -- Invalid slot

		-- If we're editing a loaded clip (frozen snapshot) and the user presses the pad
		-- for the currently-loaded slot, discard edits and revert back to the saved clip.
		-- This keeps "reverting" intuitive: the original pad means "restore original".
		if clip.buffer_frozen and clip.current_slot and bank_slot == clip.current_slot then
			local reverted = clip:revert_edits()
			if reverted then
				self:set_grid(clip)
				self:update_row_pads()
			end
			return
		end

		-- When buffer is frozen and slot is empty: swap behavior
		-- Tap (no alt) = save frozen buffer to clip; Alt + tap = start recording (synced)
		if clip.buffer_frozen and not clip.clip_bank[bank_slot] then
			if self.mode.alt then
				-- Alt + empty pad: start recording to this slot (synced as usual)
				self:queue_recording_start(clip, bank_slot)
				self:set_grid(clip)
				return
			else
				-- Empty pad (no alt): save frozen buffer to clip, then launch clip at same playback position
				local saved_tick = clip.tick
				local saved_playback_start = clip.playback_start
				local saved_playback_length = clip.playback_length
				local loop_end = saved_playback_start + saved_playback_length - 1
				local clip_name = string.format('Clip %03d', bank_slot)
				local success = clip:save_clip_to_bank(bank_slot, saved_playback_start, loop_end, clip_name)
				if success then
					if flags.debug_clip then print('ClipGrid: Saved frozen buffer to slot ' .. bank_slot) end
					-- Launch the new clip and restore playback position (clip ticks are 1-based)
					clip:load_clip_from_bank(bank_slot)
					local clip_length = clip.clip_bank[bank_slot] and clip.clip_bank[bank_slot].length or saved_playback_length
					local offset = (saved_tick - saved_playback_start) % saved_playback_length
					if offset < 0 then offset = offset + saved_playback_length end
					clip.tick = offset + 1
					if clip.sources.clip_bank then
						clip.sources.clip_bank.tick = clip.tick
					end
					self:set_grid(clip)
					self:update_row_pads()
				end
				return
			end
		end

		-- Not frozen + Alt + pad: save full buffer loop to bank slot (quick save without freezing)
		if not clip.buffer_frozen and self.mode.alt then
			local loop_start = clip.buffer.buffer_start
			local loop_end = clip.buffer.buffer_start + clip.buffer.buffer_length - 1
			local clip_name = string.format('Clip %03d', bank_slot)
			local success = clip:save_clip_to_bank(bank_slot, loop_start, loop_end, clip_name)
			if success then
				if flags.debug_clip then print('ClipGrid: Saved live buffer to slot ' .. bank_slot) end
				self:set_grid(clip)
				self:update_row_pads()
			end
			return
		end

		-- Check if transport is playing
		if not App.playing then
			-- Transport not playing: handle immediately (no sync quantization)
			if self.recording_slot == bank_slot then
				-- Currently recording: stop immediately
				self:stop_recording_and_save(clip, bank_slot)
			elseif clip.clip_bank[bank_slot] then
				-- Slot is occupied
				if clip.current_slot == bank_slot then
					-- Same clip is already playing: stop immediately
					clip:unload_clip()
					self:set_grid(clip)
				else
					-- Different clip: load immediately (clip playback will stop because transport is stopped)
					clip:load_clip_from_bank(bank_slot)
					self:set_grid(clip)
				end
			end
			return
		end

		-- Transport is playing
		if self.recording_slot == bank_slot then
			-- Currently recording to this slot: queue stop recording on next sync tick
			self:queue_recording_stop(clip, bank_slot)
		elseif clip.clip_bank[bank_slot] then
			-- Slot is occupied
			if clip.current_slot == bank_slot then
				-- Same clip is already playing: queue stop on next sync tick
				self:queue_clip_stop(clip, bank_slot)
			else
				-- Different clip: queue playback on next sync tick
				-- If recording is active, clip will play alongside recording (overdub)
				self:queue_clip_playback(clip, bank_slot)
			end
		else
			-- Slot is empty: queue recording start on next sync tick
			-- Any currently playing clip will be unloaded to prevent doubling
			self:queue_recording_start(clip, bank_slot)
		end

		self:set_grid(clip)
	end
end

-- Queue recording start on next sync tick
function ClipGrid:queue_recording_start(clip, bank_slot)
	if not clip or not clip.buffer then return end

	-- Cancel any pending recording
	if self.recording_pending then
		clip.sync_manager:clear('clipgrid_recording')
		self.recording_pending = nil
	end

	-- Get sync length from app-level launch_sync parameter
	-- For clip recording, we use App.launch_sync_length for quantization
	local sync_length = App.launch_sync_length or (App.ppqn * 4)

	-- If there's an active recording to a different slot, stop and save it first
	-- This ensures the previous recording is saved before starting a new one
	-- Also check if we're already switching to a different slot (next_recording_slot is set)
	local current_recording_slot = self.recording_slot or self.next_recording_slot
	if current_recording_slot and current_recording_slot ~= bank_slot then
		if flags.debug_clip then
			print('ClipGrid: Stopping current recording to slot ' .. (self.recording_slot or 'pending') .. ' before starting new recording to slot ' .. bank_slot)
		end
		-- Store the new slot to start after stopping
		self.next_recording_slot = bank_slot
		-- If there's an active recording (not just pending), queue stop for it
		if self.recording_slot then
			self:queue_recording_stop(clip, self.recording_slot)
		end
		-- Don't queue the start here - it will be queued after the stop completes
		return
	end

	if flags.debug_clip then
		local current_tick = App.tick or 1
		local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
		print('ClipGrid: Queue recording start for slot ' .. bank_slot)
		print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
		print('  Sync length: ' .. sync_length)
		print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')
	end

	-- Create action to start recording
	local action_fn = function(component, action_data)
		if flags.debug_clip then
			local exec_tick = App.tick or 1
			print('ClipGrid: Executing recording start for slot ' .. action_data.bank_slot)
			print('  Execution App.tick: ' .. exec_tick .. ', buffer.tick: ' .. component.buffer.tick)
		end
		self:start_recording(component, action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Queue in the 'clipgrid_recording' slot using SyncManager
	clip.sync_manager:queue('clipgrid_recording', action_fn, action_data, sync_length)
	self.recording_pending = { bank_slot = bank_slot }
end

-- Start recording to a bank slot
-- Called on sync tick - use App.tick (sync-aligned) and align buffer.tick to it
function ClipGrid:start_recording(clip, bank_slot)
	if not clip or not clip.buffer then return end

	-- Use App.tick which is sync-aligned when the action executes
	-- App.tick is 1-based (first clock = tick 1)
	local app_tick = App.tick or 1
	local recording_start_tick = app_tick

	if flags.debug_clip then
		-- Verify sync alignment (use app-level launch_sync parameter)
		local sync_length = App.launch_sync_length or (App.ppqn * 4)
		local boundary = sync_length
		local relative_tick = recording_start_tick - 1
		local is_aligned = (relative_tick % boundary == 0)

		print('ClipGrid: Start recording slot ' .. bank_slot)
		print('  App.tick: ' .. app_tick .. ', buffer.tick: ' .. clip.buffer.tick)
		print('  Using recording_start_tick: ' .. recording_start_tick .. ' (from App.tick)')
		print('  Boundary: ' .. boundary .. ', aligned: ' .. tostring(is_aligned))
		if not is_aligned then
			print('  WARNING: App.tick not aligned to sync boundary!')
			print('  Relative tick: ' .. relative_tick .. ', remainder: ' .. (relative_tick % boundary))
		end
	end

	-- Align buffer.tick to the sync-aligned App.tick
	-- This ensures buffer recording starts at the correct sync boundary
	clip.buffer.tick = recording_start_tick

	-- Unload any currently playing clip when starting a new recording to an empty slot
	-- This prevents doubling: the clip would play while new input is being recorded
	-- If user wants overdub, they should record to the same slot that's already playing
	if clip.current_slot then clip:unload_clip() end

	-- Store recording state
	self.recording_slot = bank_slot
	self.recording_start_tick = recording_start_tick
	self.recording_pending = nil

	-- Update grid to show recording state
	self:set_grid(clip)
end

-- Queue recording stop on next sync tick (when transport is playing)
function ClipGrid:queue_recording_stop(clip, bank_slot)
	if not clip or not clip.buffer then return end
	if self.recording_slot ~= bank_slot then return end

	-- Get sync length from app-level launch_sync parameter
	local sync_length = App.launch_sync_length or (App.ppqn * 4)

	if flags.debug_clip then
		local current_tick = App.tick or 1
		local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
		print('ClipGrid: Queue recording stop for slot ' .. bank_slot)
		print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
		print('  Recording started at tick: ' .. (self.recording_start_tick or 'unknown'))
		print('  Sync length: ' .. sync_length)
		print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')
	end

	-- Create action to stop recording and save
	local action_fn = function(component, action_data)
		if flags.debug_clip then
			local exec_tick = App.tick or 1
			print('ClipGrid: Executing recording stop for slot ' .. action_data.bank_slot)
			print('  Execution App.tick: ' .. exec_tick .. ', buffer.tick: ' .. component.buffer.tick)
		end
		self:stop_recording_and_save(component, action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Queue in the 'clipgrid_recording_stop' slot using SyncManager
	clip.sync_manager:queue('clipgrid_recording_stop', action_fn, action_data, sync_length)
end

-- Stop recording and save clip to bank slot
-- Called immediately when transport is stopped, or on sync tick when transport is playing
function ClipGrid:stop_recording_and_save(clip, bank_slot)
	if not clip or not clip.buffer then return end
	if self.recording_slot ~= bank_slot then return end

	local recording_start_tick = self.recording_start_tick
	if not recording_start_tick then return end

	-- Use buffer.tick to get the last tick that was actually recorded
	local buffer_tick = clip.buffer.tick
	local last_recorded_tick = buffer_tick - 1
	local loop_end = last_recorded_tick

	-- Get sync length for alignment (use app-level launch_sync parameter)
	local sync_length = App.launch_sync_length or (App.ppqn * 4)

	if flags.debug_clip then
		local is_aligned = (last_recorded_tick % sync_length == 0)
		print('ClipGrid: Stop recording slot ' .. bank_slot)
		print('  Last recorded tick: ' .. last_recorded_tick .. ' (buffer.tick - 1)')
		print('  Recording started at: ' .. recording_start_tick)
		print('  Sync length: ' .. sync_length .. ', aligned: ' .. tostring(is_aligned))
	end

	-- Clamp to max recording length
	local max_end_tick = recording_start_tick + self.max_recording_length - 1
	loop_end = math.min(loop_end, max_end_tick)

	-- Ensure we have at least 1 tick of data
	if loop_end < recording_start_tick then loop_end = recording_start_tick end

	-- Ensure loop_end doesn't exceed buffer's current loop end
	local buffer_loop_end = clip.buffer.buffer_start + clip.buffer.buffer_length - 1
	loop_end = math.min(loop_end, buffer_loop_end)

	-- Ensure clip length is a multiple of sync_length to prevent drift
	local raw_length = loop_end - recording_start_tick + 1
	local sync_units = math.floor(raw_length / sync_length)
	local remainder = raw_length % sync_length

	if remainder ~= 0 then
		loop_end = recording_start_tick + (sync_units * sync_length) - 1
		if flags.debug_clip then print('ClipGrid: Adjusted loop_end to ' .. loop_end .. ' for sync alignment') end
	end

	-- Save clip to bank
	local clip_name = string.format('Clip %03d', bank_slot)
	local success = clip:save_clip_to_bank(bank_slot, recording_start_tick, loop_end, clip_name)

	if success then
		if flags.debug_clip then
			local clip_length = loop_end - recording_start_tick + 1
			print('ClipGrid: Saved clip to slot ' .. bank_slot .. ' (' .. clip_length .. ' ticks)')
		end

		-- Auto-load and play the clip that was just saved
		if App.playing then
			self:queue_clip_playback(clip, bank_slot)
		else
			clip:load_clip_from_bank(bank_slot)
		end

		-- Clear recording state
		self.recording_slot = nil
		self.recording_start_tick = nil

		-- If there's a next recording slot queued, start recording to it now
		-- This happens when switching from one recording slot to another
		local next_slot = self.next_recording_slot
		if next_slot then
			self.next_recording_slot = nil
			if flags.debug_clip then
				print('ClipGrid: Starting queued recording to slot ' .. next_slot .. ' after stopping slot ' .. bank_slot)
			end
			-- Queue the start for the next sync tick
			self:queue_recording_start(clip, next_slot)
		end

		-- Update grid
		self:set_grid(clip)
	else
		print('ClipGrid: Failed to save clip to slot ' .. bank_slot)
	end
end

-- Queue clip playback on next sync tick
function ClipGrid:queue_clip_playback(clip, bank_slot)
	if not clip or not clip.clip_bank[bank_slot] then return end

	-- If same clip is already playing, don't queue playback
	if clip.current_slot == bank_slot then return end

	-- Get sync length from app-level launch_sync parameter
	local sync_length = App.launch_sync_length or (App.ppqn * 4)

	if flags.debug_clip then
		local current_tick = App.tick or 1
		local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
		print('ClipGrid: Queue clip playback for slot ' .. bank_slot)
		print('  Current App.tick: ' .. current_tick .. ', sync tick: ' .. next_sync_tick)
	end

	-- Create action to load and play clip
	local action_fn = function(component, action_data)
		if flags.debug_clip then print('ClipGrid: Executing clip playback for slot ' .. action_data.bank_slot .. ' at App.tick: ' .. (App.tick or 1)) end
		component:load_clip_from_bank(action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Queue in the 'clipgrid_playback' slot using SyncManager
	clip.sync_manager:queue('clipgrid_playback', action_fn, action_data, sync_length)
end

-- Queue clip stop on next sync tick
function ClipGrid:queue_clip_stop(clip, bank_slot)
	if not clip or clip.current_slot ~= bank_slot then return end

	-- Get sync length from app-level launch_sync parameter
	local sync_length = App.launch_sync_length or (App.ppqn * 4)

	if flags.debug_clip then
		local current_tick = App.tick or 1
		local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
		print('ClipGrid: Queue clip stop for slot ' .. bank_slot)
		print('  Current App.tick: ' .. current_tick .. ', sync tick: ' .. next_sync_tick)
	end

	-- Create action to unload clip (stops playback)
	local action_fn = function(component, action_data)
		if flags.debug_clip then print('ClipGrid: Executing clip stop for slot ' .. action_data.bank_slot .. ' at App.tick: ' .. (App.tick or 1)) end
		component:unload_clip()
		-- Update grid display
		if self.set_grid then self:set_grid(component) end
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Queue in the 'clipgrid_stop' slot using SyncManager
	clip.sync_manager:queue('clipgrid_stop', action_fn, action_data, sync_length)
end

function ClipGrid:transport_event(clip, data)
	if not clip then return end

	if data.type == 'stop' then
		-- Transport stopped: ensure state is updated immediately
		-- If recording was active, stop it immediately (no sync quantization needed)
		if self.recording_slot then
			-- Clear any pending slot switch since transport stopped
			self.next_recording_slot = nil
			self:stop_recording_and_save(clip, self.recording_slot)
		end
		-- Update grid display
		self:set_grid(clip)
	elseif data.type == 'start' then
		-- Transport started: update grid display
		self:set_grid(clip)
	end
end

function ClipGrid:set_grid(clip)
	if not clip then return end

	local grid = self.grid
	local track = clip.track

	if not track then
		grid:reset()
		grid:refresh('ClipGrid:set_grid')
		return
	end

	grid:for_each(function(s, x, y, i)
		local bank_slot = i
		local clip_entry = clip.clip_bank[bank_slot]

		-- Default: empty slot
		s.led[x][y] = { 1, 1, 1 } -- Dim white for empty

		if self.recording_slot == bank_slot then
			-- Currently recording: blink red
			s.led[x][y] = { 3, true } -- Red, blinking
		elseif self.recording_pending and self.recording_pending.bank_slot == bank_slot then
			-- Recording queued: dim red
			s.led[x][y] = { 3, 3, 3 } -- Dim red
		elseif clip_entry then
			-- Slot has clip: show color based on slot number
			-- Only highlight the grid "active clip" when the clip bank is the active playback source.
			-- When the buffer is frozen for editing, `current_slot` may still be set, but playback
			-- is coming from `sources.frozen` (or scrub). In that case, we should not show
			-- the saved clip as "currently playing" on the clip grid.
			local playing_slot = nil
			if clip.active_source == clip.sources.clip_bank then
				playing_slot = clip.current_slot
			end

			if playing_slot == bank_slot then
				-- Active playback from clip bank: bright color
				s.led[x][y] = Grid.rainbow_on[(bank_slot - 1) % #Grid.rainbow_on + 1]
			else
				-- Loaded but not playing: dim color
				s.led[x][y] = Grid.rainbow_off[(bank_slot - 1) % #Grid.rainbow_off + 1]
			end
		end
	end)

	grid:refresh('ClipGrid:set_grid')
end

-- Handle row pad events for track selection
function ClipGrid:row_event(data)
	if data.state then
		-- If alt mode is active, unfreeze buffer for that track
		if self.mode.alt then
			local track = App.track[data.row]
			if track and track.clip and track.clip.buffer_frozen then
				track.clip:unfreeze_buffer()
				if flags.debug_clip then print('Buffer unfrozen for track ' .. data.row) end
				-- Update row pads to reflect unfrozen state
				self:update_row_pads()
				-- Refresh grid if this is the current track
				if data.row == App.current_track then
					local clip = self:get_component()
					if clip then self:set_grid(clip) end
				end
				return -- Don't proceed with track switching
			end
		end

		-- Update track selection
		self.track = data.row
		App.current_track = data.row

		-- Update grid to show new track's clip bank
		local clip = self:get_component()
		if clip then self:set_grid(clip) end

		-- Update row pads to reflect the change
		self:update_row_pads()
	end
end

-- Update row pads to show current track
-- Frozen tracks: rainbow_off[10] when not selected, rainbow_on[10] when selected
function ClipGrid:update_row_pads()
	if not self.mode or not self.mode.row_pads then return end

	local Grid = require('Foobar/lib/grid')
	local current_track = App.current_track or 1

	-- Reset all row pads first
	self.mode.row_pads:reset()

	-- Update row pads for all tracks
	for track_id = 1, 8 do
		local track = App.track[track_id]
		if track then
			local row_y = 9 - track_id
			local is_frozen = track.clip and track.clip.buffer_frozen or false
			local is_selected = (track_id == current_track)

			if is_frozen then
				-- Frozen track: use rainbow color index 10
				if is_selected then
					-- Selected frozen track: bright color
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_on[10]
				else
					-- Unselected frozen track: dim color
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_off[10]
				end
			elseif is_selected then
				-- Current track (not frozen): white (brightness 1)
				self.mode.row_pads.led[9][row_y] = 1
			end
		end
	end

	-- Refresh both grid and display
	self.mode.row_pads:refresh('ClipGrid:update_row_pads')
	App.screen_dirty = true
end

return ClipGrid
