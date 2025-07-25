# Component Overview

This document summarizes the major modules in the project and how they collaborate. It also highlights remaining dependencies on the Norns runtime and suggests areas for further development and testing.

## 1. Application entry
- **Foobar.lua** – Norns entry point. Initializes the global `App` singleton and forwards encoder/key input to it. Runs a redraw clock for UI updates.
- **lib/app.lua** – Main controller that instantiates devices, tracks, scales and modes. Maintains global state for the running script, handles event subscription and dispatch, manages playback clock and drawing.

## 2. Device management
- **lib/components/app/devicemanager.lua** – Abstraction layer around MIDI, grid, LaunchControl and Crow devices. Provides a `Device` base class and subclasses for MIDI/Crow/Mixer/Virtual devices. Supports event routing and dynamic device registration.

## 3. Track architecture
- **lib/components/app/track.lua** – Represents a single processing chain. Loads component modules (`auto`, `input`, `seq`, `mute`, `output`) and builds callable chains for handling transport and MIDI events. Keeps per‑track parameters such as MIDI channels and device IDs. The `handle_note` function is currently empty and needs implementation.
- **lib/components/track/** – Track components. Each implements `transport_event` and/or `midi_event` used by the chain.
  - **auto.lua** – Parameter automation engine. Stores actions per step, drives CC curves and preset/scale changes.
  - **input.lua** – Generates or manipulates incoming MIDI (arpeggiators, random notes, bitwise sequencer, crow CV in, etc.).
  - **seq.lua** – Sequencer that continuously records history, quantizes segments and plays back clips.
  - **scale.lua** – Harmony and quantization logic. Supports scale following modes, chord detection and note locking.
  - **mute.lua** – Conditional gating of events (not currently listed in track builder but exists in repo).
  - **output.lua** – Sends processed events to MIDI or Crow.
  - **trackcomponent.lua** – Base class providing event subscription helpers used by all components.

## 4. UI modes
- **lib/components/app/mode.lua** and **lib/components/mode/** – Mode system for grid/Launchpad UI. Modes are stateless and reflect current track state. Components such as `scalegrid`, `mutegrid`, `notegrid`, etc. define grid regions and behavior.
- **lib/grid.lua** – Helper for Launchpad style grids. Handles drawing, sub‑grids and long‑press events.

## 5. Utilities
- **lib/utilities.lua** – Small helper functions (table concat, module unloading, etc.).
- **lib/musicutil-extended.lua** – Extensions to Norns `musicutil` for interval/bitmask conversions and chord tables.
- **lib/bitwise.lua** – Bitwise mutation helper used by the `bitwise` input type.

## Norns‑specific dependencies
Current code relies on Norns libraries for:
- `params` – parameter storage/UI (used heavily across tracks and scales)
- `clock`, `screen`, `midi`, `crow`, `util` – runtime hardware bindings
- Use of `midi.connect`, `clock.run`, `screen.*` calls in app, grid and output components

To make the core logic platform‑agnostic, those calls should be abstracted behind interfaces. For example:
- Replace direct `params` access with a configuration layer that can read/write from a table and emit change events.
- Abstract `clock` ticks and device I/O via injectable modules, so that sequencing and automation can run in a headless Lua environment.
- Move `screen` drawing code out of business logic (e.g. `app.lua` uses screen drawing directly). UI should be a thin layer.

## Components needing refactor for agnosticism
- **app.lua** – heavy usage of `params`, `clock`, `screen` and direct device methods. Would benefit from splitting core state/logic from Norns UI wrappers.
- **devicemanager.lua** – uses `midi.connect`, `crow` and Launchpad/LaunchControl specifics; refactor into a pluggable backend that can register devices in other environments.
- **track.lua** and component modules – rely on `params` for initialization. Parameter handling should be decoupled from Norns' global `params` table.
- **grid.lua** – manipulates Launchpad MIDI messages and uses `util` for time; could be abstracted to support other pad controllers.

## Testing strategy
The only existing tests cover `utilities`. The sequencing and scale logic lack coverage. Suggested test areas per component:

### lib/app.lua
- Event dispatching (`on`, `off`, `emit`)
- Mode switching and device registration
- Transport start/stop behavior with mock clock events

### devicemanager.lua
- Adding/removing devices and routing events between them
- Note interrupt handling when scales change
- Virtual and mixer device behavior

### track.lua and track components
- Building the processing chain and verifying that events pass through components in order
- Automation playback triggering preset/scale changes
- Input module modes (arpeggio, random, bitwise) producing expected note sequences
- Sequencer quantization and clip loading/saving
- Scale quantization and follow modes adjusting notes correctly
- Output sending to MIDI/Crow with correct channel/voltage mapping

### grid.lua and mode components
- Grid event translation from MIDI notes/CC to x,y coordinates
- Toggled state and long‑press detection
- ModeComponent enable/disable lifecycle registering and removing listeners

Mock implementations of `clock`, `midi`, `screen` and `params` should be used to run these tests outside of Norns hardware. The existing `spec` folder can be expanded with Busted specs covering each module.

## Migration plan
1. **Introduce abstraction layers** – create adapter modules for `clock`, `params`, and device I/O. Start replacing direct calls with calls through these adapters.
2. **Write unit tests using adapters** – implement mocks for the adapters so tests can run in any Lua environment (CI or host machine).
3. **Gradually refactor modules** – move UI drawing (`screen`) and Norns specifics out of core logic. Keep the existing Norns entry point as thin as possible.
4. **Implement missing functionality** – notably `Track:handle_note` and more complex note-off handling across scale changes.
5. **Expand documentation** – document each component's API and responsibilities to facilitate cross‑platform development.

