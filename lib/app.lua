--==============================================================================
-- App.lua - Main Application Controller
--
-- This file instantiates the App class, which manages device connections,
-- transport, tracks, modes, and the user interface.

--==============================================================================
  
--==============================================================================
-- Dependencies and Global Variables
--==============================================================================
local path_name = 'Foobar/lib/'
local utilities   = require(path_name .. 'utilities')
local Grid        = require(path_name .. 'grid')
local Track       = require('Foobar/lib/components/app/track')
local Scale       = require('Foobar/lib/components/track/scale')
local Output      = require('Foobar/lib/components/track/output')
local Mode        = require('Foobar/lib/components/app/mode')
local musicutil   = require(path_name .. 'musicutil-extended')
local DeviceManager = require('Foobar/lib/components/app/devicemanager')
local LaunchControl = require(path_name .. 'launchcontrol')

local LATCH_CC = 64

--==============================================================================
-- Class Definition: App
--==============================================================================
local App = {}
App.__index = App
  
--==============================================================================
-- Constructor & Initialization
--==============================================================================
function App:new(o)
  o = o or {}
  setmetatable(o, self)
  -- Initialize common event-handling methods from this class (and eventually from a shared base)
  o.event_listeners = {}
  o:initialize(o)
  return o
end

function App:init(o)
  ----------------------------------------------------------------------------
  -- Model & State Variables
  ----------------------------------------------------------------------------
  self.screen_dirty = true
  self.device_manager = DeviceManager:new()

  -- Model components: scales, outputs, tracks, modes, settings
  self.scale   = {}
  self.output  = {}
  self.track   = {}
  self.mode    = {}
  self.settings = {}

  -- Transport/Playback State
  self.playing = false
  self.current_mode = 1
  self.current_track = 1
  
  -- Presets (for tracks and scales)
  self.preset = {}
  self.preset_props = {
    track = {
      'program_change', 'scale_select', 'arp', 'slew',
      'note_range_upper', 'note_range_lower', 'chance',
      'step', 'step_length', 'reset_step'
    }, 
    scale = {
      'bits', 'root', 'follow_method', 'chord_set', 'follow'
    }
  }
  for i = 1, 16 do
    self.preset[i] = {}
    self.preset[i]['track_1_program_change'] = i
  end

  -- Timing parameters:
  -- Set PPQN to 48 for a finer subdivision.
  self.ppqn = 48
  self.swing = 0.5
  self.swing_div = 6 -- 1/16 note swing

  -- Tick and transport timing (times in beats)
  self.tick = 0
  self.start_time = 0
  self.last_time = 0
  
  -- Default function bindings
  self.default = {
    enc1 = function(d) print('default enc 1 ' .. d) end,
    enc2 = function(d) print('default enc 2 ' .. d) end,
    enc3 = function(d) print('default enc 3 ' .. d) end,
    alt_enc1 = function(d) print('default alt enc 1 ' .. d) end,
    alt_enc2 = function(d) print('default alt enc 2 ' .. d) end,
    alt_enc3 = function(d) print('default alt enc 3 ' .. d) end,
    long_fn_2 = function() print('Long 2') end,
    long_fn_3 = function() print('Long 3') end,
    alt_fn_2 = function() print('Alt 2') end,
    alt_fn_3 = function() print('Alt 3') end,
    press_fn_2 = function()
    
      if App.playing then
        App:stop()
      else
        App:start()
      end
    
    end,
    press_fn_3 = function() print('press 3') end
  
  }

  -- For triggers, keys, and mode-specific contexts
  self.triggers = {}
  self.context  = {}
  self.key      = {}
  self.alt_down = false
  self.key_down = 0

  -- For MIDI CC event subscribers
  self.cc_subscribers = {}

  -- State flags for modes
  self.send_out = true
  self.send_in  = true

  ----------------------------------------------------------------------------
  -- Instantiate Device-Related Modules (MIDI, Grid, etc.)
  ----------------------------------------------------------------------------
  self.midi_in   = {}
  self.midi_out  = {}
  self.midi_grid = {}  -- NOTE: must use Launch Pad Device 2
  self.launchcontrol = {}
  self.mixer     = {}
  self.bluebox   = {}

  -- Crow Setup (e.g. for external CV/gate control)
  self.crow = self.device_manager.crow

  ----------------------------------------------------------------------------
  -- Buffer/Timing and Subtick Configuration (for microtiming)
  ----------------------------------------------------------------------------
  -- For now, the transport tick is driven by ppqn = 96.
  -- In addition, we introduce a master subtick clock that emits events at a
  -- finer subdivision level for microtiming. The subdivision factor here can be
  -- adjusted (e.g., 2 means each tick is subdivided into 2 microticks).
  self.subdivision = 2
  -- seconds per tick is derived from current tempo using clock.get_beat_sec()
  -- (we recalc this in the tick handler if necessary)
  self.subtick_time = clock.get_beat_sec() / self.ppqn

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
  App:register_params()

  -- Create the tracks
  params:add_separator('tracks','Tracks')
  for i = 1, 16 do
    self.track[i] = Track:new({id = i})
  end

  -- Create Shared Components (Scales, Outputs)
  params:add_separator('scales','Scales')
  for i = 0, 3 do
    self.scale[i] = Scale:new({id = i})
  end

  for i = 1, 16 do
    self.output[i] = Output:new({id = i, type = 'midi', channel = i})
  end
  for i = 1, 2 do
    self.crow.output[i] = Output:new({id = i, type = 'crow', channel = i})
  end

  ----------------------------------------------------------------------------
  -- Device & Mode Registration
  ----------------------------------------------------------------------------
  App:register_midi_in(1)
  App:register_midi_out(2)
  App:register_midi_grid(3)
  App:register_launchcontrol(9)
  App:register_mixer(4)
  App:register_bluebox(5)

  print('params:default')
  params:default()

  App:register_modes()

  ----------------------------------------------------------------------------
  -- Start Master Subtick Clock
  ----------------------------------------------------------------------------
  -- This coroutine will run continuously to emit 'subtick' events for fine microtiming.
  self.subtick_clock = clock.run(function() self:run_subtick_clock() end)
end

--==============================================================================
-- Playback Control Functions (Start, Stop, etc.)
--==============================================================================
function App:start(continue)
  print('App start')
  self.playing = true
  self.tick = 0
  self.start_time = clock.get_beats()
  self.last_time  = clock.get_beats()

  local event
  if continue then
    event = { type = 'continue' }
    self.midi_in:continue()
    self.midi_out:continue()
    -- self.bluebox:continue()
  else
    event = { type = 'start' }
    self.midi_in:start()
    self.midi_out:start()
    -- self.bluebox:start()
  end

  ----------------------------------------------------------------------------
  -- Transport Tick Loop using 96 PPQN
  ----------------------------------------------------------------------------
  if params:get('clock_source') == 1 then
    self.clock = clock.run(function()
      while true do
        clock.sync(1 / self.ppqn)
        App:send_tick()
        App.screen_dirty = true
      end
    end)
    
    for i = 1, #self.track do
      self.track[i]:process_transport(event)
    end
  else
    self.midi_out:clock()
  end
end

function App:stop()
  print('App stop')
  self.playing = false
  
  if params:get('clock_source') > 1 then
    self.midi_in:stop()
    self.midi_out:stop()
    -- self.bluebox:stop()
  end

  if params:get('clock_source') == 1 then
    if self.clock then
      clock.cancel(self.clock)
    end
    for i = 1, #self.track do
      self.track[i]:process_transport({ type = 'stop' })
    end
  end
end

function App.apply(settings)
  for k, v in pairs(settings) do
    params:set(k, v)
  end
end

--==============================================================================
-- Tick and Transport Handling
--==============================================================================
-- Called from the main clock loop (using ppqn = 96)
function App:send_tick()
  self:on_tick()
end

-- The on_tick function updates the tick counter, recalculates subtick_time,
-- and dispatches clock events to tracks.
function App:on_tick()
  self.last_time = clock.get_beats()
  self.tick = self.tick + 1
  self.midi_out:clock()

  -- Recalculate subtick_time based on current tempo:
  self.subtick_time = clock.get_beat_sec() / self.ppqn
  
  if params:get('clock_source') == 1 then
    -- Dispatch clock events to all tracks
    for i = 1, #self.track do
      self.track[i]:process_transport({ type = 'clock' })
    end
  end
end

----------------------------------------------------------------------------
-- Master Subtick Clock
----------------------------------------------------------------------------
-- This coroutine runs continuously and emits a "subtick" event at a finer subdivision
-- than the main tick. This can be used for microtiming adjustments and dynamic note offsets.
function App:run_subtick_clock()
  while true do
    local beat_sec = clock.get_beat_sec()  -- seconds per beat at current tempo
    local sleep_time = beat_sec / (self.ppqn * self.subdivision)
    clock.sync(sleep_time)
    self:emit('subtick', sleep_time)
  end
end

--==============================================================================
-- Transport Event Handling (MIDI In, Clock, etc.)
--==============================================================================
function App:on_transport(data)
  if params:get('clock_source') > 1 then
    if data.type == "start" then
      self:start()
    elseif data.type == "continue" then
      self:start(true)
    elseif data.type == "stop" then
      self:stop()
    elseif data.type == "clock" then
      self:on_tick()
    end

    for i = 1, #self.track do
      self.track[i]:process_transport(data)
    end

    self.screen_dirty = true
  end
end

function App:on_midi(data)
  if App.debug then
    tab.print(data)
  end
end

--==============================================================================
-- CC Event Handling
--==============================================================================
function App:on_cc(data)
  if self.cc_subscribers[data.cc] then
    for _, func in ipairs(self.cc_subscribers[data.cc]) do
      func(data)
    end
  end

  -- Pass CC event to the current mode (if it defines an on_cc handler)
  if self.mode[self.current_mode] then
    self.mode[self.current_mode]:emit('cc', data)
  end

  self.midi_out:send(data)
end

function App:subscribe_cc(cc_number, func)
  if not self.cc_subscribers[cc_number] then
    self.cc_subscribers[cc_number] = {}
  end
  table.insert(self.cc_subscribers[cc_number], func)
end

function App:unsubscribe_cc(cc_number, func)
  if self.cc_subscribers[cc_number] then
    for i, subscriber in ipairs(self.cc_subscribers[cc_number]) do
      if subscriber == func then
        table.remove(self.cc_subscribers[cc_number], i)
        break
      end
    end
  end
end

--==============================================================================
-- Crow & Mixer Query/Registration (Device Management)
--==============================================================================
function App:crow_query(i)
  crow.send('input[' .. i .. '].query()')
end

function App:register_mixer(n)
  self.mixer.event = nil
  self.mixer = midi.connect(n)
  
  self.mixer.event = function(msg)
    local data = midi.to_msg(msg)
    
    if data.type == 'cc' then
      self.bluebox:send(data)
    end

    if data.type == 'note_on' then
      local send = LaunchControl:handle_note(data)
      if send then 
        App.bluebox:send(send)
      end
      LaunchControl:set_led()
    end
  end

  function LaunchControl:on_up(state)
    App.send_in = state
  end

  function LaunchControl:on_down(state)
    App.send_out = state
  end
end

function App:register_launchcontrol(n)
  LaunchControl:register(n)
  LaunchControl:set_led()
end

function App:register_bluebox(n)
  self.bluebox = midi.connect(n)
end

--==============================================================================
-- MIDI In/Out and Grid Registration
--==============================================================================
function App:register_midi_in(n)
  if self.midi_in_cleanup then
    for _, cleanup in ipairs(self.midi_in_cleanup) do
      cleanup()
    end
  end
  self.midi_in_cleanup = {}
  self.midi_in = self.device_manager:get(n)
  print('Registering MIDI In Device ' .. n)
  
  table.insert(self.midi_in_cleanup, self.midi_in:on('transport_event', function(data) self:on_transport(data) end))
  table.insert(self.midi_in_cleanup, self.midi_in:on('cc', function(data) self:on_cc(data) end))
end

function App:register_midi_out(n)
  self.midi_out = self.device_manager:get(n)
end

function App:register_midi_grid(n)
  self.midi_grid = self.device_manager:get(n)
  self.midi_grid:send({240,0,32,41,2,13,0,127,247}) -- Set Launchpad to Programmer Mode
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
  screen.ping()
  screen.clear()         -- Clear screen space
  screen.aa(1)           -- Enable anti-aliasing
  self.mode[self.current_mode]:draw()
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
end

function App:handle_key(k, z)
  local context = self.mode[self.current_mode].context
  if k == 1 then
    self.alt_down = (z == 1)
  elseif self.alt_down and z == 1 and context['alt_fn_' .. k] then
    context['alt_fn_' .. k]()
  elseif z == 1 then
    self.key_down = util.time()
  elseif not self.alt_down then
    local hold_time = util.time() - self.key_down
    if hold_time > 0.3 and context['long_fn_' .. k] then
      context['long_fn_' .. k]()
    elseif context['press_fn_' .. k] then
      context['press_fn_' .. k]()
    end
  end
end

function App:panic()
  for i = 1, 4 do
    crow.output[i].volts = 0
  end
  clock.run(function()
    for c = 1, 16 do
      for i = 0, 127 do
        local off = { note = i, type = 'note_off', ch = c, vel = 0 }
        App.midi_out:send(off)
        clock.sleep(.01)
      end
    end
  end)
end

--==============================================================================
-- Parameter Registration and Song Settings
--==============================================================================
function App:register_params()
  local midi_devices = self.device_manager.midi_device_names
  params:add_group('DEVICES', 8)
  params:add_option("midi_in", "MIDI In", midi_devices, 1)
  params:add_option("midi_out", "MIDI Out", midi_devices, 2)
  params:add_option("mixer", "Mixer", midi_devices, 4)
  params:add_option("midi_grid", "Grid", midi_devices, 3)
  params:add_option("launchcontrol", "LaunchControl", midi_devices, 9)
  params:add_option("bluebox", "BlueBox", midi_devices, 5)
  
  params:add_trigger('panic', "Panic")
  params:set_action('panic', function() App:panic() end)
  params:set_action("midi_in", function(x) App:register_midi_in(x) end)
  params:set_action("midi_out", function(x) App:register_midi_out(x) end)
  params:set_action("midi_grid", function(x) App:register_midi_grid(x) end)
  params:set_action("mixer", function(x) App:register_mixer(x) end)
  params:set_action("launchcontrol", function(x) App:register_launchcontrol(x) end)
  params:set_action("bluebox", function(x) App:register_bluebox(x) end)
  
  params:add_separator()
  App:register_song()
end

function App:save_preset(d, param)
  if self.preset[d] == nil then self.preset[d] = {} end
  local preset = self.preset[d]
  
  if type(param) == 'string' then
    local value = self.settings[param]
    if preset[param] ~= value then
      preset[param] = value
    end
  elseif type(param) == 'table' then
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
  if preset == nil then error('App:load_preset was nil') return end
  
  if type(param) == 'string' then
    local value = preset[param]
    if force or (self.settings[param] ~= value) then
      params:set(param, value)
    end
  elseif type(param) == 'table' then
    for index, name in ipairs(param) do
      local value = preset[name]
      if force or (value and self.settings[name] ~= value) then
        params:set(name, value)
      end
    end
  else
    for name, value in pairs(preset) do
      if self.settings[name] ~= value then
        params:set(name, value)
      end
    end
  end
end

function App:register_song()
  local swing_spec = controlspec.UNIPOLAR:copy()
  swing_spec.default = 0.5
  self.swing = 0.5
  params:add_control('swing', 'Swing', swing_spec)
  params:set_action('swing', function(d) self.swing = d end)
end

--==============================================================================
-- Bezier Curve Mapping (for CC, etc.)
--==============================================================================
local A = {x = 0, y = 0}            -- Minimum output control point
local B = {x = 0, y = 1.13}         -- Control point for curve shaping
local C = {x = 0.77, y = 0.64}      -- Control point for curve shaping
local D = {x = 1, y = 1}            -- Maximum output control point

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
-- Register Mixer, LaunchControl, BlueBox, etc.
--==============================================================================
function App:register_mixer(n)
  self.mixer.event = nil
  self.mixer = midi.connect(n)
  
  self.mixer.event = function(msg)
    local data = midi.to_msg(msg)
    if data.type == 'cc' then
      self.bluebox:send(data)
    end
    if data.type == 'note_on' then
      local send = LaunchControl:handle_note(data)
      if send then 
        App.bluebox:send(send)
      end
      LaunchControl:set_led()
    end
  end

  function LaunchControl:on_up(state)
    App.send_in = state
  end

  function LaunchControl:on_down(state)
    App.send_out = state
  end
end

function App:register_launchcontrol(n)
  LaunchControl:register(n)
  LaunchControl:set_led()
end

function App:register_bluebox(n)
  self.bluebox = midi.connect(n)
end

--==============================================================================
-- Modes and Grid Registration
--==============================================================================
function App:register_modes()
  self.grid = Grid:new({
    grid_start = {x = 1, y = 1},
    grid_end = {x = 4, y = 1},
    display_start = {x = 1, y = 1},
    display_end = {x = 4, y = 1},
    offset = {x = 4, y = 8},
    midi = App.midi_grid.device,
    event = function(s, data)
      if data.state then
        s:reset()
        local mode = App.mode[App.current_mode]
        mode.arrow_pads:reset()
        mode.alt_pad:reset()
        mode.row_pads:reset()
        App.current_mode = s:grid_to_index(data)
        for i = 1, #App.mode do
          if i ~= App.current_mode then
            App.mode[i]:disable()
          end
        end
        App.mode[App.current_mode]:enable()
        s.led[data.x][data.y] = 1
        s:refresh()
      end
    end,
    active = true
  })

  self.midi_grid.event = function(msg)
    local mode = self.mode[self.current_mode]
    self.grid:process(msg)
    mode.grid:process(msg)
  end

  local SessionMode = require('Foobar/lib/modes/session')
  local DrumsMode   = require('Foobar/lib/modes/drums')
  local KeysMode    = require('Foobar/lib/modes/keys')
  local UserMode    = require('Foobar/lib/modes/user')
  
  self.mode[1] = SessionMode
  self.mode[2] = DrumsMode
  self.mode[3] = KeysMode
  self.mode[4] = UserMode
  
  self.mode[1]:enable()
end

--==============================================================================
-- Return the App Class
--==============================================================================
return App