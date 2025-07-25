# Testing Guide for MIDI Thru Machine

This guide explains how to test the MIDI Thru Machine project both locally and on the Norns device.

## Local Testing

### Prerequisites
- macOS with Homebrew
- Lua 5.3+ and LuaRocks
- Busted (testing framework)
- Luacheck (linting)

### Setup
```bash
make install
```

### Run Tests
```bash
# Run all tests
make test

# Run linting
make lint

# Run both linting and tests
make ci
```

### End-to-End Testing
```bash
# Run comprehensive E2E tests locally
lua test_e2e.lua
```

## Norns Device Testing

### Prerequisites
- Norns device accessible via SSH at `we@norns.local`
- SSH key or password authentication configured

### Deployment
```bash
# Deploy and get testing instructions
./deploy_simple.sh
```

### Testing on Norns

#### Option 1: Via Maiden Web Interface (Recommended)
1. Open your web browser and navigate to `http://norns.local`
2. Click on the "Foobar" script in the list
3. In the REPL (bottom panel), run:
   ```lua
   dofile('run_norns_test.lua')
   ```

#### Option 2: Via SSH and Direct File Execution
1. SSH into the Norns device:
   ```bash
   ssh we@norns.local
   ```
2. Navigate to the script directory:
   ```bash
   cd ~/dust/code/Foobar
   ```
3. Run the test directly:
   ```bash
   lua run_norns_test.lua
   ```

#### Option 3: Via Norns REPL
1. SSH into the Norns device
2. Start the Norns REPL (if available)
3. Load and run the test:
   ```lua
   dofile('run_norns_test.lua')
   ```

## Test Structure

### Local Tests (`test_e2e.lua`)
- Uses stubbed Norns APIs for headless testing
- Tests core functionality without hardware dependencies
- Runs in Lua 5.4 environment

### Norns Tests (`test_norns.lua`)
- Designed to run within the Norns matron environment (Lua 5.3)
- Uses actual Norns APIs and hardware
- Tests real device interactions

### Test Components
1. **Device Manager Basic** - Tests device registration and management
2. **Scale Quantization** - Tests musical scale processing
3. **Track Component Chain** - Tests track processing pipeline
4. **MIDI Event Routing** - Tests MIDI message handling
5. **Note Interrupt Handling** - Tests note interruption logic
6. **Utilities Functions** - Tests helper functions

## Troubleshooting

### Local Test Issues
- **Missing dependencies**: Run `make install` to install required packages
- **Lua version issues**: Ensure Lua 5.3+ is installed
- **Path issues**: Check that all required modules are in the correct paths

### Norns Test Issues
- **Connection issues**: Verify SSH access to `we@norns.local`
- **Path issues**: Ensure the script is deployed to `~/dust/code/Foobar`
- **API issues**: Check that the Norns runtime is available
- **Syntax errors**: Verify the code is compatible with Lua 5.3

### Common Error Messages
- `module 'Foobar/lib/...' not found`: Path mapping issue in test setup
- `attempt to index a nil value`: Missing global variable or API stub
- `unexpected symbol near '~'`: Bitwise operator compatibility issue (should not occur in Norns environment)

## Development Workflow

1. **Local Development**: Write and test code locally using `test_e2e.lua`
2. **Local Validation**: Run `make ci` to ensure code quality
3. **Deployment**: Use `./deploy_simple.sh` to deploy to Norns
4. **Norns Testing**: Test on actual hardware using Maiden or SSH
5. **Iteration**: Repeat the cycle as needed

## Environment Differences

| Aspect | Local Environment | Norns Environment |
|--------|------------------|-------------------|
| Lua Version | 5.4 | 5.3 |
| APIs | Stubbed | Real Norns APIs |
| Hardware | None | Actual Norns hardware |
| MIDI | Simulated | Real MIDI devices |
| Display | None | Norns screen |

## Continuous Integration

The project includes GitHub Actions that run:
- Linting with Luacheck
- Unit tests with Busted
- Local E2E tests

These run automatically on every push and pull request.

## Manual Testing Checklist

Before deploying to production:

- [ ] All local tests pass (`make ci`)
- [ ] E2E tests pass locally (`lua test_e2e.lua`)
- [ ] Code deploys successfully (`./deploy_simple.sh`)
- [ ] Tests pass on Norns device (via Maiden)
- [ ] Basic functionality works on hardware
- [ ] MIDI routing functions correctly
- [ ] UI responds as expected 