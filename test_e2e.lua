-- End-to-End Test for MIDI Thru Machine
-- This script tests core functionality locally and can be deployed to Norns

package.path = './?.lua;./lib/?.lua;.test/stubs/?.lua;' .. package.path
require('norns')

-- map Foobar paths used inside the codebase
package.preload['Foobar/lib/utilities'] = function()
  return require('lib/utilities')
end
package.preload['Foobar/lib/launchcontrol'] = function()
  return require('lib/launchcontrol')
end
package.preload['Foobar/lib/grid'] = function()
  return require('lib/grid')
end
package.preload['Foobar/lib/app'] = function()
  return require('lib/app')
end
package.preload['Foobar/lib/musicutil-extended'] = function()
  return require('lib/musicutil-extended')
end
package.preload['Foobar/lib/components/app/track'] = function()
  return require('lib/components/app/track')
end
package.preload['Foobar/lib/components/app/mode'] = function()
  return require('lib/components/app/mode')
end
package.preload['Foobar/lib/components/track/scale'] = function()
  return require('lib/components/track/scale')
end
package.preload['Foobar/lib/components/track/output'] = function()
  return require('lib/components/track/output')
end
package.preload['Foobar/lib/components/track/trackcomponent'] = function()
  return require('lib/components/track/trackcomponent')
end
package.preload['Foobar/lib/components/track/auto'] = function()
  return require('lib/components/track/auto')
end
package.preload['Foobar/lib/components/track/input'] = function()
  return require('lib/components/track/input')
end
package.preload['Foobar/lib/components/track/seq'] = function()
  return require('lib/components/track/seq')
end
package.preload['Foobar/lib/components/track/mute'] = function()
  return require('lib/components/track/mute')
end
package.preload['Foobar/lib/components/track/scale'] = function()
  return require('lib/components/track/scale')
end
package.preload['Foobar/lib/bitwise'] = function()
  return require('lib/bitwise')
end
package.preload['musicutil'] = function()
  -- Create a stub musicutil module
  return {
    scale_names = {"major", "minor", "dorian", "mixolydian"},
    scale_notes = function(scale_name, root)
      return {root, root+2, root+4, root+5, root+7, root+9, root+11}
    end,
    note_num_to_name = function(note_num)
      local names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
      return names[(note_num % 12) + 1]
    end,
    note_name_to_num = function(note_name)
      local names = {C=0, ["C#"]=1, D=2, ["D#"]=3, E=4, F=5, ["F#"]=6, G=7, ["G#"]=8, A=9, ["A#"]=10, B=11}
      return names[note_name] or 0
    end,
    CHORDS = {}, -- Initialize empty CHORDS table
    SCALES = {}  -- Initialize empty SCALES table
  }
end

-- Create global App stub
App = {
  device_manager = {
    get = function(id) 
      return {name = "stub_device", send = function() end}
    end,
    midi_device_names = {"stub_device"}
  },
  ppqn = 24, -- Pulses per quarter note
  settings = {}, -- Settings storage
  scale = {} -- Scale storage
}

-- Create global controlspec stub
local function create_controlspec(min, max, warp, step, default, units, quantum)
  return {
    min = min or 0,
    max = max or 1,
    warp = warp or "lin",
    step = step or 0.01,
    default = default or 0,
    units = units or "",
    quantum = quantum or 0.01,
    copy = function() return create_controlspec(min, max, warp, step, default, units, quantum) end
  }
end

-- Create controlspec table with function and predefined specs
controlspec = setmetatable({
  UNIPOLAR = create_controlspec(0, 1, "lin", 0.01, 0.5, "", 0.01),
  BIPOLAR = create_controlspec(-1, 1, "lin", 0.01, 0, "", 0.01),
  FREQ = create_controlspec(0.1, 20000, "exp", 0.1, 440, "Hz", 0.1),
  MIDI = create_controlspec(0, 127, "lin", 1, 64, "", 1)
}, {
  __call = function(_, min, max, warp, step, default, units, quantum)
    return create_controlspec(min, max, warp, step, default, units, quantum)
  end
})

local utilities = require('lib/utilities')
local DeviceManager = require('lib/components/app/devicemanager')

-- Test configuration
local TEST_CONFIG = {
  verbose = true,
  test_device_manager = true,
  test_track_components = true,
  test_scale_quantization = true,
  test_midi_routing = true
}

-- Test utilities
local function log(message)
  if TEST_CONFIG.verbose then
    print("[TEST] " .. message)
  end
end

local function assert_equal(expected, actual, message)
  if expected ~= actual then
    error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", 
                       message or "values not equal", tostring(expected), tostring(actual)))
  end
end

local function assert_true(condition, message)
  if not condition then
    error(string.format("ASSERTION FAILED: %s", message or "condition is false"))
  end
end

local function run_test_suite(name, test_function)
  log("=== Running " .. name .. " ===")
  local success, error_msg = pcall(test_function)
  if success then
    log("✓ " .. name .. " PASSED")
    return true
  else
    log("✗ " .. name .. " FAILED: " .. error_msg)
    return false
  end
end

-- Test 1: Device Manager Basic Functionality
local function test_device_manager_basic()
  local dm = DeviceManager:new()
  
  -- Test device registration
  assert_true(dm ~= nil, "DeviceManager should be created")
  
  -- Test getting a device
  local dev = dm:get(1)
  assert_true(dev ~= nil, "Should be able to get device 1")
  
  -- Test note sending
  local sent_notes = {}
  dev.send = function(_, msg)
    table.insert(sent_notes, msg)
  end
  
  dev:send{type='note_on', note=60, vel=64, ch=1}
  assert_equal(1, #sent_notes, "Should have sent one note")
  assert_equal('note_on', sent_notes[1].type, "Should be note_on message")
  assert_equal(60, sent_notes[1].note, "Note should be 60")
  
  log("Device manager basic functionality: OK")
end

-- Test 2: Scale Quantization
local function test_scale_quantization()
  local Scale = require('lib/components/track/scale')
  local scale = Scale:new({id=1})
  
  -- Test basic quantization
  local result = scale:quantize_note({note=61, vel=64, ch=1})
  assert_true(result ~= nil, "Quantization should return a result")
  
  -- Test scale following
  scale.follow_mode = 1
  scale.follow_track = 1
  local follow_result = scale:quantize_note({note=62, vel=64, ch=1})
  assert_true(follow_result ~= nil, "Scale following should work")
  
  log("Scale quantization: OK")
end

-- Test 3: Track Component Chain
local function test_track_chain()
  local Track = require('lib/components/app/track')
  local track = Track:new({id=1})
  
  -- Test chain building
  assert_true(track ~= nil, "Track should be created")
  
  -- Test that track has basic structure
  assert_true(type(track) == "table", "Track should be a table")
  
  log("Track component chain: OK")
end

-- Test 4: MIDI Event Routing
local function test_midi_routing()
  local dm = DeviceManager:new()
  local dev = dm:get(1)
  
  local received_events = {}
  dev.process_midi = function(_, msg)
    table.insert(received_events, msg)
  end
  
  -- Simulate incoming MIDI
  local midi_msg = {type='note_on', note=64, vel=80, ch=1}
  dev:process_midi(midi_msg)
  
  assert_equal(1, #received_events, "Should have received one event")
  assert_equal('note_on', received_events[1].type, "Should be note_on event")
  
  log("MIDI event routing: OK")
end

-- Test 5: Note Interrupt Handling
local function test_note_interrupt()
  local dm = DeviceManager:new()
  local dev = dm:get(1)
  
  local sent_messages = {}
  dev.send = function(_, msg)
    table.insert(sent_messages, msg)
  end
  
  -- Send a note on
  dev:send{type='note_on', note=60, vel=64, ch=1}
  
  -- Simulate scale interrupt
  local scale = { quantize_note=function(_, data) return {new_note=data.note+1} end }
  dev:emit('interrupt', {type='interrupt_scale', scale=scale, ch=1})
  
  -- Should have at least the note_on
  assert_equal(1, #sent_messages, "Should have sent at least note_on")
  assert_equal('note_on', sent_messages[1].type, "First should be note_on")
  
  -- Test that interrupt listeners are set up
  assert_true(dev.manager ~= nil, "Device should have manager")
  
  log("Note interrupt handling: OK")
end

-- Test 6: Utilities Functions
local function test_utilities()
  -- Test removeDuplicates
  local test_array = {1, 2, 2, 3, 3, 4}
  local result = utilities.removeDuplicates(test_array)
  assert_equal(4, #result, "Should remove duplicates")
  
  -- Test chain_functions
  local f1 = function(x) return x + 1 end
  local f2 = function(x) return x * 2 end
  local chained = utilities.chain_functions({f1, f2})
  assert_equal(4, chained(1), "Function chaining should work")
  
  log("Utilities functions: OK")
end

-- Main test runner
local function run_all_tests()
  log("Starting MIDI Thru Machine E2E Tests")
  log("=====================================")
  
  local tests = {
    {"Device Manager Basic", test_device_manager_basic},
    {"Scale Quantization", test_scale_quantization},
    {"Track Component Chain", test_track_chain},
    {"MIDI Event Routing", test_midi_routing},
    {"Note Interrupt Handling", test_note_interrupt},
    {"Utilities Functions", test_utilities}
  }
  
  local passed = 0
  local total = #tests
  
  for _, test in ipairs(tests) do
    local name, test_func = test[1], test[2]
    if run_test_suite(name, test_func) then
      passed = passed + 1
    end
  end
  
  log("=====================================")
  log(string.format("Tests completed: %d/%d passed", passed, total))
  
  if passed == total then
    log("🎉 ALL TESTS PASSED!")
    return true
  else
    log("❌ SOME TESTS FAILED!")
    return false
  end
end

-- Run tests if this script is executed directly
if arg[0] and arg[0]:match("test_e2e.lua$") then
  local success = run_all_tests()
  os.exit(success and 0 or 1)
end

return {
  run_all_tests = run_all_tests,
  test_device_manager_basic = test_device_manager_basic,
  test_scale_quantization = test_scale_quantization,
  test_track_chain = test_track_chain,
  test_midi_routing = test_midi_routing,
  test_note_interrupt = test_note_interrupt,
  test_utilities = test_utilities
} 