local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local SequenceUtils = require(path_name .. 'utilities/sequence_utils')
local Registry = require(path_name .. 'utilities/registry')

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
						print('ClipGrid: Max recording length reached for slot ' .. self.recording_slot .. ' (elapsed: ' .. elapsed .. ' ticks)')
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
			-- If a clip is currently playing, it will continue playing during recording (overdub)
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
		clip.sync_action_queue:clear_action()
		self.recording_pending = nil
	end

	-- Get sync length from track parameter (respects user's action_sync setting)
	-- For clip recording, we use the track's action_sync_length parameter for quantization
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local current_tick = App.tick or 1
	-- Use sync_length as the boundary for clip recording quantization
	local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
	local boundary = sync_length -- Use sync_length directly for clip recording

	print('ClipGrid: Queue recording start for slot ' .. bank_slot)
	print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
	print('  Sync length: ' .. sync_length .. ', boundary: ' .. boundary)
	print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')

	-- Create action to start recording
	local action_fn = function(component, action_data)
		local exec_tick = App.tick or 1
		print('ClipGrid: Executing recording start for slot ' .. action_data.bank_slot)
		print('  Execution App.tick: ' .. exec_tick .. ', buffer.tick: ' .. component.buffer.tick)
		self:start_recording(component, action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Create a temporary sync action queue with the correct sync_length for clip recording
	-- The clip's sync_action_queue uses action_sync_length from track parameter
	local function get_sync_length_fn(component) return sync_length end
	local temp_queue = SequenceUtils.create_sync_action_queue(clip, get_sync_length_fn)
	temp_queue:queue_action(action_fn, action_data)
	self.recording_pending = { bank_slot = bank_slot }

	-- Store the temp queue so it can execute
	clip._clipgrid_sync_queue = temp_queue
end

-- Start recording to a bank slot
-- Called on sync tick - use App.tick (sync-aligned) and align buffer.tick to it
function ClipGrid:start_recording(clip, bank_slot)
	if not clip or not clip.buffer then return end

	-- Use App.tick which is sync-aligned when the action executes
	-- App.tick is 1-based (first clock = tick 1)
	local app_tick = App.tick or 1
	local recording_start_tick = app_tick

	-- Verify sync alignment (use track's action_sync_length parameter)
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local boundary = sync_length -- Use sync_length directly for clip recording
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

	-- Align buffer.tick to the sync-aligned App.tick
	-- This ensures buffer recording starts at the correct sync boundary
	clip.buffer.tick = recording_start_tick

	-- Arm the track for recording
	local track = clip.track
	if track then Registry.set('track_' .. track.id .. '_armed', 1, 'clipgrid_recording') end

	-- Set loop boundaries for recording
	-- Start at sync-aligned tick, end at max recording length
	-- This ensures recording stays within bounds and can be saved correctly
	local loop_end = recording_start_tick + self.max_recording_length - 1

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

	-- Get sync length from track parameter (respects user's action_sync setting)
	-- For clip recording, we use the track's action_sync_length parameter for quantization
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local current_tick = App.tick or 1
	-- Use sync_length as the boundary for clip recording quantization
	local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
	local boundary = sync_length -- Use sync_length directly for clip recording

	print('ClipGrid: Queue recording stop for slot ' .. bank_slot)
	print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
	print('  Recording started at tick: ' .. (self.recording_start_tick or 'unknown'))
	print('  Sync length: ' .. sync_length .. ', boundary: ' .. boundary)
	print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')

	-- Create action to stop recording and save
	local action_fn = function(component, action_data)
		local exec_tick = App.tick or 1
		print('ClipGrid: Executing recording stop for slot ' .. action_data.bank_slot)
		print('  Execution App.tick: ' .. exec_tick .. ', buffer.tick: ' .. component.buffer.tick)
		self:stop_recording_and_save(component, action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Queue the action
	clip.sync_action_queue:queue_action(action_fn, action_data)
end

-- Stop recording and save clip to bank slot
-- Called immediately when transport is stopped, or on sync tick when transport is playing
function ClipGrid:stop_recording_and_save(clip, bank_slot)
	if not clip or not clip.buffer then return end
	if self.recording_slot ~= bank_slot then return end

	local recording_start_tick = self.recording_start_tick
	if not recording_start_tick then return end

	-- Use buffer.tick to get the last tick that was actually recorded
	-- buffer.tick increments AFTER recording each clock tick, so the last recorded tick is buffer.tick - 1
	-- We need to use buffer.tick (not App.tick) to ensure we capture all recorded data
	local buffer_tick = clip.buffer.tick
	local last_recorded_tick = buffer_tick - 1

	-- Always use last_recorded_tick as the base (not App.tick)
	-- App.tick points to the next tick to be processed, not the last recorded tick
	-- Using last_recorded_tick ensures we match the behavior of menu/frozen_buffer saves
	-- The sync alignment logic below will handle rounding down if needed
	local loop_end = last_recorded_tick

	-- Get sync length for alignment verification and later sync adjustment
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local boundary = sync_length -- Use sync_length directly for clip recording

	-- Verify sync alignment
	local is_aligned = (last_recorded_tick % boundary == 0)

	print('ClipGrid: Stop recording slot ' .. bank_slot)
	print('  App.tick: ' .. App.tick .. ', buffer.tick: ' .. buffer_tick)
	print('  Last recorded tick: ' .. last_recorded_tick .. ' (buffer.tick - 1)')
	print('  Using loop_end: ' .. loop_end .. ' (sync-aligned from last recorded)')
	print('  Recording started at: ' .. recording_start_tick)
	print('  Boundary: ' .. boundary .. ', aligned: ' .. tostring(is_aligned))
	if not is_aligned then
		print('  WARNING: loop_end not aligned to sync boundary!')
		print('  Relative tick: ' .. relative_end_tick .. ', remainder: ' .. (relative_end_tick % boundary))
	end

	-- Clamp to max recording length
	local max_end_tick = recording_start_tick + self.max_recording_length - 1
	loop_end = math.min(loop_end, max_end_tick)

	-- Ensure we have at least 1 tick of data (minimum clip length)
	if loop_end < recording_start_tick then loop_end = recording_start_tick end

	-- Ensure loop_end doesn't exceed buffer's current loop end (set during recording start)
	local buffer_loop_end = clip.buffer.buffer_start + clip.buffer.buffer_length - 1
	loop_end = math.min(loop_end, buffer_loop_end)

	-- Ensure loop_end creates a clip length that is a multiple of sync_length
	-- This prevents drift by ensuring the clip loops perfectly
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local raw_length = loop_end - recording_start_tick + 1
	local sync_units = math.floor(raw_length / sync_length)
	local remainder = raw_length % sync_length

	-- If there's a remainder, adjust loop_end to make the length a perfect multiple
	if remainder ~= 0 then
		-- Round down to the previous sync boundary to ensure perfect alignment
		-- This might cut off a few ticks, but prevents drift
		loop_end = recording_start_tick + (sync_units * sync_length) - 1
		print('ClipGrid: Adjusted loop_end from ' .. (recording_start_tick + raw_length - 1) .. ' to ' .. loop_end .. ' to ensure sync alignment')
	end
	print('STOP AND SAVE--------------------------------')

	-- Save clip to bank
	local clip_name = string.format('Clip %03d', bank_slot)
	local success = clip:save_clip_to_bank(bank_slot, recording_start_tick, loop_end, clip_name)

	if success then
		local clip_length = loop_end - recording_start_tick + 1
		local expected_bars = clip_length / (App.ppqn * 4) -- 1 bar = 4 beats * App.ppqn ticks
		local final_sync_units = clip_length / sync_length
		local final_remainder = clip_length % sync_length

		print('ClipGrid: Saved clip to slot ' .. bank_slot)
		print('  Tick range: ' .. recording_start_tick .. ' to ' .. loop_end .. ' (inclusive)')
		print('  Clip length: ' .. clip_length .. ' ticks')
		print('  Sync length: ' .. sync_length .. ' ticks (action_sync setting)')
		print('  Expected bars: ' .. string.format('%.2f', expected_bars) .. ' bars')
		print('  Sync units: ' .. string.format('%.2f', final_sync_units) .. ' units')
		print('  Remainder: ' .. final_remainder .. ' ticks (should be 0 for perfect sync alignment)')
		if final_remainder ~= 0 then
			print('  WARNING: Clip length is NOT a multiple of sync_length! This will cause drift.')
		else
			print('  ✓ Clip length is perfectly aligned to sync boundaries')
		end

		-- Disarm track
		local track = clip.track
		if track then Registry.set('track_' .. track.id .. '_armed', 0, 'clipgrid_recording_done') end

		-- Auto-load and play the clip that was just saved
		-- This ensures playback starts immediately after recording
		if App.playing then
			-- Queue playback on next sync tick (or start immediately if already on sync boundary)
			self:queue_clip_playback(clip, bank_slot)
		else
			-- Transport not playing: just load the clip (will play when transport starts)
			clip:load_clip_from_bank(bank_slot)
		end

		-- Clear recording state
		self.recording_slot = nil
		self.recording_start_tick = nil

		-- Update grid
		self:set_grid(clip)
	else
		print('ClipGrid: Failed to save clip to slot ' .. bank_slot)
	end
end

-- Queue clip playback on next sync tick
function ClipGrid:queue_clip_playback(clip, bank_slot)
	if not clip or not clip.clip_bank[bank_slot] then return end

	-- If same clip is already playing, don't queue playback (should use queue_clip_stop instead)
	if clip.current_slot == bank_slot then
		-- Already playing this clip: no action needed (caller should use queue_clip_stop)
		return
	end

	-- Get sync length from track parameter (respects user's action_sync setting)
	-- For clip playback, we use the track's action_sync_length parameter for quantization
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local current_tick = App.tick or 1
	-- Use sync_length as the boundary for clip playback quantization
	local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
	local boundary = sync_length -- Use sync_length directly for clip playback

	print('ClipGrid: Queue clip playback for slot ' .. bank_slot)
	print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
	print('  Sync length: ' .. sync_length .. ', boundary: ' .. boundary)
	print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')

	-- Create action to load and play clip
	local action_fn = function(component, action_data)
		local exec_tick = App.tick or 1
		print('ClipGrid: Executing clip playback for slot ' .. action_data.bank_slot .. ' at App.tick: ' .. exec_tick)
		component:load_clip_from_bank(action_data.bank_slot)
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Create a temporary sync action queue with the correct sync_length for clip playback
	-- The clip's sync_action_queue uses action_sync_length from track parameter
	local function get_sync_length_fn(component) return sync_length end
	local temp_queue = SequenceUtils.create_sync_action_queue(clip, get_sync_length_fn)
	temp_queue:queue_action(action_fn, action_data)

	-- Store the temp queue so it can execute
	clip._clipgrid_sync_queue = temp_queue
end

-- Queue clip stop on next sync tick
function ClipGrid:queue_clip_stop(clip, bank_slot)
	if not clip or clip.current_slot ~= bank_slot then return end

	-- Get sync length from track parameter (respects user's action_sync setting)
	local sync_length = SequenceUtils.get_sync_length(clip.buffer, clip.action_sync_length)
	local current_tick = App.tick or 1
	local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)

	print('ClipGrid: Queue clip stop for slot ' .. bank_slot)
	print('  Current App.tick: ' .. current_tick .. ', buffer.tick: ' .. clip.buffer.tick)
	print('  Sync length: ' .. sync_length)
	print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')

	-- Create action to unload clip (stops playback)
	local action_fn = function(component, action_data)
		local exec_tick = App.tick or 1
		print('ClipGrid: Executing clip stop for slot ' .. action_data.bank_slot .. ' at App.tick: ' .. exec_tick)
		component:unload_clip()
		-- Emit event so grid can update
		if self.set_grid then self:set_grid(component) end
	end

	local action_data = {
		bank_slot = bank_slot,
	}

	-- Create a temporary sync action queue with the correct sync_length for clip stop
	local function get_sync_length_fn(component) return sync_length end
	local temp_queue = SequenceUtils.create_sync_action_queue(clip, get_sync_length_fn)
	temp_queue:queue_action(action_fn, action_data)

	-- Store the temp queue so it can execute
	clip._clipgrid_sync_queue = temp_queue
end

function ClipGrid:transport_event(clip, data)
	if not clip then return end

	if data.type == 'stop' then
		-- Transport stopped: ensure state is updated immediately
		-- If recording was active, stop it immediately (no sync quantization needed)
		if self.recording_slot then self:stop_recording_and_save(clip, self.recording_slot) end
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
			if clip.current_slot == bank_slot then
				-- Currently playing: bright color
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
			if track.armed then
				-- Armed track: use rainbow colors
				if track_id == current_track then
					-- Selected and armed: bright color
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_on[track_id]
				else
					-- Armed but not selected: dim color
					self.mode.row_pads.led[9][row_y] = Grid.rainbow_off[track_id]
				end
			elseif track_id == current_track then
				-- Current track but not armed: white (brightness 1)
				self.mode.row_pads.led[9][row_y] = 1
			end
		end
	end

	-- Refresh both grid and display
	self.mode.row_pads:refresh('ClipGrid:update_row_pads')
	App.screen_dirty = true
end

return ClipGrid
