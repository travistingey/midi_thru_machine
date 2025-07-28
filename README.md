# Midi Thru Machine Scaffold

This scaffold lets you lint and test Norns Lua code without hardware, with comprehensive testing across both local and Norns environments.

## Requirements
- macOS with [Homebrew](https://brew.sh/)
- Lua 5.3+ and LuaRocks
- `rsync`, `ssh`, and `sshpass` for deployment
- Norns device accessible via SSH

## Setup
```sh
make install
```

## Testing

### Local Testing
```sh
# Run all unit tests with Busted
make test

# Run E2E tests locally
make test-local

# Run linting
make lint

# Run both linting and tests
make ci
```

### Norns Device Testing
```sh
# Deploy and test on Norns device
make deploy-and-test

# Or deploy only
make deploy

# Test on Norns only
make test-norns
```

### Manual Testing on Norns
1. **Via Maiden Web Interface**  
   – open `http://norns.local`, select the *Foobar* script, then run  
   ```lua
   dofile('test/run_norns_test.lua')
   ```

2. **Via SSH & matron (recommended for full API access)**  
   ```bash
   # from your workstation
   make test-norns-shell        # opens SSH session

   # inside the SSH session
   matron                       # starts the Lua REPL
   > dofile('~/dust/code/Foobar/test/run_norns_test.lua')
   ```

   The runner prints a plain-text summary and exits back to the REPL.

3. **Fallback – run Busted directly over SSH**  
   (requires `busted` already installed on the Norns)  
   ```bash
   ssh we@norns.local
   cd ~/dust/code/Foobar
   busted -o plain test/spec
   ```

## Configuration

Create a `.env` file (copy from `scripts/env.example`) to configure deployment:

```bash
NORNS_HOST=we@norns.local
NORNS_PASS=sleep
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
NORNS_PATH=~/dust/code/Foobar
```

## Project Structure

```
midi_thru_machine/
├── lib/                    # Main application code
├── test/                   # All test-related files
│   ├── spec/              # Busted test specifications
│   ├── .test/             # Test stubs and mocks
│   └── run_norns_test.lua # Norns test runner
├── scripts/               # Deployment and utility scripts
│   ├── deploy_simple.sh
│   ├── deploy_and_test.sh
│   ├── ssh_helpers.sh
│   └── env.example
├── docs/                  # Documentation
│   ├── TESTING.md
│   ├── components_overview.md
│   └── note_handling.md
└── Foobar.lua            # Main application entry point
```

## Deployment Scripts

- `scripts/deploy_simple.sh` - Deploy and provide testing instructions
- `scripts/deploy_and_test.sh` - Deploy and run automated tests
- `scripts/ssh_helpers.sh` - SSH helper functions for password-free deployment

## Test Structure

### Unit Tests (`test/spec/`)
- `e2e_spec.lua` - End-to-end functionality tests
- `track_components_spec.lua` - Individual track component tests
- `devicemanager_note_handling_spec.lua` - Device manager note handling
- `example_spec.lua` - Basic utility tests

### Test Support
- `test/spec/support/helpers.lua` - Common test utilities and mocks
- `test/spec/support/test_setup.lua` - Shared test environment setup
- `test/.test/norns.lua` - Norns API stubs for headless testing

### Environment Compatibility
- **Local**: Lua 5.4 with stubbed Norns APIs
- **Norns**: Lua 5.3 with real Norns APIs
- **CI**: Both Lua 5.3 and 5.4 for version compatibility testing

## Continuous Integration

The GitHub workflow runs:
- Linting with Luacheck
- Unit tests with Busted (Lua 5.3 & 5.4)
- E2E tests locally
- Automatic testing on every push and pull request

## Development Workflow

1. **Local Development**: Write and test code locally using `make test`
2. **Local Validation**: Run `make ci` to ensure code quality
3. **Deployment**: Use `make deploy-and-test` for automated deployment and testing
4. **Manual Testing**: Test on actual hardware using Maiden or SSH
5. **Iteration**: Repeat the cycle as needed

## Troubleshooting

### Connection Issues
- Ensure Norns device is accessible at configured host
- Check SSH configuration in `.env` file
- Verify `sshpass` is installed: `brew install sshpass`

### Test Failures
- Check Lua version compatibility (5.3 vs 5.4 differences)
- Verify all dependencies are installed: `make install`
- Check test output for specific error messages

### Deployment Issues
- Ensure Norns device has sufficient storage
- Check SSH permissions and password configuration
- Verify the target directory exists on Norns

## Testing Guide

For detailed testing instructions, see [docs/TESTING.md](docs/TESTING.md).
