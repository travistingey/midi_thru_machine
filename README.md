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

## Continuous Integration
The included GitHub workflow runs `make lint` and `make test` on every push and pull request.

## Deploy to Norns
```sh
make deploy PI_HOST=user@ip-address
```
This syncs the repo to `~/dust/code/Foobar` on the device.

## Documentation

Additional architecture notes and known issues live in the `docs/` folder. See
[`docs/scale_note_off_issue.md`](docs/scale_note_off_issue.md) for a discussion
of note-off handling when scales change and how mismatched note values can leave
notes stuck.
