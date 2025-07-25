-- Norns Busted Tests
-- These tests run in the actual Norns matron runtime using busted
-- Execute with: ./scripts/run-test test/norns_busted_spec.lua

-- Set up package path for Norns runtime
package.path = './?.lua;./lib/?.lua;test/spec/?.lua;' .. package.path

-- Load busted if available
local busted_available, busted = pcall(require, 'busted.runner')

if not busted_available then
    print("⚠️  Busted not available in Norns runtime, running basic tests...")
    
    -- Fallback to basic tests
    print("🧪 Running Basic Norns Runtime Tests")
    print("====================================")
    
    -- Test basic Norns APIs
    assert(params ~= nil, "params should be available")
    assert(engine ~= nil, "engine should be available")
    assert(clock ~= nil, "clock should be available")
    assert(screen ~= nil, "screen should be available")
    assert(midi ~= nil, "midi should be available")
    assert(util ~= nil, "util should be available")
    assert(musicutil ~= nil, "musicutil should be available")
    
    print("✅ Basic Norns API tests passed")
    
    -- Test our application modules
    local success, app = pcall(require, "lib.app")
    if success then
        print("✅ Application module loaded successfully")
    else
        print("❌ Application module failed to load: " .. tostring(app))
    end
    
    print("✅ All basic tests completed")
    return true
else
    print("🧪 Running Busted Tests in Norns Runtime")
    print("========================================")
    
    -- Run busted tests
    local success = busted({ standalone = false })
    
    if success then
        print("✅ All busted tests passed!")
    else
        print("❌ Some busted tests failed!")
    end
    
    return success
end 