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
local path_name = "Foobar/lib/"
local utilities = require(path_name .. "utilities")
local Grid = require(path_name .. "grid")
local Track = require(path_name .. "components/app/track")
local Scale = require(path_name .. "components/track/scale")
local Output = require(path_name .. "components/track/output")
local Mode = require(path_name .. "components/app/mode")
local musicutil = require(path_name .. "musicutil-extended")
local DeviceManager = require(path_name .. "components/app/devicemanager")
local LaunchControl = require(path_name .. "launchcontrol")
local UI = require(path_name .. "ui")
local flags = require(path_name .. "utilities/flags")
local trace = require(path_name .. "utilities/trace_cli")
local ParamTrace = require(path_name .. "utilities/paramtrace")
local LATCH_CC = 64

--==============================================================================
-- Class Definition: App
--==============================================================================
local App = {}
App.__index = App

--==============================================================================
-- Constructor & Initialization
--==============================================================================
function App:init(o)
	-- Model & State Variables
	self.screen_dirty = true
	self.device_manager = DeviceManager:new()
	self.flags = flags

	-- Model components: scales, outputs, tracks, modes, settings
	self.scale = {}
	self.output = {}
	self.track = {}
	self.mode = {}
	self.settings = {}

	-- Transport/Playback State
	self.playing = false
	self.recording = false
	self.current_mode = 1
	self.current_track = 1

	-- Presets (for tracks and scales)
	self.preset = {}
	self.preset_props = {
		track = {
			"program_change",
			"scale_select",
			"arp",
			"slew",
			"note_range_upper",
			"note_range_lower",
			"chance",
			"step",
			"step_length",
			"reset_step",
		},
		scale = {
			"bits",
			"root",
			"follow_method",
			"chord_set",
			"follow",
		},
	}
	for i = 1, 16 do
		self.preset[i] = {}
		self.preset[i]["track_1_program_change"] = i
	end

	-- Timing parameters:
	self.ppqn = 24
	self.swing = 0.5
	self.swing_div = 6 -- 1/16 note swing

	-- Tick and transport timing (times in beats)
	self.tick = 0
	self.start_time = 0
	self.last_time = 0

	-- UI redraw heartbeat (used by Foobar.lua watchdog)
	-- Stores last time the UI successfully redrew, in seconds.
	self.ui_last_redraw = (util and util.time and util.time()) or os.time()

	

	-- Default function bindings
	self.default = {
		enc1 = function(d)
			self.mode[self.current_mode]:set_cursor(d)
		end,
		enc2 = function(d)
			self.mode[self.current_mode]:use_menu('enc2', d)
		end,
		enc3 = function(d)
			self.mode[self.current_mode]:use_menu('enc3', d)
		end,
		alt_enc1 = function(d)
			self.mode[self.current_mode]:use_menu('alt_enc1', d)
		end,
		alt_enc2 = function(d)
			self.mode[self.current_mode]:use_menu('alt_enc2', d)
		end,
		alt_enc3 = function(d)
			self.mode[self.current_mode]:use_menu('alt_enc3', d)
		end,
		long_fn_2 = function()
			self.mode[self.current_mode]:use_menu('long_fn_2')
		end,
		long_fn_3 = function()
			self.recording = not self.recording
			print("Recording: " .. tostring(self.recording))
			self.screen_dirty = true
		end,
		alt_fn_2 = function()
			self.mode[self.current_mode]:use_menu('alt_fn_2')
		end,
		alt_fn_3 = function()
			self.mode[self.current_mode]:use_menu('alt_fn_3')
		end,
		press_fn_2 = function()
			self.mode[self.current_mode]:use_menu('press_fn_2')
		end,
		press_fn_3 = function()
			self.mode[self.current_mode]:use_menu('press_fn_3')
		end,
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

	self.device_manager:register_params()
	-- Create the tracks
	params:add_separator("tracks", "Tracks")
	for i = 1, 5 do
		self.track[i] = Track:new({ id = i })
	end

	-- Create Shared Components (Scales, Outputs)
	params:add_separator("scales", "Scales")
	for i = 0, 3 do
		self.scale[i] = Scale:new({ id = i })
	end

	----------------------------------------------------------------------------
	-- params:default() loads preset and triggeres all set_actions in params
	----------------------------------------------------------------------------

	print("params:default")
	App.flags.state.set('initializing', false)
	params:default()
end

--==============================================================================
-- Transport Event Handling (MIDI In, Clock, etc.)
--==============================================================================
function App:on_transport(data)
	if data.type == "start" then
		self:on_start()
	elseif data.type == "continue" then
		self:on_start(true)
	elseif data.type == "stop" then
		self:on_stop()
	elseif data.type == "clock" then
		self:on_tick()
	end

	self.screen_dirty = true
end

--==============================================================================
-- Playback Control Functions (Start, Stop, etc.)
--==============================================================================
function App:on_start(continue)
	local tracer = require('Foobar/lib/utilities/tracer').device(0, 'transport')
	tracer:log('info', 'App start')
	self.playing = true
	self.tick = 0
	self.start_time = clock.get_beats()
	self.last_time = clock.get_beats()

	if continue then
		self:emit("transport_event", { type = "continue" })
	else
		self:emit("transport_event", { type = "start" })
	end

	-- Transport Tick Loop using PPQN (Internal = 1, External = 2)
	if params:get("clock_source") == 1 then
		self.clock = clock.run(function()
			while true do
				clock.sync(1 / self.ppqn)
				App:on_tick()
				App.screen_dirty = true
			end
		end)
	end
end

function App:on_stop()
	local tracer = require('Foobar/lib/utilities/tracer').device(0, 'transport')
	tracer:log('info', 'App stop')
	self.playing = false
	self:emit("transport_event", { type = "stop" })
	if params:get("clock_source") == 1 then
		if self.clock then
			clock.cancel(self.clock)
			self.clock = nil
		end
	end
end

function App:cleanup()
	-- Clean up any running clocks when script reloads
	if self.clock then
		clock.cancel(self.clock)
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
	self.last_time = clock.get_beats()
	self.tick = self.tick + 1
	self:emit("transport_event", { type = "clock" })
end

--==============================================================================
-- UI Heartbeat
--==============================================================================
-- Called by the top-level redraw function to record the last successful redraw.
function App:ui_heartbeat()
	self.ui_last_redraw = (util and util.time and util.time()) or os.time()
end

--==============================================================================
-- MIDI In/Out and Grid Registration
--==============================================================================


function App:register_midi_grid(n)
	print("Register Grid Device " .. n)
	self.midi_grid = self.device_manager:get(n)
	self.midi_grid:send({ 240, 0, 32, 41, 2, 13, 0, 127, 247 }) -- Set Launchpad to Programmer Mode
end

--==============================================================================
-- Event Handling System (on, off, emit)
--==============================================================================
function App:on(event_name, listener)
	if not self.event_listeners then
		self.event_listeners = {}
	end
	if not self.event_listeners[event_name] then
		self.event_listeners[event_name] = {}
	end
	table.insert(self.event_listeners[event_name], listener)
	return function()
		self:off(event_name, listener)
	end
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
	screen.ping()
	screen.clear() -- Clear screen space
	screen.aa(1) -- Enable anti-aliasing
	if self.mode[self.current_mode] then
		self.mode[self.current_mode]:draw()
	end
	screen.update()
end

function App:handle_enc(e, d)
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
end

function App:handle_key(k, z)
	local context = self.mode[self.current_mode].context
	if k == 1 then
		self.alt_down = (z == 1)
	elseif self.alt_down and z == 1 and context["alt_fn_" .. k] then
		context["alt_fn_" .. k]()
	elseif z == 1 then
		self.key_down = util.time()
	elseif not self.alt_down then
		local hold_time = util.time() - self.key_down
		if hold_time > 0.3 and context["long_fn_" .. k] then
			context["long_fn_" .. k]()
		elseif context["press_fn_" .. k] then
			context["press_fn_" .. k]()
		end
	end
	App.mode[App.current_mode]:reset_timeout()
end

--==============================================================================
-- Parameter Registration and Song Settings
--==============================================================================

function App:save_preset(d, param)
	if self.preset[d] == nil then
		self.preset[d] = {}
	end
	local preset = self.preset[d]

	if type(param) == "string" then
		local value = self.settings[param]
		if preset[param] ~= value then
			preset[param] = value
		end
	elseif type(param) == "table" then
		for index, name in ipairs(param) do
			local value = self.settings[name]
			if preset[name] ~= value then
				preset[name] = value
			end
		end
	else
		for name, value in pairs(self.settings) do
			if preset[name] ~= value then
				preset[name] = value
			end
		end
	end
end

function App:load_preset(d, param, force)
	local preset = self.preset[d]
	if preset == nil then
		error("App:load_preset was nil")
		return
	end

	if type(param) == "string" then
		local value = preset[param]
		if force or (self.settings[param] ~= value) then
			ParamTrace.set(param, value, 'preset_load_single')
		end
	elseif type(param) == "table" then
		for index, name in ipairs(param) do
			local value = preset[name]
			if force or (value and self.settings[name] ~= value) then
				ParamTrace.set(name, value, 'preset_load_table')
			end
		end
	else
		for name, value in pairs(preset) do
			if self.settings[name] ~= value then
				ParamTrace.set(name, value, 'preset_load_all')
			end
		end
	end
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

				if App.current_mode == selected then
					return
				end

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

	local SessionModePreset = require("Foobar/lib/modes/session-preset")
	local SessionModeNote = require("Foobar/lib/modes/session-note")
	local DrumsMode = require("Foobar/lib/modes/drums")
	local KeysMode = require("Foobar/lib/modes/keys")
	local UserMode = require("Foobar/lib/modes/user")

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
