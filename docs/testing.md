# Testing Framework

This project uses a custom test framework that runs directly on Norns hardware without external dependencies.

## Overview

The test framework is designed to work within the constraints of the Norns environment:
- No external package managers (luarocks)
- No network dependencies during execution
- Self-contained test scripts
- Custom output capture for REPL compatibility

## Test Structure

### Test Script (`test/FoobarTests.lua`)

The main test script follows Norns conventions:

```lua
-- FoobarTests.lua - Simple test framework for Norns
local script_dir = debug.getinfo(1).source:match("@?(.*/)") or ""

-- Simple test framework
local TestFramework = {
  tests = {},
  passed = 0,
  failed = 0,
  current_suite = nil
}

function TestFramework.describe(name, fn)
  TestFramework.current_suite = name
  print("📋 " .. name)
  fn()
  TestFramework.current_suite = nil
end

function TestFramework.it(name, fn)
  local status, err = pcall(fn)
  if status then
    print("  ✅ " .. name)
    TestFramework.passed = TestFramework.passed + 1
  else
    print("  ❌ " .. name .. " - " .. tostring(err))
    TestFramework.failed = TestFramework.failed + 1
  end
end

-- Simple assertion functions that match luassert API
local assert = {
  is_true = function(value, message)
    if not value then
      error(message or "expected true, got " .. tostring(value))
    end
  end,
  
  is_false = function(value, message)
    if value then
      error(message or "expected false, got " .. tostring(value))
    end
  end,
  
  are = {
    equal = function(expected, actual, message)
      if expected ~= actual then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
      end
    end,
    
    same = function(expected, actual, message)
      -- Deep comparison for tables
      if type(expected) ~= type(actual) then
        error(message or "types don't match")
      end
      if type(expected) == "table" then
        for k, v in pairs(expected) do
          if actual[k] ~= v then
            error(message or "tables don't match at key " .. tostring(k))
          end
        end
        for k, v in pairs(actual) do
          if expected[k] ~= v then
            error(message or "tables don't match at key " .. tostring(k))
          end
        end
      else
        if expected ~= actual then
          error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
        end
      end
    end
  },
  
  is_table = function(value, message)
    if type(value) ~= "table" then
      error(message or "expected table, got " .. type(value))
    end
  end,
  
  is_number = function(value, message)
    if type(value) ~= "number" then
      error(message or "expected number, got " .. type(value))
    end
  end,
  
  is_nil = function(value, message)
    if value ~= nil then
      error(message or "expected nil, got " .. tostring(value))
    end
  end
}

-- Make functions globally available
_G.describe = TestFramework.describe
_G.it = TestFramework.it
_G.test_assert = assert  -- Use different name to avoid conflicts with Norns

function init()
  print("🧪 Running Foobar test-suite on Norns…")
  print("Looking for tests in: " .. script_dir .. 'lib/spec/')
  
  -- Load and run all spec files
  local specs = {
    'minimal_spec',
    'simple_spec',
    'example_spec',
    'app_spec',
    'bitwise_spec',
    'device_manager_spec',
    'devicemanager_note_handling_spec',
    'grid_spec',
    'input_spec',
    'launchcontrol_spec',
    'mode_spec',
    'musicutil_extended_spec',
    'mute_spec',
    'output_spec',
    'seq_spec',
    'trackcomponent_spec'
  }
  
  for _, spec_name in ipairs(specs) do
    local ok, err = pcall(function()
      dofile(script_dir .. 'lib/spec/' .. spec_name .. '.lua')
    end)
    if not ok then
      print("⚠️  Failed to load " .. spec_name .. ": " .. tostring(err))
    end
  end
  
  -- Print summary
  print("")
  print("📊 Test Results:")
  print("  Passed: " .. TestFramework.passed)
  print("  Failed: " .. TestFramework.failed)
  print("  Total: " .. (TestFramework.passed + TestFramework.failed))
  
  if TestFramework.failed == 0 then
    print("🎉 All tests completed successfully!")
  else
    print("💥 Some tests failed!")
  end
  
  print("<ok>")
end
```

### Test Specs (`test/lib/spec/`)

Individual test files follow this pattern:

```lua
-- test/lib/spec/example_spec.lua
require('norns')
local SomeModule = require('lib/some_module')

describe('SomeModule', function()
  it('should do something', function()
    local instance = SomeModule:new()
    test_assert.is_table(instance)
    test_assert.are.equal(expected, actual)
  end)
  
  it('should handle errors', function()
    test_assert.is_true(true)
    test_assert.is_false(false)
  end)
end)
```

## Available Assertions

The test framework provides these assertion functions:

### Basic Assertions
- `test_assert.is_true(value, message)` - Asserts value is true
- `test_assert.is_false(value, message)` - Asserts value is false
- `test_assert.is_nil(value, message)` - Asserts value is nil

### Type Assertions
- `test_assert.is_table(value, message)` - Asserts value is a table
- `test_assert.is_number(value, message)` - Asserts value is a number

### Comparison Assertions
- `test_assert.are.equal(expected, actual, message)` - Asserts equality
- `test_assert.are.same(expected, actual, message)` - Deep comparison for tables

## Running Tests

### On Norns Hardware

```bash
# Deploy and run tests
make test-norns

# Deploy tests only
make deploy-tests

# Run tests only (if already deployed)
make run-tests
```

### Test Output

Tests provide clear, emoji-enhanced output:

```
🧪 Running Foobar test-suite on Norns…
Looking for tests in: /home/we/dust/code/FoobarTests/lib/spec/
📋 Minimal test
  ✅ should pass
📋 Simple test
  ✅ should pass
  ✅ should do basic math
  ✅ should handle strings

📊 Test Results:
  Passed: 4
  Failed: 0
  Total: 4
🎉 All tests completed successfully!
```

## Writing Tests

### Test Structure

1. **Require dependencies**: Start with `require('norns')` and any modules you're testing
2. **Use describe blocks**: Group related tests with descriptive names
3. **Write individual tests**: Use `it()` for specific test cases
4. **Use test_assert**: All assertions use the `test_assert` prefix

### Example Test

```lua
require('norns')
local MyComponent = require('lib/components/my_component')

describe('MyComponent', function()
  it('should initialize correctly', function()
    local component = MyComponent:new{param=1}
    test_assert.is_table(component)
    test_assert.are.equal(1, component.param)
  end)
  
  it('should handle errors gracefully', function()
    local ok, err = pcall(function()
      MyComponent:new{invalid_param=true}
    end)
    test_assert.is_false(ok)
    test_assert.is_table(err)
  end)
end)
```

## Key Features

### 1. Norns Compatibility
- Runs directly on Norns hardware
- No external dependencies
- Uses Norns script lifecycle (`init()` function)
- Proper output capture for REPL

### 2. Simple and Reliable
- Custom test framework (no busted/luassert complexity)
- Clear error messages
- Fast execution
- No circular dependency issues

### 3. Familiar Syntax
- `describe()` and `it()` functions like popular frameworks
- Assertion API similar to luassert
- Easy to understand and maintain

### 4. Conflict Avoidance
- Uses `test_assert` instead of `assert` to avoid conflicts with Norns internals
- Doesn't interfere with Norns' global namespace
- Safe to run alongside other Norns scripts

## Troubleshooting

### Common Issues

1. **"attempt to index a nil value (field 'are')"**
   - Make sure you're using `test_assert.are.equal()` not `assert.are.equal()`

2. **Tests not loading**
   - Check that spec files are in `test/lib/spec/`
   - Verify file names match the list in `FoobarTests.lua`

3. **Module not found errors**
   - Ensure modules are in the correct paths
   - Check that `require('norns')` is at the top of test files

### Debugging

Add debug output to your tests:

```lua
describe('Debug test', function()
  it('should show debug info', function()
    print("Debug: component = " .. tostring(component))
    test_assert.is_table(component)
  end)
end)
```

## Best Practices

1. **Keep tests focused**: Each test should verify one specific behavior
2. **Use descriptive names**: Test names should clearly describe what they're testing
3. **Test error conditions**: Don't just test happy paths
4. **Mock external dependencies**: Use stubs for MIDI, grid, etc.
5. **Group related tests**: Use `describe()` blocks to organize tests logically 