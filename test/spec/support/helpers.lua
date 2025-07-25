-- Test helper functions for MIDI Thru Machine tests
-- Provides common utilities for both local and Norns testing

local helpers = {}

-- Test configuration
helpers.TEST_CONFIG = {
  verbose = true,
  test_device_manager = true,
  test_track_components = true,
  test_scale_quantization = true,
  test_midi_routing = true
}

-- Logging function
function helpers.log(message)
  if helpers.TEST_CONFIG.verbose then
    print("[TEST] " .. message)
  end
end

-- Custom assertion functions
function helpers.assert_equal(expected, actual, message)
  if expected ~= actual then
    error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", 
                       message or "values not equal", tostring(expected), tostring(actual)))
  end
end

function helpers.assert_true(condition, message)
  if not condition then
    error(string.format("ASSERTION FAILED: %s", message or "condition is false"))
  end
end

function helpers.assert_not_nil(value, message)
  if value == nil then
    error(string.format("ASSERTION FAILED: %s", message or "value is nil"))
  end
end

function helpers.assert_table(value, message)
  if type(value) ~= "table" then
    error(string.format("ASSERTION FAILED: %s (expected table, got %s)", 
                       message or "value is not a table", type(value)))
  end
end

-- Test runner wrapper
function helpers.run_test_suite(name, test_function)
  helpers.log("=== Running " .. name .. " ===")
  local success, error_msg = pcall(test_function)
  if success then
    helpers.log("✓ " .. name .. " PASSED")
    return true
  else
    helpers.log("✗ " .. name .. " FAILED: " .. error_msg)
    return false
  end
end

-- Mock MIDI device for testing
function helpers.create_mock_midi_device()
  local device = {
    name = "mock_midi_device",
    sent = {},
    received = {},
    connected = true
  }
  
  device.send = function(_, msg)
    table.insert(device.sent, msg)
  end
  
  device.process_midi = function(_, msg)
    table.insert(device.received, msg)
  end
  
  device.clear = function()
    device.sent = {}
    device.received = {}
  end
  
  return device
end

-- Mock scale for testing
function helpers.create_mock_scale()
  local scale = {
    root = 0,
    mode = 1,
    follow_mode = 0,
    follow_track = 1
  }
  
  scale.quantize_note = function(_, data)
    return {
      note = data.note,
      vel = data.vel,
      ch = data.ch,
      new_note = data.note -- Default: no change
    }
  end
  
  return scale
end

-- Mock clock for testing
function helpers.create_mock_clock()
  local clock = {
    beats = 0,
    tempo = 120,
    running = false,
    tasks = {}
  }
  
  clock.run = function(fn)
    table.insert(clock.tasks, fn)
    return #clock.tasks
  end
  
  clock.cancel = function(id)
    if clock.tasks[id] then
      clock.tasks[id] = nil
    end
  end
  
  clock.get_beats = function()
    return clock.beats
  end
  
  clock.get_tempo = function()
    return clock.tempo
  end
  
  clock.advance = function(beats)
    clock.beats = clock.beats + beats
    -- Execute any pending tasks
    for _, task in ipairs(clock.tasks) do
      if task then
        task()
      end
    end
  end
  
  return clock
end

return helpers 