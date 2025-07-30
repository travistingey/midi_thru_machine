# AGENTS.md - Development Patterns and Requirements

This document captures important patterns, requirements, and architectural decisions for the MIDI Thru Machine project. It serves as a reference for future development and AI assistance.

## Core Architecture Patterns

### 1. Norns Script Structure

**Pattern**: All Norns scripts must follow the standard lifecycle functions:
```lua
-- Required lifecycle functions
function init()
  -- Called when script loads
end

function cleanup()
  -- Called when script unloads
end

function redraw()
  -- Called for screen updates
end

function enc(e, d)
  -- Called for encoder events
end

function key(k, z)
  -- Called for key events
end
```

**Requirement**: Scripts must be self-contained and not rely on external package managers.

### 2. Global State Management

**Pattern**: Use singleton App instance for global state:
```lua
-- Global values like PPQN should be stored in the App singleton instance
-- rather than being defined per component
App = {
  ppqn = 24,
  -- other global state
}
```

**Requirement**: Avoid global variables outside of the App singleton.

### 3. Component Architecture

**Pattern**: Organize code into reusable components:
```
lib/components/
├── app/          # App-level components
├── mode/         # Mode-specific components  
└── track/        # Track-specific components
```

**Requirement**: Each component should be self-contained with clear interfaces.

## Testing Patterns

### 1. On-Device Testing

**Pattern**: Tests must run directly on Norns hardware:
- Use custom test framework (no external dependencies)
- Self-contained test scripts
- Custom output capture for REPL compatibility
- Avoid conflicts with Norns internals (use `test_assert` instead of `assert`)

**Requirement**: All tests must be executable on real hardware, not just in simulation.

### 2. Test Script Structure

**Pattern**: Test scripts follow Norns conventions:
```lua
script_name = 'ScriptNameTests'

-- Path resolution
local info = debug.getinfo(1, 'S')
local script_path = info.source:match('^@(.+)$')
local script_dir = script_path and script_path:gsub('[^/]+$', '') or '/home/we/dust/code/ScriptNameTests/'

-- Package path configuration
package.path = table.concat(paths, ';') .. ';' .. package.path

-- Output capture
io.write = create_writer_hook()

function init()
  -- Test execution
  print('<ok>')
end
```

**Requirement**: Test scripts must use `init()` function and proper output capture.

### 3. Custom Test Framework

**Pattern**: Use custom test framework built for Norns:
```
test/
├── FoobarTests.lua    # Main test script
├── lib/
│   ├── spec/          # Test specifications
│   └── stubs/         # Norns environment stubs
└── scripts/           # Test utilities
```

**Requirement**: No external package managers or network dependencies during test execution.

## Communication Patterns

### 1. Node.js to Norns Bridge

**Pattern**: Use WebSocket for reliable communication:
```javascript
// scripts/send-to-norns.js
const WebSocket = require('ws');
const ws = new WebSocket('ws://norns.local:5555');

ws.on('message', (data) => {
  const text = data.toString();
  if (text.includes('<ok>')) {
    ws.close();
  }
});
```

**Requirement**: Always wait for `<ok>` signal before closing connection.

### 2. Output Capture

**Pattern**: Custom `io.write` hook for test output:
```lua
local function create_writer_hook()
  local buffer = ''
  return function(...)
    -- Capture and forward to print()
  end
end
io.write = create_writer_hook()
```

**Requirement**: All test output must be captured and forwarded to Norns REPL.

## Development Workflow Patterns

### 1. Makefile Automation

**Pattern**: Use Makefile for all development tasks:
```makefile
# Script management
SCRIPT_NAME=Foobar
SCRIPT_PATH=/home/we/dust/code/$(SCRIPT_NAME)/$(SCRIPT_NAME).lua

# Test management  
TEST_SCRIPT_NAME=$(SCRIPT_NAME)Tests
TEST_PATH=/home/we/dust/code/$(TEST_SCRIPT_NAME)/$(TEST_SCRIPT_NAME).lua

# Commands
deploy: rsync
reload: send-to-norns
test-norns: deploy-tests run-tests
```

**Requirement**: All common tasks should be automated via Makefile targets.

### 2. File Organization

**Pattern**: Consistent file structure:
```
project/
├── src/              # Main Norns scripts
├── test/             # Test scripts and specs
├── scripts/          # Development tools
├── docs/             # Documentation
└── Makefile          # Automation
```

**Requirement**: Maintain clear separation between source, tests, and tools.

## Error Handling Patterns

### 1. Lua Error Handling

**Pattern**: Use `pcall` for safe module loading:
```lua
local ok, result = pcall(require, 'module.name')
if not ok then
  print('Failed to load module:', result)
  return
end
```

**Requirement**: Always handle module loading errors gracefully.

### 2. WebSocket Error Handling

**Pattern**: Comprehensive error handling in Node.js bridge:
```javascript
ws.on('error', (error) => {
  console.error('WebSocket error:', error.message);
  process.exit(1);
});

ws.on('close', () => {
  if (!responseReceived) {
    console.log('Connection closed without receiving response');
  }
});
```

**Requirement**: Handle connection failures and timeouts appropriately.

## Performance Patterns

### 1. Memory Management

**Pattern**: Clear module cache when reloading:
```lua
for script,value in pairs(package.loaded) do
  if string.match(script, 'ScriptName') then
    package.loaded[script] = nil
  end
end
```

**Requirement**: Always clear cache when reloading scripts to avoid stale state.

### 2. Efficient Testing

**Pattern**: Use targeted test execution:
```lua
-- Run specific test suites
describe('Component Tests', function()
  it('should handle specific case', function()
    -- focused test
  end)
end)
```

**Requirement**: Tests should be fast and focused on specific functionality.

## Security Patterns

### 1. SSH Key Management

**Pattern**: Use SSH keys for passwordless access:
```makefile
SSH_KEY=~/.ssh/norns_key
PI_HOST=we@norns.local
```

**Requirement**: Never store passwords in code or configuration files.

### 2. Input Validation

**Pattern**: Validate all external inputs:
```lua
function validate_midi_message(msg)
  assert(type(msg) == 'table', 'MIDI message must be table')
  assert(msg.type, 'MIDI message must have type')
  -- additional validation
end
```

**Requirement**: Always validate inputs from external sources (MIDI, encoders, etc.).

## Documentation Patterns

### 1. Code Documentation

**Pattern**: Use consistent comment style:
```lua
-- Function: handle_midi_message
-- Purpose: Process incoming MIDI messages
-- Parameters:
--   msg (table): MIDI message table
-- Returns: (boolean) success status
function handle_midi_message(msg)
  -- implementation
end
```

**Requirement**: Document all public functions and complex logic.

### 2. Architecture Documentation

**Pattern**: Document system architecture in `docs/`:
```
docs/
├── components_overview.md
├── testing.md
├── note_handling.md
└── scale_note_off_issue.md
```

**Requirement**: Keep documentation up-to-date with code changes.

## Future Considerations

### 1. Scalability

- Consider modular component loading
- Plan for larger test suites
- Design for multiple script management

### 2. Maintainability

- Establish coding standards
- Implement automated linting
- Create component templates

### 3. Extensibility

- Design for plugin architecture
- Plan for custom modes

## Anti-Patterns to Avoid

1. **Global Variables**: Don't use globals outside App singleton
2. **Hard-coded Paths**: Always use dynamic path resolution
3. **External Dependencies**: Don't rely on luarocks or network during execution
4. **Blocking Operations**: Avoid blocking calls in event handlers
5. **Memory Leaks**: Always clean up resources in cleanup functions
6. **Silent Failures**: Always log or handle errors appropriately
7. **Tight Coupling**: Keep components loosely coupled with clear interfaces
8. **Magic Numbers**: Use named constants instead of magic numbers
9. **Long Functions**: Break complex functions into smaller, focused functions
10. **Inconsistent Naming**: Follow established naming conventions 