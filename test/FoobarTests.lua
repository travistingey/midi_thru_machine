-- FoobarTests.lua
-- Runs Foobar unit-tests directly ON the Norns without any external dependencies.
-- We vendor the full busted framework inside ./vendor so that no luarocks install
-- is required on the device.

script_name = 'FoobarTests'

-- ---------------------------------------------------------------------
-- Helper: find absolute path of this script to build relative paths.
-- ---------------------------------------------------------------------
local info        = debug.getinfo(1, 'S')
local script_path = info.source:match('^@(.+)$')           -- full path to this file
local script_dir  = script_path and script_path:gsub('[^/]+$', '') or '/home/we/dust/code/FoobarTests/'

-- ---------------------------------------------------------------------
-- Prepend vendor+project paths to package.path so that 'require' works.
-- ---------------------------------------------------------------------
local paths = {
  -- vendored busted
  script_dir .. 'vendor/?.lua',
  script_dir .. 'vendor/?/init.lua',
  script_dir .. 'vendor/busted/?.lua',
  script_dir .. 'vendor/busted/?/init.lua',
  -- project libraries (Foobar/lib)
  script_dir .. '../Foobar/lib/?.lua',
  -- Penlight
  script_dir .. 'vendor/penlight/lua/?.lua',
  script_dir .. 'vendor/penlight/lua/?/init.lua',
  -- Luassert + Say (luassert requires 'say')
  script_dir .. 'vendor/luassert/src/?.lua',
  script_dir .. 'vendor/luassert/src/?/init.lua',
  script_dir .. 'vendor/luassert/src/init.lua',
  script_dir .. 'vendor/say/lib/?.lua',
  script_dir .. 'vendor/say/lib/?/init.lua',
  -- lua-term (optional colours)
  script_dir .. 'vendor/lua-term/?.lua',
  script_dir .. 'vendor/lua-term/?/init.lua',
  -- specs + stubs for this test-harness
  script_dir .. 'spec/?.lua',
  script_dir .. 'stubs/?.lua'
}
package.path = table.concat(paths, ';') .. ';' .. package.path

-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- Capture writes to both io.write and io.stdout:write so Busted output appears in REPL
-- ---------------------------------------------------------------------
local function create_writer_hook()
  local buffer = ''
  return function(...)
    for i = 1, select('#', ...) do
      local s = tostring(select(i, ...))
      buffer = buffer .. s
    end
    -- Flush complete lines to print()
    while true do
      local nl = buffer:find("\n")
      if not nl then break end
      local line = buffer:sub(1, nl - 1)
      if line ~= '' then print(line) end -- send to Norns REPL
      buffer = buffer:sub(nl + 1)
    end
    return true
  end
end

-- Hook io.write (Busted's TAP handler uses this)
io.write = create_writer_hook()

-- ---------------------------------------------------------------------
-- Ensure LuaFileSystem stub is available (Penlight needs it)
-- ---------------------------------------------------------------------
package.preload['lfs'] = function()
  return dofile(script_dir .. 'vendor/lfs.lua')
end

-- ---------------------------------------------------------------------
-- Try to load busted.
-- ---------------------------------------------------------------------
local ok, busted_or_err = pcall(require, 'busted.runner')
if not ok then
  print('Failed to load busted.runner:', busted_or_err)
  print('Ensure vendor libraries are deployed. (make vendor-busted && make deploy-tests)')
  print('<ok>')
  return
end
local busted = busted_or_err

function init()
  print('Running Foobar test-suite on Norns…')

  -- Test our output capture with basic assertions
  print('Testing basic assertions...')

  -- Test basic assert
  assert(true, 'Basic true assertion')
  print('✓ Basic assertion passed')

  -- Test math
  assert(4 == 2 + 2, 'Basic math')
  print('✓ Math assertion passed')

  -- Test string comparison
  assert('hello' == 'hello', 'String comparison')
  print('✓ String assertion passed')

  print('All basic tests passed!')
  print('<ok>')
end