--==============================================================================
-- App.lua - Main Application Controller
--
-- This file instantiates the App class, which manages device connections,
-- transport, tracks, modes, and the user interface.

--==============================================================================
-- TODO:
-- Remove App.midi_out and move panic function to device mangement
-- Integrate LaunchControl within DeviceManager?
-- Maybe move LaunchPad within DeviceManager?

--==============================================================================
-- Dependencies and Global Variables
--==============================================================================
local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local Track = require(path_name .. 'components/app/track')
local Scale = require(path_name .. 'components/track/scale')
local Output = require(path_name .. 'components/track/output')
local Mode = require(path_name .. 'components/app/mode')
local musicutil = require(path_name .. 'musicutil-extended')
local DeviceManager = require(path_name .. 'components/app/devicemanager')
local LaunchControl = require(path_name .. 'launchcontrol')
local UI = require(path_name .. 'ui')
local flags = require(path_name .. 'utilities/flags')
local trace = require(path_name .. 'utilities/trace_cli')
local Registry = require(path_name .. 'utilities/registry')
local Persistence = require(path_name .. 'utilities/persistence')
local LATCH_CC = 64

--==============================================================================
-- Class Definition: App
--==============================================================================
local App = {}
App.__index = App

-- Helper function to safely cancel a coroutine
-- Handles cases where coroutine may have already completed
local function safe_cancel(coro)
	if coro then
		local ok, err = pcall(clock.cancel, coro)
		if not ok and App.DEBUG_TIMING then print('Warning: Failed to cancel coroutine:', err) end
	end
end

--==============================================================================
-- Constructor & Initialization
--==============================================================================
function App:init(o)
	-- Model & State Variables
	self.screen_dirty = true
	self.device_manager = DeviceManager:new()
	self.flags = flags

	-- Sticky screen settings only need to be applied once
	if screen and screen.aa then screen.aa(1) end

	-- Model components: scales, outputs, tracks, modes, settings
	self.scale = {}
	self.output = {}
	self.track = {}
	self.mode = {}
	self.settings = {}

	-- Unified helper toast timeout (seconds); set to 5 for your target timing
	self.helper_toast_timeout = 5

	-- Transport/Playback State
	self.playing = false
	self.recording = false
	self.current_mode = 1
	self.current_track = 1
	self.key_held = false
	self.key_held_button = nil

	-- Presets (for tracks and scales)
	self.preset = {}
	-- Tracks parameter IDs that changed since last preset activation/save.
	-- Used for sparse overwrite preset saves.
	self.preset_armed = {}
	-- Guard to prevent arming during preset application.
	self.preset_applying = false
	-- Namespaces/properties that should only be saved when armed.
	-- Default: everything is constant unless listed here.
	self.preset_nonconstant_props = {
		track = { clip_slot = true },
		-- All scale props are treated as non-constant for global preset blocks.
		scale = { bits = true, root = true, follow_method = true, chord_set = true, follow = true },
	}
	self.preset_props = {
		track = {
			'program_change_in',
			'program_change_out',
			'scale_select',
			'clip_slot',
			'arp',
			'slew',
			'note_range_upper',
			'note_range_lower',
			'chance',
			'step',
			'step_length',
			'reset_step_count',
		},
		scale = {
			'bits',
			'root',
			'follow_method',
			'chord_set',
			'follow',
		},
	}
	for i = 1, 16 do
		self.preset[i] = {}
		self.preset[i]['track_1_program_change_in'] = i
		self.preset[i]['track_1_program_change_out'] = i
	end

	-- Timing parameters:
	self.ppqn = 96
	self.external_ppqn = 24
	self.external_tick = 0
	self.swing = 0.5
	self.swing_div = 6 -- 1/16 note swing

	-- Adaptive clock timing state
	self.tick_multiplier = 4 -- internal_ppqn / external_ppqn (96/24)
	self.last_clock_time = nil -- Timestamp of last external tick
	self.subtick_ms = nil -- Calculated duration of one subtick
	self.use_burst_mode = true -- Dynamic flag for tick dispatch mode
	self.burst_threshold_ms = 4.5 -- Below this, use burst mode. Optimized for 60-200 BPM: spaced mode for natural timing up to ~150 BPM, burst above where scheduling becomes unreliable
	self.scheduled_ticks = {} -- Track scheduled coroutines for cleanup
	self.pending_subticks = 0 -- Track how many subticks are still pending
	self.DEBUG_TIMING = false -- Enable for timing diagnostics

	-- Buffer scrub mode setting (app-level)
	self.buffer_scrub_mode = 'loop' -- 'loop' = loop scrub range, 'play_through' = play through once

	-- Global recording quantization (app-level)
	-- 0 or nil = off; >0 = grid size in ticks (e.g., ppqn/4 for 1/16 note)
	self.record_quantize_grid = 0

	-- Launch sync and scrub sync settings (app-level)
	-- Default values will be set by params:default() via set_action callbacks
	self.launch_sync_length = self.ppqn * 4 -- Default to 1 bar (will be overridden by params)
	self.scrub_sync_length = math.floor(self.ppqn / 4) -- Default to 1/16th note (will be overridden by params)
	self.scrub_start_mode = 'grid'

	-- Tick and transport timing (times in beats)
	self.tick = 0
	self.start_time = 0
	self.last_time = 0

	-- Cached clock_source (1 = internal, 2 = external) to avoid params:get() lookups
	-- on every tick. Kept in sync via a set_action below.
	self.clock_source = 1

	-- Reusable transport_event payload for clock ticks.
	-- Listeners must treat this table as read-only. Allocating a fresh table
	-- on every tick was a major source of GC pressure.
	self._clock_event = { type = 'clock' }

	-- UI redraw heartbeat (used by Foobar.lua watchdog)
	-- Stores last time the UI successfully redrew, in seconds.
	self.ui_last_redraw = (util and util.time and util.time()) or os.time()

	-- Default function bindings
	self.default = {
		-- Scroll with enc2; use enc1 for primary menu actions
		enc1 = function(d) self.mode[self.current_mode]:use_menu('enc2', d) end,
		enc2 = function(d) self.mode[self.current_mode]:set_cursor(d) end,
		enc3 = function(d) self.mode[self.current_mode]:use_menu('enc3', d) end,
		alt_enc1 = function(d) self.mode[self.current_mode]:use_menu('alt_enc2', d) end,
		alt_enc2 = function(d) self.mode[self.current_mode]:use_menu('alt_enc1', d) end,
		alt_enc3 = function(d) self.mode[self.current_mode]:use_menu('alt_enc3', d) end,
		long_fn_2 = function() self.mode[self.current_mode]:use_menu('long_fn_2') end,
		long_fn_3 = function()
			self:set_recording(not self.recording)
			print('Recording: ' .. tostring(self.recording))
		end,
		alt_fn_2 = function() self.mode[self.current_mode]:use_menu('alt_fn_2') end,
		alt_fn_3 = function() self.mode[self.current_mode]:use_menu('alt_fn_3') end,
		press_fn_2 = function() self.mode[self.current_mode]:use_menu('press_fn_2') end,
		press_fn_3 = function() self.mode[self.current_mode]:use_menu('press_fn_3') end,
		screen = function()
			-- Baseline screen now provided by a gridless mode component.
			-- Keep this minimal to avoid duplicate drawing.
		end,
	}
	-- Default menu is now provided by a gridless ModeComponent per mode.

	-- For triggers, keys, and mode-specific contexts
	self.triggers = {}
	self.context = {}
	self.key = {}
	self.alt_down = false
	self.key_down = 0

	-- For MIDI CC event subscribers
	self.cc_subscribers = {}

	----------------------------------------------------------------------------
	-- Instantiate Device-Related Modules (MIDI, Grid, etc.)
	----------------------------------------------------------------------------
	self.midi_in = {}
	self.midi_grid = {} -- NOTE: must use Launch Pad Device 2
	self.launchcontrol = {}
	self.mixer = {}

	-- Crow Setup (e.g. for external CV/gate control)
	self.crow = self.device_manager.crow

	----------------------------------------------------------------------------
	-- Buffer/Sequence State (for recording & playback)
	-- (Note: These might eventually belong in a separate sequencer module.)
	----------------------------------------------------------------------------
	-- (The App does not handle note recording directly; tracks and their sequencers do.)
	--
	-- In future, you may want to centralize buffer management if multiple tracks share similar behavior.

	----------------------------------------------------------------------------
	-- Register Parameters, Tracks, Scales, Outputs, etc.
	----------------------------------------------------------------------------
	params:add_separator('app', 'App')
	params:add_group('Devices', 4)
	self.device_manager:register_params()

	params:add_group('Recording', 4)
	params:add_binary('recording', 'Recording', 'momentary', 0)
	params:set_action('recording', function(state) self:set_recording(state == 1) end)

	params:add_option('buffer_scrub_mode', 'Scrub Mode', { 'loop', 'play_through' }, 1)
	params:set_action('buffer_scrub_mode', function(d)
		self.buffer_scrub_mode = d == 1 and 'loop' or 'play_through'
		App.screen_dirty = true
	end)

	-- Global Record Quantize (app-level)
	-- Index 1 = off, others map to musical divisions based on ppqn
	local record_quantize_options = { 'off', '1/32', '1/16', '1/8', '1/4', '1/2', '1' }
	params:add_option('record_quantize', 'Record Quantize', record_quantize_options, 1)
	params:set_action('record_quantize', function(d)
		self.settings['record_quantize'] = d
		-- Default: off
		local grid = 0
		if d == 2 then
			-- 1/32
			grid = math.floor(self.ppqn / 8)
		elseif d == 3 then
			-- 1/16
			grid = math.floor(self.ppqn / 4)
		elseif d == 4 then
			-- 1/8
			grid = math.floor(self.ppqn / 2)
		elseif d == 5 then
			-- 1/4
			grid = self.ppqn
		elseif d == 6 then
			-- 1/2
			grid = self.ppqn * 2
		elseif d == 7 then
			-- 1/1
			grid = self.ppqn * 4
		end
		self.record_quantize_grid = grid
		App.screen_dirty = true
	end)

	-- Helper function to calculate step values (shared with track.lua logic)
	local function calculate_step_values(include_trig)
		local ppqn = self.ppqn
		local step_values = {
			math.floor(ppqn / 12), -- 1/48
			math.floor(ppqn / 8), -- 1/32
			math.floor(ppqn * 2 / 24), -- 1/32t (triplet)
			math.floor(ppqn / 4), -- 1/16
			math.floor(ppqn * 2 / 12), -- 1/16t (triplet)
			math.floor(ppqn * 3 / 8), -- 1/16d (dotted)
			math.floor(ppqn / 2), -- 1/8
			math.floor(ppqn * 2 / 6), -- 1/8t (triplet)
			math.floor(ppqn * 3 / 4), -- 1/8d (dotted)
			ppqn, -- 1/4
			math.floor(ppqn * 2 / 3), -- 1/4t (triplet)
			math.floor(ppqn * 3 / 2), -- 1/4d (dotted)
			ppqn * 2, -- 1/2
			ppqn * 4, -- 1 (whole note)
			ppqn * 8, -- 2
			ppqn * 16, -- 4
			ppqn * 32, -- 8
			ppqn * 64, -- 16
		}

		if include_trig then
			local options = { 0 }
			for i = 1, #step_values do
				table.insert(options, step_values[i])
			end
			return options
		end
		return step_values
	end

	-- Launch Sync (app-level, replaces per-track action_sync)
	local launch_sync_options = { '1/48', '1/32', '1/32t', '1/16', '1/16t', '1/16d', '1/8', '1/8t', '1/8d', '1/4', '1/4t', '1/4d', '1/2', '1', '2', '4', '8', '16' }
	local launch_sync_default_index = 14 -- Default to 1 bar (index 14 = '1')
	params:add_option('launch_sync', 'Launch Sync', launch_sync_options, launch_sync_default_index)
	params:set_action('launch_sync', function(d)
		self.settings['launch_sync'] = d
		local step_values = calculate_step_values(true)
		local new_sync_length = step_values[d + 1] -- +1 because we removed 'step' option
		self.launch_sync_length = new_sync_length
		App.screen_dirty = true
	end)

	-- Scrub Sync (app-level, controls scrub synchronization)
	local scrub_sync_options = { '1/48', '1/32', '1/32t', '1/16', '1/16t', '1/16d', '1/8', '1/8t', '1/8d', '1/4', '1/4t', '1/4d', '1/2', '1', '2', '4', '8', '16' }
	local scrub_sync_default_index = 4 -- Default to 1/16th note (index 4 = '1/16')
	params:add_option('scrub_sync', 'Scrub Sync', scrub_sync_options, scrub_sync_default_index)
	params:set_action('scrub_sync', function(d)
		self.settings['scrub_sync'] = d
		local step_values = calculate_step_values(true)
		local new_sync_length = step_values[d + 1] -- +1 because we removed 'step' option
		self.scrub_sync_length = new_sync_length
		App.screen_dirty = true
	end)

	-- Scrub Start (app-level, controls where scrub playback starts)
	params:add_option('scrub_start', 'Scrub Start', { 'grid', 'relative', 'absolute' }, 1)
	params:set_action('scrub_start', function(d)
		self.settings['scrub_start'] = d
		local modes = { 'grid', 'relative', 'absolute' }
		self.scrub_start_mode = modes[d]
		App.screen_dirty = true
	end)

	-- Preset grid (session): normal press recalls either only the active track or all tracks+scales from the slot (macro). Alt-save stays scoped per track.
	params:add_option('preset_grid_macro', 'Preset grid macro', { 'off', 'on' }, 2)
	params:set_action('preset_grid_macro', function()
		App.screen_dirty = true
	end)

	-- Create the tracks
	params:add_separator('tracks', 'Tracks')
	for i = 1, 8 do
		self.track[i] = Track:new({ id = i })
	end

	-- Create Shared Components (Scales, Outputs)
	params:add_separator('scales', 'Scales')
	for i = 0, 3 do
		self.scale[i] = Scale:new({ id = i })
	end

	----------------------------------------------------------------------------
	-- params:default() loads preset and triggeres all set_actions in params
	----------------------------------------------------------------------------

	print('params:default')
	App.flags.state.set('initializing', false)
	params:default()

	-- device_out is authoritative for crow vs midi routing; reconcile after all
	-- param set_actions so output_type cannot override a crow device_out choice.
	for i = 1, 8 do
		if self.track[i] then self.track[i]:reconcile_output_routing() end
	end

	-- Mirror the (built-in) clock_source param into self.clock_source so the
	-- per-tick hot path doesn't have to do a params:get() lookup. Norns sets
	-- this via the system params menu.
	if params.lookup_param and params:lookup_param('clock_source') then
		self.clock_source = params:get('clock_source')
		params:set_action('clock_source', function(d)
			self.clock_source = d
		end)
	end

	----------------------------------------------------------------------------
	-- Register PSET save/load/delete callbacks for table data persistence
	----------------------------------------------------------------------------
	params.action_write = function(filename, name, pset_number) Persistence.save(pset_number) end

	params.action_read = function(filename, silent, pset_number)
		Persistence.load(pset_number)
		-- Reload current preset to reflect loaded state
		local current = self.track[1] and self.track[1].current_preset or 1
		if self.preset[current] then self:load_preset(current) end
	end

	params.action_delete = function(filename, name, pset_number) Persistence.delete(pset_number) end

	-- Attempt to load default PSET data (slot 1) if it exists
	-- This also sets the PSET number for Persistence (clip persistence)
	Persistence.load(1)
end

--==============================================================================
-- Transport Event Handling (MIDI In, Clock, etc.)
--==============================================================================
function App:on_transport(data)
	if data.type == 'start' then
		self:on_start()
	elseif data.type == 'continue' then
		self:on_start(true)
	elseif data.type == 'stop' then
		self:on_stop()
	elseif data.type == 'clock' then
		self:on_external_clock()
	end

	self.screen_dirty = true
end

--==============================================================================
-- External Clock Handling (from MIDI Clock)
--==============================================================================
function App:on_external_clock()
	-- Only process external clock if clock source is external
	if self.clock_source ~= 2 then return end
	-- Prevent reentrancy: emit('transport_event') in on_tick can trigger MIDI/echo and re-enter
	if self._in_external_clock then return end
	self._in_external_clock = true
	self.external_tick = self.external_tick + 1
	local now = util.time()

	-- Cap total ticks per invocation: at most 8 (4 to complete previous + 4 for this clock).
	-- Prevents drift from any path firing too many ticks.
	local ticks_this_invocation = 0
	local cap_limit = self.tick_multiplier * 2
	local function fire_tick_capped()
		if ticks_this_invocation < cap_limit then
			ticks_this_invocation = ticks_this_invocation + 1
			self._tick_authorized = true
			self:on_tick()
			self._tick_authorized = false
		end
	end

	-- If a new clock tick arrives before scheduled subticks complete,
	-- cancel remaining scheduled ticks and burst them immediately
	if #self.scheduled_ticks > 0 then
		-- Cancel all pending scheduled ticks
		for _, coro in ipairs(self.scheduled_ticks) do
			safe_cancel(coro)
			goto continue
		end
		::continue::
		self.scheduled_ticks = {}

		-- Burst the remaining subticks immediately (safety check for count)
		local remaining = math.max(0, self.pending_subticks)
		for i = 1, remaining do
			fire_tick_capped()
		end
		self.pending_subticks = 0
	end

	-- First tick: no timing data yet, process one tick and schedule the rest
	if not self.last_clock_time then
		-- Process first tick immediately
		fire_tick_capped()

		-- Schedule remaining subticks to process at start of second clock signal
		-- Store count of pending subticks (will be processed before next clock handling)
		self.pending_subticks = self.tick_multiplier - 1
		self.last_clock_time = now

		if self.DEBUG_TIMING then print(string.format('FIRST CLOCK: Tick: %d, Pending: %d', App.tick, self.pending_subticks)) end
		self._in_external_clock = false
		return
	end

	-- Process any pending subticks from first clock before handling new clock
	if self.pending_subticks > 0 then
		local remaining = self.pending_subticks
		if self.DEBUG_TIMING then print(string.format('PROCESSING PENDING: %d subticks, starting at Tick: %d', remaining, App.tick)) end
		for i = 1, remaining do
			fire_tick_capped()
		end
		self.pending_subticks = 0
		if self.DEBUG_TIMING then print(string.format('PENDING COMPLETE: Tick: %d', App.tick)) end
	end

	-- Calculate subtick timing based on time between external ticks
	local tick_duration = (now - self.last_clock_time) * 1000 -- Convert to ms
	self.subtick_ms = tick_duration / self.tick_multiplier

	-- Hybrid approach: calculate how many subticks can be spaced at threshold resolution
	-- This preserves finer timing resolution instead of jumping to full burst mode
	local spaced_subticks = math.floor(tick_duration / self.burst_threshold_ms)
	spaced_subticks = math.min(spaced_subticks, self.tick_multiplier) -- Can't schedule more than we need
	local burst_count = self.tick_multiplier - spaced_subticks -- Remaining subticks to burst

	self.last_clock_time = now

	-- Cap for THIS external clock only: never fire more than tick_multiplier (4) in the dispatch below.
	-- Burst/process_pending above complete the *previous* clock; dispatch is for *this* clock only.
	-- Logs showed all advances authorized but still 383 ext at 1536 app => 4 invocations fire 5; cap at sink.
	self._current_period_advances = 0
	local function fire_tick_current()
		self._in_current_period = true
		fire_tick_capped()
		self._in_current_period = false
	end

	-- Dispatch internal ticks using hybrid approach (fire_tick_capped enforces 8 max per invocation)
	if spaced_subticks == 0 then
		-- No spacing possible: burst all subticks immediately
		for i = 1, self.tick_multiplier do
			fire_tick_current()
		end
		self.pending_subticks = 0

		if self.DEBUG_TIMING then print(string.format('FULL BURST: tick_duration=%.2fms, threshold=%.2fms', tick_duration, self.burst_threshold_ms)) end
	elseif burst_count == 0 then
		-- Full spaced mode: all subticks can be scheduled
		-- Fire first subtick immediately
		fire_tick_current()

		-- Track remaining subticks
		self.pending_subticks = spaced_subticks - 1

		-- Schedule remaining subticks with even spacing
		local spacing_ms = tick_duration / spaced_subticks
		for i = 2, spaced_subticks do
			local delay_ms = spacing_ms * (i - 1)
			local coro = clock.run(function()
				clock.sleep(delay_ms / 1000) -- Convert ms to seconds
				if self.playing then
					if self.pending_subticks > 0 then self.pending_subticks = self.pending_subticks - 1 end
					fire_tick_current()
				end
			end)
			table.insert(self.scheduled_ticks, coro)
		end
	else
		-- Hybrid mode: schedule spaced subticks, burst remaining at last scheduled position
		-- Fire first subtick immediately
		fire_tick_current()

		-- Track remaining spaced subticks (excluding the burst)
		self.pending_subticks = spaced_subticks - 1

		-- Schedule remaining spaced subticks with even spacing
		local spacing_ms = tick_duration / spaced_subticks
		for i = 2, spaced_subticks do
			local delay_ms = spacing_ms * (i - 1)
			local is_last_spaced = (i == spaced_subticks)
			local coro = clock.run(function()
				clock.sleep(delay_ms / 1000) -- Convert ms to seconds
				if self.playing then
					if self.pending_subticks > 0 then self.pending_subticks = self.pending_subticks - 1 end

					-- At the last scheduled position, burst remaining subticks
					if is_last_spaced and burst_count > 0 then
						-- Fire the scheduled subtick, then burst remaining
						fire_tick_current()
						for j = 1, burst_count do
							fire_tick_current()
						end
					else
						-- Normal scheduled subtick
						fire_tick_current()
					end
				end
			end)
			table.insert(self.scheduled_ticks, coro)
		end

		if self.DEBUG_TIMING then print(string.format('HYBRID: spaced=%d, burst=%d, tick_duration=%.2fms, spacing=%.2fms', spaced_subticks, burst_count, tick_duration, spacing_ms)) end
	end

	-- Debug output (optional)
	if self.DEBUG_TIMING then
		local mode_str
		if spaced_subticks == 0 then
			mode_str = 'FULL_BURST'
		elseif burst_count == 0 then
			mode_str = 'FULL_SPACED'
		else
			mode_str = 'HYBRID'
		end
		print(
			string.format(
				'Mode: %s, Spaced: %d, Burst: %d, Subtick: %.2fms, Threshold: %.2fms, Pending: %d, Tick: %d',
				mode_str,
				spaced_subticks,
				burst_count,
				self.subtick_ms or 0,
				self.burst_threshold_ms,
				self.pending_subticks,
				App.tick
			)
		)
	end
	self._in_external_clock = false
end

--==============================================================================
-- Playback Control Functions (Start, Stop, etc.)
--==============================================================================
function App:on_start(continue)
	local tracer = require('Foobar/lib/utilities/tracer').device(0, 'transport')
	tracer:log('info', 'App start')
	self.playing = true
	self.tick = 0
	self.external_tick = 0
	self.start_time = clock.get_beats()
	self.last_time = clock.get_beats()

	-- Reset external clock timing state
	self.last_clock_time = nil
	self.subtick_ms = nil
	self.use_burst_mode = true
	self.pending_subticks = 0
	-- Clear any scheduled ticks from previous session
	for _, coro in ipairs(self.scheduled_ticks) do
		safe_cancel(coro)
	end
	self.scheduled_ticks = {}

	if continue then
		self:emit('transport_event', { type = 'continue' })
	else
		self:emit('transport_event', { type = 'start' })
	end

	-- Transport Tick Loop using PPQN (Internal = 1, External = 2)
	if self.clock_source == 1 then self.clock = clock.run(function()
		while true do
			clock.sync(1 / self.ppqn)
			self:on_tick()
			App.screen_dirty = true
		end
	end) end
end

function App:on_stop()
	local tracer = require('Foobar/lib/utilities/tracer').device(0, 'transport')
	tracer:log('info', 'App stop')
	self.playing = false
	self:emit('transport_event', { type = 'stop' })
	if self.clock_source == 1 then
		if self.clock then
			safe_cancel(self.clock)
			self.clock = nil
		end
	end

	-- Reset clock timing state
	self.last_clock_time = nil
	self.subtick_ms = nil
	self.pending_subticks = 0

	-- Cancel any scheduled ticks
	for _, coro in ipairs(self.scheduled_ticks) do
		safe_cancel(coro)
	end
	self.scheduled_ticks = {}
end

function App:set_recording(state)
	self.recording = state
	self:emit('recording', state)
	self.screen_dirty = true
end

function App:cleanup()
	-- Clean up any running clocks when script reloads
	if self.clock then
		safe_cancel(self.clock)
		self.clock = nil
	end
	self.playing = false
end

--==============================================================================
-- Tick and Transport Handling
--==============================================================================

-- The on_tick function updates the tick counter,
-- and dispatches clock events to tracks.
function App:on_tick()
	-- When external clock: only advance if we were called from fire_tick_capped (catches stray callers)
	local external = (self.clock_source == 2)
	if external and not self._tick_authorized then return end
	self.last_time = clock.get_beats()
	self.tick = self.tick + 1
	-- When external and in "current period" (dispatch): allow at most 4 advances per period; undo 5th.
	if external and self._in_current_period then
		self._current_period_advances = (self._current_period_advances or 0) + 1
		if self._current_period_advances > self.tick_multiplier then
			self.tick = self.tick - 1
			self._current_period_advances = self._current_period_advances - 1
			return
		end
	end
	-- Reuse a single payload table to avoid allocating one per tick.
	-- Listeners must treat the table as read-only (only reads .type).
	self:emit('transport_event', self._clock_event)
end

--==============================================================================
-- UI Heartbeat
--==============================================================================
-- Called by the top-level redraw function to record the last successful redraw.
function App:ui_heartbeat() self.ui_last_redraw = (util and util.time and util.time()) or os.time() end

--==============================================================================
-- MIDI In/Out and Grid Registration
--==============================================================================

function App:register_midi_grid(n)
	self.midi_grid = self.device_manager:get(n)
	self.midi_grid:send({ 240, 0, 32, 41, 2, 13, 0, 127, 247 }) -- Set Launchpad to Programmer Mode
end

--==============================================================================
-- Event Handling System (on, off, emit)
--==============================================================================
function App:on(event_name, listener)
	if not self.event_listeners then self.event_listeners = {} end
	if not self.event_listeners[event_name] then self.event_listeners[event_name] = {} end
	table.insert(self.event_listeners[event_name], listener)
	return function() self:off(event_name, listener) end
end

function App:off(event_name, listener)
	if self.event_listeners and self.event_listeners[event_name] then
		for i, l in ipairs(self.event_listeners[event_name]) do
			if l == listener then
				table.remove(self.event_listeners[event_name], i)
				break
			end
		end
	end
end

function App:emit(event_name, ...)
	if self.event_listeners and self.event_listeners[event_name] then
		for _, listener in ipairs(self.event_listeners[event_name]) do
			listener(...)
		end
	end
end

--==============================================================================
-- Drawing and User Interface Functions
--==============================================================================
function App:draw()
	screen.clear() -- Clear screen space
	if self.mode[self.current_mode] then self.mode[self.current_mode]:draw() end
	-- Note: screen.update() is called once by the top-level redraw() in
	-- Foobar.lua; do not call it here too. screen.aa(1) is set once at init,
	-- not every frame. screen.ping() (screen-blanker reset) belongs on user
	-- input paths, not in the redraw loop.
end

function App:handle_enc(e, d)
	if screen and screen.ping then screen.ping() end
	local context = self.mode[self.current_mode].context
	if e == 1 then
		if context.enc1_alt and self.alt_down then
			context.enc1_alt(d)
		elseif context.enc1 then
			context.enc1(d)
		end
	elseif e == 2 then
		if context.enc2_alt and self.alt_down then
			context.enc2_alt(d)
		elseif context.enc2 then
			context.enc2(d)
		end
	elseif e == 3 then
		if context.enc3_alt and self.alt_down then
			context.enc3_alt(d)
		elseif context.enc3 then
			context.enc3(d)
		end
	end
	App.mode[App.current_mode]:reset_timeout()

	-- Ensure helper toast reflects latest pending/confirm state and force redraw
	local mode = self.mode[self.current_mode]
	if mode then
		local duration = self.alt_down and false or self.helper_toast_timeout
		mode:update_helper_toast({ duration = duration })
		self.screen_dirty = true
	end
end

function App:handle_key(k, z)
	if screen and screen.ping then screen.ping() end
	local mode = self.mode[self.current_mode]
	local context = mode.context
	local prev_key_held = self.key_held
	self.key_held = (z == 1)
	self.key_held_button = (z == 1) and k or nil
	if k == 1 then
		local was_alt = self.alt_down
		self.alt_down = (z == 1)
		if mode and self.alt_down ~= was_alt then
			local duration = self.alt_down and false or self.helper_toast_timeout
			mode:update_helper_toast({ duration = duration })
		end
	elseif self.alt_down and z == 1 and context['alt_fn_' .. k] then
		context['alt_fn_' .. k]()
	elseif z == 1 then
		self.key_down = util.time()
	elseif not self.alt_down then
		local hold_time = util.time() - self.key_down
		local handled = false
		if hold_time <= 0.3 and mode:has_pending_confirmation() then
			if k == 2 then
				mode:clear_pending_confirmation({ revert = true })
				handled = true
			elseif k == 3 then
				handled = mode:confirm_pending_confirmation()
			end
			if handled then
				-- Immediately refresh helper labels/toast so confirm label disappears
				local duration = App.alt_down and false or self.helper_toast_timeout
				mode:update_helper_toast({ duration = duration })
				App.screen_dirty = true
			end
		end
		if not handled then
			if hold_time > 0.3 and context['long_fn_' .. k] then
				context['long_fn_' .. k]()
			elseif context['press_fn_' .. k] then
				context['press_fn_' .. k]()
			end
		end
	end
	if self.key_held ~= prev_key_held then self.screen_dirty = true end
	mode:reset_timeout()
end

--==============================================================================
-- Parameter Registration and Song Settings
--==============================================================================

function App:_preset_arm(param_id, source)
	-- Arm only when not applying a preset.
	if self.preset_applying then return end
	-- Avoid arming changes that we know are not user/creative edits.
	if source and type(source) == 'string' then
		if string.match(source, '^preset_load') then return end
		if source == 'clip_state_sync' then return end
	end
	self.preset_armed[param_id] = true
end

function App:clear_preset_armed() self.preset_armed = {} end

-- Current value for preset serialization: prefer App.settings, then params (some UIs use params:set directly).
function App:_preset_param_value(param_id)
	if self.settings[param_id] ~= nil then return self.settings[param_id] end
	if params and params.lookup_param then
		local p = params:lookup_param(param_id)
		if p then return params:get(param_id) end
	end
	return nil
end

function App:save_preset(d, param)
	if self.preset[d] == nil then self.preset[d] = {} end
	local preset = self.preset[d]

	if type(param) == 'string' then
		local value = self.settings[param]
		if preset[param] ~= value then preset[param] = value end
	elseif type(param) == 'table' then
		for index, name in ipairs(param) do
			local value = self.settings[name]
			if preset[name] ~= value then preset[name] = value end
		end
	else
		for name, value in pairs(self.settings) do
			if preset[name] ~= value then preset[name] = value end
		end
	end
end

function App:load_preset(d, param, force)
	local preset = self.preset[d]
	if preset == nil then
		error('App:load_preset was nil')
		return
	end

	if type(param) == 'string' then
		-- Apply only when explicitly present in preset table (nil means no-op).
		if preset[param] ~= nil then
			local value = preset[param]
			if force or (self.settings[param] ~= value) then Registry.set(param, value, 'preset_load_single') end
		end
	elseif type(param) == 'table' then
		for index, name in ipairs(param) do
			-- Apply only when explicitly present in preset table (nil means no-op).
			if preset[name] ~= nil then
				local value = preset[name]
				if force or (self.settings[name] ~= value) then Registry.set(name, value, 'preset_load_table') end
			end
		end
	else
		for name, value in pairs(preset) do
			if self.settings[name] ~= value then Registry.set(name, value, 'preset_load_all') end
		end
	end
end

-- Overwrite save for a scoped subset of a preset slot, using sparse keys.
-- - Constant props: always saved.
-- - Non-constant props: saved only if armed; otherwise removed (nil => no-op).
-- Scope:
--   track_id: active track to save
--   scale_id: selected scale to save (0 => skip scale keys)
function App:save_preset_overwrite_scoped(slot, scope)
	if self.preset[slot] == nil then self.preset[slot] = {} end
	local preset = self.preset[slot]
	scope = scope or {}
	local track_id = scope.track_id
	local scale_id = scope.scale_id

	-- Track params
	if track_id and self.preset_props and self.preset_props.track then
		for _, prop in ipairs(self.preset_props.track) do
			local pid = 'track_' .. track_id .. '_' .. prop
			local is_nonconstant = self.preset_nonconstant_props
				and self.preset_nonconstant_props.track
				and self.preset_nonconstant_props.track[prop] == true
			if is_nonconstant then
				if self.preset_armed[pid] then
					preset[pid] = self:_preset_param_value(pid)
				else
					preset[pid] = nil
				end
			else
				preset[pid] = self:_preset_param_value(pid)
			end
		end
	end

	-- Scale params (only for selected scale; skip entirely when scale_select==0)
	if scale_id and scale_id > 0 and self.preset_props and self.preset_props.scale then
		local scale = self.scale and self.scale[scale_id] or nil
		local track_following = false
		if scale and scale.follow_method and scale.follow then
			-- Track-following modes: follow_method > 4 implies MIDI modes in Scale component.
			track_following = (scale.follow_method > 4 and scale.follow > 0)
		end

		for _, prop in ipairs(self.preset_props.scale) do
			local pid = 'scale_' .. scale_id .. '_' .. prop
			-- Harmony is edited via many paths (some use params:set without Registry.set), so arming alone misses changes.
			-- Snapshot full current scale state when not track-following; omit keys when following (no-op on load).
			if track_following then
				preset[pid] = nil
			else
				preset[pid] = self:_preset_param_value(pid)
			end
		end
	end

	-- Saving commits the armed set as the new baseline.
	self:clear_preset_armed()
end

-- Activate a preset slot as a global musical block:
-- applies any saved track/scale keys across the whole system using sparse key existence.
function App:activate_preset_global(slot)
	self.preset_applying = true
	self:clear_preset_armed()

	-- Keep per-track UI state consistent
	for tid = 1, 8 do
		if self.track[tid] then self.track[tid].current_preset = slot end
	end

	-- Build a global parameter list for tracks + scales.
	local params_to_apply = {}
	if self.preset_props and self.preset_props.track then
		for tid = 1, 8 do
			for _, prop in ipairs(self.preset_props.track) do
				table.insert(params_to_apply, 'track_' .. tid .. '_' .. prop)
			end
		end
	end
	if self.preset_props and self.preset_props.scale then
		-- Scales are instantiated for ids 0..3 in App:init
		for sid = 0, 3 do
			for _, prop in ipairs(self.preset_props.scale) do
				table.insert(params_to_apply, 'scale_' .. sid .. '_' .. prop)
			end
		end
	end

	self:load_preset(slot, params_to_apply)
	self.preset_applying = false
end

--==============================================================================
-- Bezier Curve Mapping (for CC, etc.)
--==============================================================================
local A = { x = 0, y = 0 } -- Minimum output control point
local B = { x = 0, y = 1.13 } -- Control point for curve shaping
local C = { x = 0.77, y = 0.64 } -- Control point for curve shaping
local D = { x = 1, y = 1 } -- Maximum output control point

local function bezier_transform(input, P0, P1, P2, P3)
	local t = input / 127
	local output = {}
	output.input = input

	local u = 1 - t
	local tt = t * t
	local uu = u * u
	local uuu = uu * u
	local ttt = tt * t

	output.x = uuu * P0.x + 3 * uu * t * P1.x + 3 * u * tt * P2.x + ttt * P3.x
	output.y = uuu * P0.y + 3 * uu * t * P1.y + 3 * u * tt * P2.y + ttt * P3.y
	output.value = math.floor(output.y * 127)
	return output
end

--==============================================================================
-- Modes and Grid Registration
--==============================================================================
function App:register_modes()
	self.modes = {}
	self.grid = Grid:new({
		grid_start = { x = 1, y = 1 },
		grid_end = { x = 4, y = 1 },
		display_start = { x = 1, y = 1 },
		display_end = { x = 4, y = 1 },
		offset = { x = 4, y = 8 },
		midi = App.midi_grid.device,
		event = function(self, data)
			if data.state then
				local mode = App.mode[App.current_mode]
				local selected = self:grid_to_index(data)

				if App.current_mode == selected then return end

				self:reset()

				App:set_mode(selected)

				self.led[data.x][data.y] = 1
				self:refresh()
			end
		end,
		active = true,
	})

	self.midi_grid.event = function(msg)
		local mode = self.mode[self.current_mode]
		self.grid:process(msg)
		mode.grid:process(msg)
	end

	local SessionModePreset = require('Foobar/lib/modes/session-preset-buffer')
	local SessionModeNote = require('Foobar/lib/modes/session-note')
	local DrumsMode = require('Foobar/lib/modes/drums')
	local KeysMode = require('Foobar/lib/modes/keys')
	local UserMode = require('Foobar/lib/modes/user')

	self.mode[1] = SessionModePreset
	self.mode[5] = SessionModeNote
	self.mode[2] = DrumsMode
	self.mode[3] = KeysMode
	self.mode[4] = UserMode

	self.mode[1]:enable()
end

function App:set_mode(index)
	self.mode[self.current_mode].track = App.current_track
	self.mode[self.current_mode]:disable()
	self.current_mode = index
	self.mode[self.current_mode].track = App.current_track
	self.mode[self.current_mode]:enable()
end
--==============================================================================
-- Feature Flags Management
--==============================================================================

--==============================================================================
-- Return the App Class
--==============================================================================
return App
