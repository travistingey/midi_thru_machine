# Norns Testing System

This document describes the on-device testing system for Norns scripts, which allows running unit tests directly on the Norns hardware without external dependencies.

## Overview

The testing system consists of:
- **`test/FoobarTests.lua`** - A self-contained Norns script that runs unit tests
- **Vendored dependencies** - Busted testing framework and its dependencies included in `test/vendor/`
- **Node.js bridge** - `scripts/send-to-norns.js` for communication with Norns
- **Makefile automation** - Commands for deploying and running tests

## Fresh Installation Steps

### 1. Prerequisites

Ensure you have:
- Node.js installed
- SSH access to your Norns device
- SSH key configured for passwordless access

### 2. Install Node.js Dependencies

```bash
npm install
```

This installs the `ws` (WebSocket) library required for communication with Norns.

### 3. Configure SSH Access

Ensure your SSH key is configured in the Makefile:

```makefile
SSH_KEY=~/.ssh/norns_key
PI_HOST=we@norns.local
```

### 4. Vendor Testing Dependencies

```bash
make vendor-busted
```

This clones and sets up:
- **Busted** - Lua unit testing framework
- **Penlight** - Lua utility library (required by Busted)
- **Luassert** - Lua assertion library
- **Say** - String internationalization (required by Luassert)
- **lua-term** - Terminal color utilities (optional)

### 5. Deploy Test Script

```bash
make deploy-tests
```

This copies the test script and all vendored dependencies to the Norns device.

## Running Tests

### Basic Test Execution

```bash
make test-norns
```

This command:
1. Deploys the test script (`make deploy-tests`)
2. Runs the tests on Norns (`make run-tests`)

### Individual Commands

```bash
# Deploy only
make deploy-tests

# Run tests only (assumes already deployed)
make run-tests

# Vendor dependencies only
make vendor-busted
```

## Test Script Structure

### `test/FoobarTests.lua`

The main test script follows Norns conventions:

```lua
-- Script metadata
script_name = 'FoobarTests'

-- Path resolution for dependencies
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@(.+)$')
local script_dir = script_path and script_path:gsub('[^/]+$', '') or '/home/we/dust/code/FoobarTests/'

-- Configure package.path for vendored dependencies
local paths = {
  script_dir .. 'vendor/?.lua',
  script_dir .. 'vendor/?/init.lua',
  -- ... more paths
}
package.path = table.concat(paths, ';') .. ';' .. package.path

-- Output capture hook
local function create_writer_hook()
  -- Captures io.write calls and forwards to print()
end
io.write = create_writer_hook()

-- Norns lifecycle function
function init()
  -- Test execution goes here
  print('Running tests...')
  -- ... test code ...
  print('<ok>')
end
```

### Key Features

1. **Self-contained** - No external dependencies required
2. **Norns-compatible** - Uses `init()` function for proper lifecycle
3. **Output capture** - Custom `io.write` hook ensures test output is visible
4. **Path resolution** - Dynamically determines script location
5. **Vendored dependencies** - All testing libraries included

## Writing Tests

### Basic Test Structure

Create test files in `test/spec/`:

```lua
-- test/spec/example_spec.lua
describe('Example Test Suite', function()
  it('should pass basic assertions', function()
    assert(true, 'Basic assertion')
    assert(2 + 2 == 4, 'Math works')
  end)
  
  it('should test string operations', function()
    local str = 'hello'
    assert(str == 'hello', 'String comparison')
  end)
end)
```

### Available Assertions

The vendored `luassert` library provides extended assertions:

```lua
-- Basic assertions
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)

-- Comparison assertions
assert.are.equal(expected, actual)
assert.are_not.equal(expected, actual)
assert.are.same(expected, actual)

-- Type assertions
assert.is_string(value)
assert.is_number(value)
assert.is_table(value)
assert.is_function(value)
```

## Troubleshooting

### Common Issues

1. **"module 'luassert' not found"**
   - Ensure `make vendor-busted` has been run
   - Check that `make deploy-tests` copied all vendor files

2. **No test output visible**
   - Verify the `io.write` hook is working
   - Check that tests are actually running in `init()`

3. **SSH connection issues**
   - Verify SSH key is configured correctly
   - Check Norns IP address in Makefile

4. **Tests not discovered**
   - Ensure test files are in `test/spec/`
   - Check `lfs.lua` stub returns correct file names

### Debugging

Enable verbose output by modifying `test/FoobarTests.lua`:

```lua
function init()
  print('Debug: Starting test execution...')
  -- Add debug prints throughout
  print('Debug: Tests completed')
  print('<ok>')
end
```

## Integration with Development Workflow

### Watch Mode

The `watch` command can be extended to run tests:

```makefile
watch: reload
	@echo "Running tests..."
	@make run-tests
```

### CI/CD Integration

Tests can be integrated into CI/CD pipelines:

```bash
# Run tests and fail on any errors
make test-norns || exit 1
```

## Architecture Notes

### Why On-Device Testing?

1. **Real Environment** - Tests run in actual Norns Lua environment
2. **Hardware Integration** - Tests can access real MIDI, grid, encoders
3. **No External Dependencies** - Self-contained testing environment
4. **Immediate Feedback** - Tests run directly on target hardware

### Communication Flow

```
Node.js Script → WebSocket → Norns REPL → Test Script → Output Capture → Node.js
```

1. `send-to-norns.js` sends Lua commands via WebSocket
2. Norns REPL executes commands and returns output
3. Test script runs with vendored dependencies
4. Custom `io.write` hook captures all output
5. Output is streamed back through WebSocket to Node.js

### Dependency Management

All testing dependencies are vendored to avoid:
- External package managers (luarocks)
- Network dependencies during test execution
- Version conflicts between environments

## Future Enhancements

1. **Test Coverage** - Integrate coverage reporting
2. **Parallel Testing** - Run multiple test suites simultaneously
3. **Test Categories** - Unit, integration, and hardware tests
4. **Continuous Testing** - Auto-run tests on file changes
5. **Test Reporting** - Generate HTML/JSON test reports 