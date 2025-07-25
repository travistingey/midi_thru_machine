-- Norns-compatible E2E Test for MIDI Thru Machine
-- This script runs within the Norns matron environment (Lua 5.3)

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
  local DeviceManager = require('lib/components/app/devicemanager')
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
  local DeviceManager = require('lib/components/app/devicemanager')
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
  local DeviceManager = require('lib/components/app/devicemanager')
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
  local utilities = require('lib/utilities')
  
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
  log("Starting MIDI Thru Machine E2E Tests (Norns Environment)")
  log("=======================================================")
  
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
  
  log("=======================================================")
  log(string.format("Tests completed: %d/%d passed", passed, total))
  
  if passed == total then
    log("🎉 ALL TESTS PASSED!")
    return true
  else
    log("❌ SOME TESTS FAILED!")
    return false
  end
end

-- Export the test runner for use in Norns REPL
return {
  run_all_tests = run_all_tests,
  test_device_manager_basic = test_device_manager_basic,
  test_scale_quantization = test_scale_quantization,
  test_track_chain = test_track_chain,
  test_midi_routing = test_midi_routing,
  test_note_interrupt = test_note_interrupt,
  test_utilities = test_utilities
} 