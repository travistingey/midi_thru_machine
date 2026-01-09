# MIDI Thru Machine - MIDI Processing & Sequencing System

A sophisticated MIDI processing and live looping workstation for the [Monome Norns](https://monome.org/docs/norns/) platform. MIDI Thru Machine provides an 8-track MIDI processing system with real-time manipulation, sequencing, automation, and hardware controller integration.

## Overview

MIDI Thru Machine transforms your Norns into a powerful MIDI hub that can:
- Route and process MIDI between multiple devices
- Generate notes via arpeggiators, randomization, and algorithmic sequencers
- Apply scale quantization with sophisticated follow modes
- Record and loop MIDI performances with overdub/overwrite
- Automate parameters, CC curves, and preset changes
- Control everything via Novation Launchpad or similar grid controllers

## Features

### Core Architecture
- **8 Independent Tracks**: Each track has a complete processing chain
- **Multi-Device Routing**: Connect and route between multiple MIDI devices
- **Event-Driven Design**: Loosely coupled components communicate via publish/subscribe
- **Hardware Integration**: Native support for grid controllers, LaunchControl, and Crow CV/gate

### Input Generation

Each track can generate or transform MIDI input in multiple modes:

- **MIDI**: Direct passthrough of incoming MIDI
- **Arpeggiator**: 6 patterns (up, down, up/down, converge, diverge, random)
- **Random**: Random note generation within configurable ranges
- **Bitwise Sequencer**: Algorithmic pattern generation using bitwise operations
- **Chord**: Chord generation based on current scale
- **Crow CV**: Convert CV/gate input from Monome Crow to MIDI

### Scale & Harmony System

Powerful scale quantization and harmonic processing:

- **4095 Possible Scales**: Defined via 12-bit bitmasks for maximum flexibility
- **7 Follow Modes**: Tracks can follow other scales with different transformation methods:
  - Transpose
  - Scale degree mapping
  - Pentatonic conversion
  - Chord-based transformation
  - MIDI-triggered modes (on/latch/lock)
- **Chord Detection**: Recognizes and generates chords within scales
- **Chord Sets**: All chords, Plaits-inspired set (11 chords), or custom presets

### Buffer Recording & Looping

Live MIDI capture and manipulation (recent addition):

- **Live Recording**: Capture MIDI input into loop buffers
- **Overdub Mode**: Layer additional notes onto existing loops
- **Overwrite Mode**: Replace existing notes step-by-step
- **Scrub Playback**: Visual grid interface for scrubbing through recorded buffers
- **Loop Points**: Define custom loop regions within buffers
- **Grid Visualization**: See your recorded MIDI on the grid controller

### Automation Engine

Record and playback parameter changes over time:

- **Parameter Recording**: Capture any parameter changes during playback
- **CC Curves**: Record and playback continuous controller curves
- **Preset Sequencing**: Automate preset changes at specific steps
- **Scale Changes**: Schedule scale/root changes in automation timeline
- **Loop/Scrub Modes**: Different playback behaviors for automation

### UI Modes

Multiple operational modes optimized for different workflows:

1. **Session Preset Mode**: Preset and automation sequencing
2. **Session Note Mode**: Note-based session view
3. **Drums Mode**: Drum-focused interface
4. **Keys Mode**: Keyboard/melodic interface
5. **User Mode**: Customizable mode

Each mode provides specialized grid layouts and interaction patterns.

## Architecture

### Component Structure

```
Foobar.lua (Entry Point)
└── App (Main Controller)
    ├── DeviceManager
    │   ├── MIDIDevice (MIDI hardware)
    │   ├── CrowDevice (CV/Gate)
    │   ├── MixerDevice (LaunchControl)
    │   └── VirtualDevice (Internal routing)
    ├── Tracks (8 instances)
    │   └── Processing Chain:
    │       ├── Auto (Automation & Buffer Recording)
    │       ├── Input (Note Generation)
    │       ├── Seq (Sequencer - WIP)
    │       ├── Scale (Quantization & Harmony)
    │       ├── Mute (Event Gating)
    │       └── Output (Device Routing)
    ├── Scales (4 shared scales)
    ├── Modes (Session, Drums, Keys, User)
    └── UI (Screen & Grid rendering)
```

### Processing Flow

1. **Input**: MIDI/CV arrives at a device
2. **Device Manager**: Routes to appropriate track(s)
3. **Track Chain**: Event flows through components:
   - Auto checks for buffer playback or passes through
   - Input generates or modifies notes
   - Seq processes sequences (future)
   - Scale quantizes to harmonic content
   - Mute conditionally gates events
   - Output sends to destination device(s)
4. **Output**: Processed MIDI/CV leaves via device

### Event System

All components use a publish/subscribe event system:

```lua
-- Subscribe to events
component:on('event_name', function(data) ... end)

-- Emit events
component:emit('event_name', data)

-- Unsubscribe
component:off('event_name', handler)
```

Key events:
- `transport` - Start/stop/tick events from clock
- `midi_event` - MIDI note/CC data
- `scale_change` - Scale/root modifications
- `interrupt_scale` - Mid-note scale changes (triggers note-off handling)

## Getting Started

### Requirements

- **Hardware**: Monome Norns (or Norns Shield)
- **Optional**:
  - Novation Launchpad or compatible grid controller
  - Novation LaunchControl XL
  - Monome Crow (for CV/gate)
- **Development** (for making changes):
  - macOS with [Homebrew](https://brew.sh/)
  - Lua 5.3
  - Node.js (for deployment tools)

### Installation

1. **Direct Installation** (to Norns):
   ```sh
   ssh we@norns.local
   cd ~/dust/code
   git clone [repository-url] MIDI Thru Machine
   ```

2. **Development Setup** (on your computer):
   ```sh
   git clone [repository-url] midi_thru_machine
   cd midi_thru_machine
   make install  # Install Lua, LuaRocks, dev tools
   ```

### Usage

1. **On Norns**: Navigate to `SELECT > FOOBAR` and press K3 to launch
2. **Connect MIDI Devices**: Use `SYSTEM > DEVICES > MIDI` to configure
3. **Configure Tracks**: Use encoders to navigate and K2/K3 to select
4. **Connect Grid** (optional): Grid will be auto-detected when connected

### Development Workflow

```sh
# Lint code
make lint

# Deploy to Norns
make deploy

# Deploy and reload script
make push

# Watch for changes and auto-deploy
make watch

# SSH into Norns
make norns
```

The Makefile expects your Norns to be accessible at `we@norns.local` with SSH key at `~/.ssh/norns_key`. Adjust these in the Makefile if needed.

## Configuration

### Parameters

Each track has 27+ parameters:
- MIDI input/output device and channel
- Input type (MIDI, Arp, Random, etc.)
- Arpeggiator settings (rate, pattern, octaves)
- Scale assignment and follow mode
- Automation and buffer settings
- Mute state

Parameters are accessible via Norns parameter menu (K1) and can be automated.

### Presets

- Save/load presets via Norns PSET system
- Includes all track parameters and buffer contents
- Automation can sequence preset changes

### Device Management

Devices are auto-detected and assigned IDs:
- MIDI devices: Detected via Norns MIDI system
- Grid: Auto-detected Launchpad or compatible controller
- Crow: Auto-detected when connected
- Virtual devices: For internal routing

## Key Concepts

### Smart Note-Off Handling

When scales change mid-note, MIDI Thru Machine intelligently handles note-offs to prevent stuck notes:

1. Tracks all active note-on events
2. When scale changes, re-quantizes active notes
3. If pitch class changes, sends early note-off for old pitch
4. Continues with new pitch for remaining note duration

See `docs/note_handling.md` for detailed flow.

### Scale Bitmasks

Scales are represented as 12-bit numbers where each bit represents a note in the chromatic scale:

```
C  C# D  D# E  F  F# G  G# A  A# B
b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11
```

Example: Major scale = `0b101010110101` = 2741

This allows for 4095 possible scale combinations (2^12 - 1).

### Track Components

Components in a track chain implement:
- `transport_event(data)` - Handle clock events (start/stop/tick)
- `midi_event(data)` - Handle MIDI events (note/CC)
- `enable()` / `disable()` - Lifecycle management

Components can:
- Transform events and pass them on
- Generate new events
- Terminate the chain (by not calling next component)

## Project Structure

```
midi_thru_machine/
├── src/
│   ├── Foobar.lua                    # Norns entry point
│   └── lib/
│       ├── app.lua                   # Main application controller
│       ├── ui.lua                    # Screen rendering
│       ├── grid.lua                  # Grid controller interface
│       ├── launchcontrol.lua         # LaunchControl integration
│       ├── components/
│       │   ├── app/                  # Core components
│       │   │   ├── devicemanager.lua # Device abstraction
│       │   │   ├── track.lua         # Track container
│       │   │   ├── mode.lua          # Mode system
│       │   │   └── scale.lua         # Global scale objects
│       │   ├── mode/                 # UI mode components
│       │   │   ├── bufferseq.lua     # Buffer sequencer UI
│       │   │   ├── presetseq.lua     # Preset sequencer UI
│       │   │   ├── scalegrid.lua     # Scale editor
│       │   │   ├── mutegrid.lua      # Mute interface
│       │   │   └── notegrid.lua      # Note interface
│       │   └── track/                # Track processing components
│       │       ├── auto.lua          # Automation & buffers
│       │       ├── input.lua         # Input generation
│       │       ├── seq.lua           # Sequencer (WIP)
│       │       ├── scale.lua         # Quantization
│       │       ├── mute.lua          # Event gating
│       │       └── output.lua        # Output routing
│       ├── modes/                    # Mode definitions
│       └── utilities/                # Helper modules
│           ├── registry.lua          # Parameter management
│           ├── persistence.lua       # Data persistence
│           ├── tracer.lua            # Diagnostic tracing
│           └── flags.lua             # Feature flags
├── docs/                             # Architecture documentation
├── scripts/                          # Deployment tools
├── Makefile                          # Build automation
└── package.json                      # Node.js dependencies
```

## Documentation

Additional documentation in `docs/`:

- `components_overview.md` - Detailed component architecture
- `note_handling.md` - Note-off handling flow
- `scale_note_off_issue.md` - Discussion of scale change challenges

## Current Development

Recent work (as of `ai` branch) focuses on:

1. **Buffer Recording System**: Live MIDI loop recording with overdub/overwrite modes
2. **Buffer Sequencer UI**: Grid-based interface for buffer manipulation
3. **Device Management**: Enhanced device handling and triggering
4. **Track Processing**: Refinements to track component chains
5. **Automation**: Integration of buffer playback with automation timeline

## Known Limitations

### Platform Dependencies

The codebase is currently tightly coupled to Norns runtime:
- Direct use of `params`, `clock`, `screen`, `midi`, `crow` from Norns
- Limits testability and cross-platform compatibility
- See `docs/components_overview.md` for refactoring strategy

### Testing

- Limited test coverage (currently only utilities)
- Tests require Norns hardware or elaborate mocking
- Plan to abstract platform dependencies for headless testing

## Contributing

When contributing:

1. Run `make lint` before committing
2. Follow existing code patterns and event-driven architecture
3. Update documentation for significant changes
4. Test on actual Norns hardware when possible
5. Consider platform abstraction for new features

## Roadmap

Future development areas:

1. **Sequencer Component**: Complete `seq.lua` implementation
2. **Platform Abstraction**: Decouple from Norns runtime for testing
3. **Test Coverage**: Expand unit tests for all components
4. **Performance**: Optimize processing chain for lower latency
5. **Documentation**: API docs for all components
6. **Additional Modes**: More specialized UI modes
7. **Pattern Management**: Save/load patterns and buffers
8. **MIDI Learn**: Dynamic CC mapping

## Troubleshooting

### Script won't start
- Check Norns system log: `SYSTEM > LOG`
- Verify MIDI devices are properly connected
- Try manually reloading: `norns.script.load("/home/we/dust/code/Foobar/Foobar.lua")`

### Stuck notes
- MIDI Thru Machine includes smart note-off handling, but if notes stick:
  - Press K1 to open menu, then K3 to close (triggers cleanup)
  - Restart the script
  - Check scale change interrupts are working

### Grid not responding
- Verify grid is detected: Check `SYSTEM > DEVICES > GRID`
- Ensure grid is in correct mode (some Launchpads need mode selection)
- Try disconnecting and reconnecting

### UI frozen
- Watchdog system should auto-recover after 2.5 seconds
- If not, SSH in and restart script
- Check for errors in system log

## License

[License information to be added]

## Credits

Built with love for the Norns community.

"Just remember you're doing as good as you can today. There are no stakes and it's just for fun. ^_^"
