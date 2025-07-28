-- Norns-side Busted test-runner
-- Usage inside matron REPL:
--   dofile('~/dust/code/Foobar/test/run_norns_test.lua')

-- ------------------------------------------------------------------
-- 1.  Set up paths for the Foobar project
-- ------------------------------------------------------------------
local project_root = "/home/we/dust/code/Foobar"
local test_dir = project_root .. "/test"

-- Adjust package.path so code + specs are visible
package.path = table.concat({
  test_dir .. "/?.lua",
  test_dir .. "/spec/?.lua", 
  project_root .. "/lib/?.lua",
  package.path,
}, ';')

-- ------------------------------------------------------------------
-- 0.  Bootstrap LuaRocks paths (if available)
-- ------------------------------------------------------------------
local rocks_ok = pcall(require, 'luarocks.loader')
if rocks_ok then
  print('[TEST] LuaRocks loader found – package.path patched for rocks')
else
  print('[TEST] LuaRocks loader not found – continuing without it')
end

-- ------------------------------------------------------------------
-- 2.  Try to load Busted with multiple fallback paths
-- ------------------------------------------------------------------
print("[TEST] Looking for Busted...")
print("[TEST] Current package.path: " .. package.path)

local busted_runner = nil
local busted_found = false

-- Try multiple approaches to find Busted
local busted_paths = {
  'busted.runner',
  'busted',
  '/usr/local/lib/lua/5.3/busted/runner.lua',
  '/usr/local/share/lua/5.3/busted/runner.lua',
  '/usr/lib/lua/5.3/busted/runner.lua',
  '/usr/share/lua/5.3/busted/runner.lua'
}

for _, path in ipairs(busted_paths) do
  local ok, result = pcall(require, path)
  if ok then
    print("[TEST] ✓ Found Busted at: " .. path)
    busted_runner = result
    busted_found = true
    break
  else
    print("[TEST] ✗ Not found at: " .. path)
  end
end

if not busted_found then
  print("[TEST] Busted not found in any standard location.")
  print("[TEST] Installed locations:")
  
  -- Try to find where Busted was installed
  local handle = io.popen("find /usr/local /usr -name 'busted*' 2>/dev/null | head -10")
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      print(result)
    else
      print("No busted files found in /usr/local or /usr")
    end
  end
  
  print("[TEST] Try reinstalling with: sudo luarocks install busted")
  return
end

-- ------------------------------------------------------------------
-- 3.  Set up Norns environment for testing
-- ------------------------------------------------------------------
print("[TEST] Setting up Norns environment...")

-- Create a minimal test environment that works with real Norns APIs
_G.App = _G.App or {
  device_manager = {
    get = function(id) 
      return {name = "norns_device", send = function() end}
    end,
    midi_device_names = {"norns_device"}
  },
  ppqn = 24,
  settings = {}
}

-- Helper function for tests
function create_test_track(id)
  return {
    id = id or 1,
    scale_select = 1,
    input_device = App.device_manager:get(1),
    output_device = App.device_manager:get(2)
  }
end

-- ------------------------------------------------------------------
-- 4.  Run a simple test to verify the environment works
-- ------------------------------------------------------------------
print("[TEST] Running basic environment test...")

local function run_basic_test()
  local utilities = require('lib/utilities')
  if utilities then
    print("[TEST] ✓ Utilities module loaded successfully")
    return true
  else
    print("[TEST] ✗ Failed to load utilities module")
    return false
  end
end

if run_basic_test() then
  print("[TEST] ✓ Basic environment test passed")
else
  print("[TEST] ✗ Basic environment test failed")
  return
end

-- ------------------------------------------------------------------
-- 5.  Try to run the actual test specs (with error handling)
-- ------------------------------------------------------------------
print("[TEST] Attempting to run test specs...")

local run = busted_runner({
  standalone = false,
  output = 'plain',
  pattern = '_spec$',
  verbose = true
})

local ok, err = pcall(run)
if ok and err == 0 then
  print("\n[TEST] ✓ All tests passed.")
else
  print("\n[TEST] ✗ Test failures detected or tests could not run.")
  print("[TEST] This is expected if test specs require stub files.")
end 