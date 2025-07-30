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
local path_name     = 'Foobar/lib/'
local utilities     = require(path_name .. 'utilities')
local Grid          = require(path_name .. 'grid')
local Track         = require('Foobar/lib/components/app/track')
local Scale         = require('Foobar/lib/components/track/scale')
local Output        = require('Foobar/lib/components/track/output')
local Mode          = require('Foobar/lib/components/app/mode')
local musicutil     = require(path_name .. 'musicutil-extended')
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



function App:set_font(n)
  local fonts = {
    {name = '04B_03', face = 1, size = 8},
    {name = 'ALEPH', face = 2, size = 8},
    {name = 'tom-thumb', face = 25, size = 6},
    {name = 'creep', face = 26, size = 16},
    {name = 'ctrld', face = 27, size = 10},
    {name = 'ctrld', face = 28, size = 10},
    {name = 'ctrld', face = 29, size = 13},
    {name = 'ctrld', face = 30, size = 13},
    {name = 'ctrld', face = 31, size = 13},
    {name = 'ctrld', face = 32, size = 13},
    {name = 'ctrld', face = 33, size = 16},
    {name = 'ctrld', face = 34, size = 16},
    {name = 'ctrld', face = 35, size = 16},
    {name = 'ctrld', face = 36, size = 16},
    {name = 'scientifica', face = 37, size = 11},
    {name = 'scientifica', face = 38, size = 11},
    {name = 'scientifica', face = 39, size = 11},
    {name = 'ter', face = 40, size = 12},
    {name = 'ter', face = 41, size = 12},
    {name = 'ter', face = 42, size = 14},
    {name = 'ter', face = 43, size = 14},
    {name = 'ter', face = 44, size = 14},
    {name = 'ter', face = 45, size = 16},
    {name = 'ter', face = 46, size = 16},
    {name = 'ter', face = 47, size = 16},
    {name = 'ter', face = 48, size = 18},
    {name = 'ter', face = 49, size = 18},
    {name = 'ter', face = 50, size = 20},
    {name = 'ter', face = 51, size = 20},
    {name = 'ter', face = 52, size = 22},
    {name = 'ter', face = 53, size = 22},
    {name = 'ter', face = 54, size = 24},
    {name = 'ter', face = 55, size = 24},
    {name = 'ter', face = 56, size = 28},
    {name = 'ter', face = 57, size = 28},
    {name = 'ter', face = 58, size = 32},
    {name = 'ter', face = 59, size = 32},
    {name = 'unscii', face = 60, size = 16},
    {name = 'unscii', face = 61, size = 16},
    {name = 'unscii', face = 62, size = 8},
    {name = 'unscii', face = 63, size = 8},
    {name = 'unscii', face = 64, size = 8},
    {name = 'unscii', face = 65, size = 8},
    {name = 'unscii', face = 66, size = 16},
    {name = 'unscii', face = 67, size = 8}
  }
  screen.font_face(fonts[n].face)
  screen.font_size(fonts[n].size)
end

local function draw_tempo()
  if App.playing then
      local beat = 15 - math.floor((App.tick % App.ppqn) / App.ppqn * 16)
      screen.level(beat)
  else
      screen.level(5)
  end
  
  screen.rect(76, 0, 127, 32)
  screen.fill()

  screen.move(102, 28)
  App:set_font(34)
  screen.level(0)
  screen.text_center(math.floor(clock.get_tempo() + 0.5))
  screen.fill()

  
  screen.level(0)
  
  if App.playing then
    App:set_font(5)
    screen.move(79, 7)
    screen.text('\u{25b8}')
  else
    App:set_font(1)
    screen.move(79, 7)
    screen.text('||')
  end
  
  App:set_font(1)
  screen.move(124, 7)
  local quarter = math.floor(App.tick / (App.ppqn) )
  local measure = math.floor(quarter / 4) + 1
  local count = math.floor(quarter % 4) + 1
  screen.text_right( measure .. ':' .. count)
  screen.fill()


  if App.recording  then
    screen.level(0)
    App:set_font(1)
    screen.move(85, 7)
    screen.text('REC')
    screen.fill()
  end
end

local function draw_chord(select, x, y)
  x = x or 60
  y = y or 14
  local scale = App.scale[select]
  local chord = scale.chord
  if chord and #scale.intervals > 2 then
      local name = chord.name
      local root = chord.root + scale.root
      local bass = scale.root
      
      screen.level(15)
      App:set_font(37)
      screen.move(x, y + 12)
      screen.text(musicutil.note_num_to_name(root))
      local name_offset = screen.text_extents(musicutil.note_num_to_name(root)) + x
      App:set_font(9)
      
      screen.move(name_offset, y)
      screen.text(name)
      screen.fill()
      
      if bass ~= root then
      screen.move(name_offset, y + 12)
      screen.text('/' .. musicutil.note_num_to_name(bass))
      end
  end
end

local function draw_chord_small(select, x, y)
  x = x or 60
  y = y or 46
  local scale = App.scale[select]
  local chord = scale.chord
  if chord and #scale.intervals > 2 then
      local name = chord.name
      local root = chord.root + scale.root
      local bass = scale.root
      
      screen.level(15)
      App:set_font(1)
      screen.move(x, y)
      screen.text(musicutil.note_num_to_name(root) .. name)
      screen.fill()
  end
end

function draw_intervals(select, x, y)
  x = x or 0
  y = y or 63
  screen.move(127, 41)

  local interval_names = {'R', 'b2', '2', 'b3', '3', '4', 'b5', '5', 'b6', '6', 'b7', '7'}

  App:set_font(1)
  for i = 1, #interval_names do
      if App.scale[1].bits & (1 << (i - 1)) > 0 then
              screen.level(15)
      else
              screen.level(1)
      end
      screen.move(i * 10 + x, y)
      screen.text_center(interval_names[i])
      screen.fill()
  end
end
  
function draw_tag(label, value, x, y)
  x = x or 0
  y = y or 35
  screen.level(0)
  screen.rect(x, y, 128, 29)
  screen.fill()
  
  screen.level(15)
  screen.rect(x, y, 32, 32)
  screen.fill()
  
  screen.level(0)
  screen.move(x + 1, y + 7)
  screen.text(label)
  
  screen.move(x + 16, y + 27)
  App:set_font(34)
  screen.text_center(value)
  
  App:set_font(1)
  screen.move(x + 16, y + 17)
  screen.text_center('shit')
  screen.fill()
end

local function draw_status()
  App:set_font(1)
  screen.level(15)
  screen.rect(0, 0, 10, 9)
  screen.fill()
  screen.level(0)
  screen.move(5,7)
  screen.text_center(App.current_track)
  screen.fill()
  
  screen.level(15)
  screen.move(15,7)
  screen.text(App.track[App.current_track].name )
  
  App:set_font(5)
  screen.move(0,20)
  screen.text('\u{25b8}')
  screen.move(0,30)
  screen.text('\u{25c2}')

  App:set_font(1)


  local in_ch = 'off'
    if App.track[App.current_track].midi_in == 17 then
        in_ch = 'all'
    elseif App.track[App.current_track].midi_in ~= 0 then
      in_ch = App.track[App.current_track].midi_in
    end
    screen.move(6,20)
    screen.text(App.track[App.current_track].input_device.abbr)

    screen.move(70,20)
    screen.text_right(in_ch)

    screen.fill()
  
  local out_ch = 'off'
    if App.track[App.current_track].midi_out == 17 then
        out_ch = 'all'
    elseif App.track[App.current_track].midi_out ~= 0 then
      out_ch = App.track[App.current_track].midi_out
    end

    screen.move(6,30)
    screen.text(App.track[App.current_track].output_device.abbr)

    screen.move(70,30)
    screen.text_right(out_ch)

    screen.fill()
  


  screen.move(6,20)
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
  self.recording = false
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
  self.ppqn = 24
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
    long_fn_2 = function()
      self.recording = not self.recording
      print('Recording: ' .. tostring(self.recording))
      self.screen_dirty = true
    end,
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
    press_fn_3 = function() print('press 3') end,
    screen = function()
      draw_tempo()
      
      local track_name = params:get('track_' .. App.current_track .. '_name')
      
      if App.track[App.current_track].enabled then
        screen.level(10)
      else
              screen.level(2)
      end
      
      draw_chord(1, 80, 45)
      draw_chord_small(2)
      -- draw_intervals(1)

      draw_status()
    end
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
  self.midi_grid = {}  -- NOTE: must use Launch Pad Device 2
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
  params:add_separator('tracks','Tracks')
  for i = 1, 16 do
    self.track[i] = Track:new({id = i})
  end

  -- Create Shared Components (Scales, Outputs)
  params:add_separator('scales','Scales')
  for i = 0, 3 do
    self.scale[i] = Scale:new({id = i})
  end
 

  ----------------------------------------------------------------------------
  -- Device & Mode Registration
  ----------------------------------------------------------------------------
  App:register_midi_in(1)
  -- App:register_midi_grid(3)

  -- App:register_mixer(6)
  -- App:register_launchcontrol(8)

  print('params:default')
  params:default()


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

  for i = 1, #self.track do
    if continue then
      self.track[i].output_device:start()
    else
      self.track[i].output_device:continue()
    end
  end

  ----------------------------------------------------------------------------
  -- Transport Tick Loop using PPQN
  ----------------------------------------------------------------------------
  if params:get('clock_source') == 1 then
    self.clock = clock.run(function()
      while true do
        clock.sync(1 / self.ppqn)
        App:send_tick()
        App.screen_dirty = true
      end
    end)
  end
end

function App:stop()
  print('App stop')
  self.playing = false

  for i = 1, #self.track do
    self.track[i].output_device:stop()
  end

  if params:get('clock_source') == 1 then
    if self.clock then
      clock.cancel(self.clock)
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
function App:send_tick()
  self:on_tick()
end

-- The on_tick function updates the tick counter,
-- and dispatches clock events to tracks.
function App:on_tick()
  self.last_time = clock.get_beats()
  self.tick = self.tick + 1
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
  print('Registering MIDI In Device from port ' .. n)
  
  table.insert(self.midi_in_cleanup, self.midi_in:on('transport_event', function(data) self:on_transport(data) end))
end

function App:register_midi_grid(n)
  print('Register Grid Device ' .. n)
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

--==============================================================================
-- Parameter Registration and Song Settings
--==============================================================================
-- function App:register_params()
--   local midi_devices = self.device_manager.midi_device_names
--   params:add_group('DEVICES', 5)
--   params:add_option("midi_in", "Clock Input", midi_devices, 1)
--   params:add_option("mixer", "Mixer", midi_devices, 4)
--   params:add_option("midi_grid", "Grid", midi_devices, 3)
--   params:add_option("launchcontrol", "LaunchControl", midi_devices, 9)
  
--   params:add_trigger('panic', "Panic")
--   params:set_action('panic', function() App:panic() end)
--   params:set_action("midi_in", function(x) App:register_midi_in(x) end)
--   params:set_action("midi_grid", function(x) App:register_midi_grid(x) end)
--   params:set_action("mixer", function(x) App:register_mixer(x) end)
--   params:set_action("launchcontrol", function(x) App:register_launchcontrol(x) end)
  
--   params:add_separator()
--   App:register_song()
-- end

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
-- Modes and Grid Registration
--==============================================================================
function App:register_modes()
  self.modes = {}
  self.grid = Grid:new({
    grid_start = {x = 1, y = 1},
    grid_end = {x = 4, y = 1},
    display_start = {x = 1, y = 1},
    display_end = {x = 4, y = 1},
    offset = {x = 4, y = 8},
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
    active = true
  })

  self.midi_grid.event = function(msg)
    local mode = self.mode[self.current_mode]
    self.grid:process(msg)
    mode.grid:process(msg)
  end

  local SessionModePreset = require('Foobar/lib/modes/session-preset')
  local SessionModeNote = require('Foobar/lib/modes/session-note')
  local DrumsMode   = require('Foobar/lib/modes/drums')
  local KeysMode    = require('Foobar/lib/modes/keys')
  local UserMode    = require('Foobar/lib/modes/user')
  
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
-- Return the App Class
--==============================================================================
return App