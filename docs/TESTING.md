# Testing Guide for MIDI Thru Machine

This guide explains how to test the MIDI Thru Machine project using the comprehensive testing framework that provides **complete coverage** across all environments, including the **actual Norns runtime**.

## Overview

The testing framework provides:
- **Unified testing**: Single Busted-based test suite that runs on both local and Norns environments
- **Comprehensive coverage**: Unit tests, integration tests, and E2E tests for all components
- **Environment compatibility**: Tests run on Lua 5.3 (Norns), 5.4 (local/CI), and 5.1 (system shell)
- **Real runtime testing**: Tests execute in the actual Norns matron runtime (Lua 5.3 with full APIs)
- **Hardware integration**: Tests have access to real engine, grid, clock, params, midi, and screen APIs
- **Password-free deployment**: Automated deployment using sshpass
- **AI agent integration**: Python wrapper for automated testing and deployment

## Test Environment Strategy

The framework tests across **three distinct environments** to ensure complete coverage:

| Environment | Lua Version | APIs | Purpose | Testing Method |
|-------------|-------------|------|---------|----------------|
| **Local Development** | 5.4 | Stubbed | Development & CI | `make test` |
| **Norns System Shell** | 5.1 | System | Compatibility | `make test-norns-shell` |
| **Norns Runtime** | 5.3 | Real Norns APIs | Production | `./scripts/run-test` |

### Why Three Environments?

1. **Local (Lua 5.4 + Stubbed APIs)**: Fast development, CI/CD, no hardware required
2. **Norns System Shell (Lua 5.1)**: Compatibility testing, catches version-specific issues
3. **Norns Runtime (Lua 5.3 + Real APIs)**: Real environment testing with hardware integration

## Local Testing

### Prerequisites
- macOS with Homebrew
- Lua 5.4 and LuaRocks
- Busted (testing framework)
- Luacheck (linting)

### Setup
```bash
make install
```

### Run Tests
```bash
# Run all unit tests with Busted
make test

# Run E2E tests locally
make test-local

# Run linting
make lint

# Run both linting and tests
make ci
```

### Test Structure
- `test/spec/e2e_spec.lua` - End-to-end functionality tests
- `test/spec/track_components_spec.lua` - Individual track component tests
- `test/spec/grid_and_clock_spec.lua` - Grid events and clock automation
- `test/spec/devicemanager_note_handling_spec.lua` - Device manager note handling
- `test/spec/example_spec.lua` - Basic utility tests
- `test/spec/support/helpers.lua` - Common test utilities and mocks

## Norns Device Testing

### Prerequisites
- Norns device accessible via SSH at configured host
- SSH password authentication configured
- `.env` file with deployment configuration
- `maiden repl` available on Norns device

### Configuration
Create a `.env` file (copy from `scripts/env.example`):
```bash
NORNS_HOST=we@norns.local
NORNS_PASS=sleep
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
NORNS_PATH=~/dust/code/Foobar
```

### Setup Norns Device (One-time)
```bash
# Install required packages on Norns device
make setup-norns
```

### Automated Testing
```bash
# Deploy and test on Norns device (comprehensive)
make deploy-and-test

# Or deploy only
make deploy

# Test on Norns system shell (Lua 5.1)
make test-norns-shell

# Test on Norns runtime (Lua 5.3 + real APIs) - RECOMMENDED
make test-norns-runtime

# Test with busted in Norns runtime (if available)
make test-norns-busted

# Default Norns test (uses runtime)
make test-norns

# Test across all environments
make test-all
```

### Manual Testing on Norns

#### Option 1: Via Maiden Web Interface (Recommended)
1. Open your web browser and navigate to `http://norns.local`
2. Click on the "Foobar" script in the list
3. In the REPL (bottom panel), run:
   ```lua
   dofile('test/norns_runtime_spec.lua')
   ```

#### Option 2: Via SSH and maiden repl
1. SSH into the Norns device:
   ```bash
   ssh we@norns.local
   ```
2. Navigate to the script directory:
   ```bash
   cd ~/dust/code/Foobar
   ```
3. Run the tests using maiden repl:
   ```bash
   cat test/norns_runtime_spec.lua | maiden repl
   ```

#### Option 3: Using the run-test helper
```bash
# From your local machine
./scripts/run-test test/norns_runtime_spec.lua

# Or multiple test files
./scripts/run-test test/norns_runtime_spec.lua test/norns_busted_spec.lua
```

## AI Agent Integration

### Python Wrapper
The framework includes a Python wrapper for AI agent integration:

```bash
# Execute Lua code on Norns
python scripts/norns_agent.py eval "print('Hello from Norns!')"

# Get device state
python scripts/norns_agent.py state

# Run a test file
python scripts/norns_agent.py test test/norns_runtime_spec.lua

# Deploy and test
python scripts/norns_agent.py deploy .
```

### Agent Loop Example
```python
from scripts.norns_agent import NornsAgent

agent = NornsAgent()
agent.connect()

# Get current state
state = agent.get_state()
print(f"Current tempo: {state['clock_tempo']}")

# Execute code
result = agent.eval_lua("params:set('output_level', -20)")
print(result)

# Run tests
test_result = agent.run_test("test/norns_runtime_spec.lua")
print(f"Tests passed: {test_result['success']}")

agent.disconnect()
```

## Test Components

### 1. Device Manager Tests
- Device registration and management
- MIDI event routing
- Note interrupt handling
- Scale change management
- Clock-driven device updates

### 2. Track Component Tests
- **Input component**: Arpeggiator, random, bitwise, MIDI input
- **Auto component**: Parameter automation, preset changes, scale changes
- **Scale component**: Quantization, scale following, chord detection
- **Mute component**: Conditional gating, event filtering
- **Output component**: MIDI routing, Crow output
- **Seq component**: Recording, playback, quantization
- **Complete chain**: Input → Scale → Mute → Output processing

### 3. Grid and Clock Integration Tests
- Grid event translation (coordinates to MIDI)
- Long press handling
- Sub-grid regions
- Clock-driven automation
- Transport events (start/stop/continue)
- Tempo changes and swing timing
- Automation curves

### 4. Mode System Tests
- Mode switching (scale, note, etc.)
- Grid events in different modes
- Encoder and key event handling
- Device manager clock integration

### 5. Integration Tests
- Complete grid-to-MIDI workflow
- Clock-driven automation workflow
- Mode switching with grid events
- Track processing chain integration

### 6. Hardware Integration Tests
- **Real engine**: SuperCollider integration
- **Real grid**: Hardware grid interaction
- **Real clock**: Norns clock system
- **Real params**: Parameter system
- **Real midi**: Hardware MIDI
- **Real screen**: Display drawing

### 7. Utility Tests
- Helper function validation
- Data structure manipulation
- Function chaining and composition

## Environment Differences

| Aspect | Local Environment | Norns System Shell | Norns Runtime |
|--------|------------------|-------------------|---------------|
| Lua Version | 5.4 | 5.1 | 5.3 |
| APIs | Stubbed | System | Real Norns APIs |
| Hardware | None | None | Actual Norns hardware |
| MIDI | Simulated | None | Real MIDI devices |
| Display | None | None | Norns screen |
| Clock | Mock | System | Real clock system |
| Engine | None | None | SuperCollider integration |
| Grid | None | None | Hardware grid |
| Bitwise Operators | ✅ | ❌ | ✅ |

## Continuous Integration

The GitHub Actions workflow runs:
- **Matrix testing**: Both Lua 5.3 and 5.4
- **Linting**: Luacheck for code quality
- **Unit tests**: Busted for all test suites
- **E2E tests**: Local end-to-end testing
- **Dependencies**: Automatic installation of sshpass

## Troubleshooting

### Local Test Issues
- **Missing dependencies**: Run `make install` to install required packages
- **Lua version issues**: Ensure Lua 5.4 is installed
- **Path issues**: Check that all required modules are in the correct paths
- **Stub issues**: Verify `test/.test/norns.lua` is properly loaded

### Norns System Shell Test Issues
- **Bitwise operator errors**: Expected in Lua 5.1, these operators are only available in 5.3+
- **Syntax errors**: Expected due to version differences
- **Missing APIs**: Expected as system shell doesn't have Norns APIs

### Norns Runtime Test Issues
- **Connection issues**: Verify SSH access to configured host
- **Path issues**: Ensure the script is deployed to the correct directory
- **maiden repl issues**: Verify maiden repl is available on Norns device
- **API issues**: Check that the Norns runtime is available
- **Syntax errors**: Verify the code is compatible with Lua 5.3
- **Setup issues**: Run `make setup-norns` to install dependencies

### Common Error Messages
- `module 'Foobar/lib/...' not found`: Path mapping issue in test setup
- `attempt to index a nil value`: Missing global variable or API stub
- `unexpected symbol near '~'`: Bitwise operator compatibility issue (expected in Lua 5.1)
- `sshpass: command not found`: Install sshpass: `brew install sshpass`
- `maiden: command not found`: maiden repl not available on Norns device

## Development Workflow

1. **Local Development**: Write and test code locally using `make test`
2. **Local Validation**: Run `make ci` to ensure code quality
3. **Deployment**: Use `make deploy-and-test` for automated deployment and comprehensive testing
4. **Runtime Testing**: Test on actual hardware using maiden repl
5. **AI Integration**: Use Python wrapper for automated testing and deployment
6. **Iteration**: Repeat the cycle as needed

## Best Practices

### Writing Tests
- Use descriptive test names that explain the expected behavior
- Test both success and failure cases
- Mock external dependencies appropriately
- Keep tests focused and isolated
- Test across all three environments when possible
- Use real Norns APIs when testing in runtime

### Test Organization
- Group related tests using `describe` blocks
- Use `before_each` for common setup
- Clean up resources in `after_each` if needed
- Use helper functions for common assertions

### Environment Compatibility
- Test with both Lua 5.3 and 5.4 when possible
- Avoid version-specific language features
- Use stubbed APIs for local testing
- Verify behavior on actual Norns hardware
- Expect and document Lua 5.1 incompatibilities
- Test hardware integration in runtime environment

## Manual Testing Checklist

Before deploying to production:

- [ ] All local tests pass (`make ci`)
- [ ] E2E tests pass locally (`make test-local`)
- [ ] Code deploys successfully (`make deploy`)
- [ ] Norns runtime tests pass (`make test-norns-runtime`)
- [ ] Manual testing via Maiden interface
- [ ] Hardware integration testing
- [ ] Performance testing under load
- [ ] AI agent integration testing

## Test Coverage Summary

The framework now provides **complete coverage** across all critical components:

✅ **Track Components**: Input, Auto, Scale, Mute, Output, Seq  
✅ **Grid Integration**: Event translation, long press, sub-grids  
✅ **Clock Automation**: Transport events, tempo changes, curves  
✅ **Mode System**: Switching, grid events, encoder/key handling  
✅ **Device Management**: Registration, routing, clock integration  
✅ **Hardware Integration**: Engine, grid, clock, params, midi, screen  
✅ **Integration Scenarios**: Complete workflows, end-to-end testing  
✅ **AI Agent Integration**: Python wrapper for automated testing  

This comprehensive testing approach ensures that your code works correctly in the actual Norns environment while maintaining fast development cycles locally and providing AI agent integration capabilities. 