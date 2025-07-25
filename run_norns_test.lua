-- Simple test runner for Norns environment
-- Run this script directly in the Norns REPL or via maiden

local test = require('test_norns')
local success = test.run_all_tests()

if success then
  print("✅ All tests passed!")
else
  print("❌ Some tests failed!")
end

return success 