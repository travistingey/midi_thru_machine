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

## Test
```sh
make test
```

## Continuous Integration
The included GitHub workflow runs `make lint` and `make test` on every push and pull request.

## Deploy to Norns
```sh
make deploy PI_HOST=user@ip-address
```
This syncs the repo to `~/dust/code/Foobar` on the device.
