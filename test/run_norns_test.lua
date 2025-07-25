-- Norns test runner for MIDI Thru Machine
-- This script runs Busted tests in the actual Norns Lua 5.3 runtime environment

print("🧪 Running MIDI Thru Machine tests in Norns Lua 5.3 runtime...")
print("==============================================")

-- Set up the Lua path for Norns environment
package.path = './?.lua;./lib/?.lua;test/spec/?.lua;' .. package.path

-- Check if we're running in the actual Norns environment
local is_norns_runtime = (norns ~= nil and matron ~= nil)
if is_norns_runtime then
    print("✅ Running in Norns Lua 5.3 runtime")
    print("Lua version: " .. _VERSION)
else
    print("⚠️  Warning: Not running in Norns runtime")
    print("Lua version: " .. _VERSION)
end

-- Test bitwise operator support (Lua 5.3+ feature)
local bitwise_supported = pcall(function()
    local test = 1 << 2
    test = test & 3
    test = test | 4
    test = test ~ 1
    test = test >> 1
    return test
end)

if bitwise_supported then
    print("✅ Bitwise operators supported")
else
    print("❌ Bitwise operators NOT supported - this will cause test failures")
end

-- Run busted with plain output
local busted = require('busted')
local handler = require('busted.outputHandler')({ verbose = false, suppressPending = true })
local runner = require('busted.runner')({ standalone = false })

-- Run all test specs
local success = runner({ 'test/spec' })

if success then
    print("✅ All tests passed!")
else
    print("❌ Some tests failed!")
end

print("==============================================")
return success 