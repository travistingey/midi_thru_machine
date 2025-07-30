# Lib Component Test Specifications

This document summarizes the automated specs added for the modules in
`src/lib` and its subdirectories.  Each spec is executed with the on-device
busted test runner and uses the stubbed `norns` environment found in
`test/stubs`.

## Specs Overview

| Spec File | Covered Module | Purpose |
|-----------|----------------|---------|
| `app_spec.lua` | `lib/app.lua` | Verifies the event subscription system. |
| `auto_spec.lua` | `lib/components/track/auto.lua` | Tests storing and toggling automation actions. |
| `bitwise_spec.lua` | `lib/bitwise.lua` | Checks initialization, mutation and cycling of bitwise sequences. |
| `device_manager_spec.lua` | `lib/components/app/devicemanager.lua` | Ensures virtual and MIDI devices are registered. |
| `grid_spec.lua` | `lib/grid.lua` | Exercises LED setting and refresh behaviour. |
| `input_spec.lua` | `lib/components/track/input.lua` | Sends MIDI trigger events through the input component. |
| `launchcontrol_spec.lua` | `lib/launchcontrol.lua` | Confirms note and CC mappings. |
| `mode_spec.lua` | `lib/components/app/mode.lua` | Enables and disables mode with a dummy component. |
| `mute_spec.lua` | `lib/components/track/mute.lua` | Verifies note filtering based on mute state. |
| `musicutil_extended_spec.lua` | `lib/musicutil-extended.lua` | Tests scale bit conversions and shifting. |
| `output_spec.lua` | `lib/components/track/output.lua` | Forwards MIDI events to the assigned device. |
| `seq_spec.lua` | `lib/components/track/seq.lua` | Records events and loads clips. |
| `trackcomponent_spec.lua` | `lib/components/track/trackcomponent.lua` | Confirms generic event emitter functionality. |

These specs are intended to serve as a starting point for more detailed test
coverage. They focus on the most important public APIs of each component and
exercise basic behaviour to ensure modules load and function without errors.
