-- FoobarTests.lua - Simple test framework for Norns
-- Based on working examples in test/lib/spec/
script_name = 'FoobarTests'
path_name = script_name .. '/lib/'

-- Load test framework
local tf = require('FoobarTests/lib/test_framework')

-- Load and run all spec files
local specs = {
  -- path_name .. 'spec/app_spec',
  path_name .. 'spec/bitwise_spec',
  path_name .. 'spec/device_manager_spec',
  path_name .. 'spec/devicemanager_note_handling_spec',
  -- path_name .. 'spec/grid_spec',
  path_name .. 'spec/input_spec',
  -- path_name .. 'spec/launchcontrol_spec',
  path_name .. 'spec/mode_spec',
  path_name .. 'spec/musicutil_extended_spec',
  path_name .. 'spec/mute_spec',
  path_name .. 'spec/output_spec',
  path_name .. 'spec/seq_spec',
  -- path_name .. 'spec/trackcomponent_spec'
}




function init()
  print("🧪 Running Foobar test-suite on Norns…")
  
  for _, spec_name in ipairs(specs) do
    require(spec_name)
  end
  -- Print summary
  local stats = tf.get_stats()
  print("")
  print("📊 Test Results:")
  print("  Passed: " .. stats.passed)
  print("  Failed: " .. stats.failed)
  print("  Total: " .. stats.total)
  
  if stats.failed == 0 then
    print("🎉 All tests completed successfully!")
  else
    print("💥 Some tests failed!")
  end
  
  print("<ok>")
end

function r()
	for script,value in pairs(package.loaded) do	
    script_name = 'FoobarTests'	
		if util.string_starts(script, script_name) then
			package.loaded[script] = nil
			_G[script] = nil
		end
	end
	norns.script.load(norns.state.script)
end