# Foobar - Multi-Track Music Sequencer

## Overview
**Foobar** is a sophisticated multi-track music sequencer and DAW-like application built for the **Norns** platform (a sound computing platform). It provides comprehensive music production capabilities with advanced sequencing, MIDI control, and modular architecture.

## Core Features

### 🎵 **Multi-Track Sequencing**
- **16 individual tracks** with independent configuration
- **Step sequencing** with configurable step lengths (1/48 to 16 bars)
- **Arpeggiator** with multiple patterns (up, down, up-down, converge, diverge)
- **Transport controls** (play, stop, record, continue)
- **PPQN-based timing** (24 pulses per quarter note)

### 🎹 **Input/Output Systems**
- **MIDI I/O** with channel-specific routing (1-16 channels)
- **Crow CV/Gate** support for modular synthesis
- **MIDI Thru** functionality
- **Program Change** events
- **Polyphonic and monophonic** voice modes

### 🎛️ **Device Management**
- **Device Manager** for handling multiple MIDI devices
- **Monome Grid** support (Launchpad compatible)
- **LaunchControl** MIDI controller integration
- **Mixer** functionality with CC automation
- **Panic function** for emergency note-off

### 🎼 **Musical Intelligence**
- **Scale system** with 4 configurable scales (0-3)
- **Chord detection and display** with root/bass notation
- **Interval visualization** (R, b2, 2, b3, 3, 4, b5, 5, b6, 6, b7, 7)
- **Note range constraints** with octave-based configuration
- **Chance-based triggering** for generative elements

### 🎚️ **Advanced Controls**
- **Slew limiting** for smooth parameter changes
- **Swing timing** with configurable swing amount
- **Step reset** functionality for polyrhythmic patterns
- **Preset management** with 16 preset slots
- **Real-time parameter modulation**

## Operational Modes

The application features **5 distinct operational modes**:

1. **Session Mode (Preset)** - Main sequencing and preset management
2. **Drums Mode** - Specialized for drum programming
3. **Keys Mode** - Keyboard-focused interface
4. **User Mode** - Customizable user interface
5. **Session Mode (Note)** - Note-based session management

## Technical Architecture

### 🏗️ **Modular Design**
- **Component-based architecture** with clear separation of concerns
- **Event-driven system** with listener/emitter pattern
- **Device abstraction layer** for hardware independence
- **Parameter management** with automatic UI generation

### 📁 **Key Components**
- **App** (`app.lua`) - Main application controller (897 lines)
- **Track** (`track.lua`) - Individual track management (603 lines)
- **Grid** (`grid.lua`) - Grid interface handling (499 lines)
- **LaunchControl** (`launchcontrol.lua`) - MIDI controller support (330 lines)
- **Device Manager** (`devicemanager.lua`) - Hardware device management (583 lines)
- **Music Utilities** (`musicutil-extended.lua`) - Extended music theory functions (268 lines)

### 🎛️ **User Interface**
- **Screen-based interface** with tempo display, chord visualization, and status indicators
- **Encoder/Key handling** with ALT key combinations
- **Real-time visual feedback** with 24fps refresh rate
- **Font system** with multiple typefaces and sizes

## Development Features

### 🔧 **Development Tools**
- **Hot-reloading** system with `r()` function
- **Cleanup functions** for proper resource management
- **Debug modes** with MIDI data visualization
- **Bitwise operations** for efficient flag management

### 🧪 **Testing & Debugging**
- **Test functions** for flag combination validation
- **Binary representation** utilities
- **Error handling** with graceful degradation
- **Logging system** for troubleshooting

## Configuration & Customization

### ⚙️ **Parameters**
- **Per-track settings**: Name, device routing, MIDI channels, arpeggio patterns, step timing
- **Global settings**: Swing, tempo, transport controls, device assignments
- **Scale settings**: Root notes, intervals, chord progressions, follow methods
- **Preset system**: 16 slots with track and scale parameter storage

### 🎨 **UI Customization**
- **Multiple font options** with size variants
- **Color coding** for different UI states
- **Customizable grid layouts** and button mappings
- **Mode-specific interfaces** with context-sensitive controls

## Integration Capabilities

- **MIDI Clock** sync (internal/external)
- **Crow** integration for modular synthesis
- **Multiple MIDI devices** simultaneously
- **Grid controllers** (Monome/Launchpad)
- **MIDI controllers** (LaunchControl)
- **Preset recall** via MIDI program changes

## Summary

**Foobar** is a professional-grade music sequencer that combines the power of a traditional DAW with the flexibility of modular synthesis. Its modular architecture, comprehensive MIDI support, and advanced musical features make it suitable for both live performance and studio production on the Norns platform.

**Key Strengths:**
- **Comprehensive feature set** rivaling commercial sequencers
- **Modular, maintainable codebase** with clear architecture
- **Hardware integration** supporting multiple device types
- **Musical intelligence** with scale/chord awareness
- **Live performance** optimized with real-time controls

**Target Users:**
- Electronic musicians and producers
- Modular synthesis enthusiasts  
- Live performers requiring sophisticated sequencing
- Developers interested in music software architecture