# Midi Thru Machine Scaffold

This scaffold lets you lint and test Norns Lua code without hardware.

## Requirements
- macOS with [Homebrew](https://brew.sh/)
- Lua 5.3 and LuaRocks
- `rsync` and `ssh` for deployment

## Setup
```sh
make install
```

## Lint
```sh
make lint
```
Lint warnings are printed but do not fail the build.

## Test
```sh
make test
```

## End-to-End Testing
```sh
# Run comprehensive E2E tests locally
lua test_e2e.lua

# Deploy and test on Norns device
./deploy_simple.sh
```

## Continuous Integration
The included GitHub workflow runs `make lint` and `make test` on every push and pull request.

## Deploy to Norns
```sh
make deploy PI_HOST=user@ip-address
```
This syncs the repo to `~/dust/code/Foobar` on the device.

## Testing Guide
For detailed testing instructions, see [TESTING.md](TESTING.md).
