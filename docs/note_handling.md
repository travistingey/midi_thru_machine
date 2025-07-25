# Note Handling Flow

This document describes how MIDI notes travel through the application and how the event based system in `devicemanager.lua` manages them.

## Overview

Notes originate from a track's **Input** component. Depending on the `input_type` the track may generate notes internally (arpeggiator, random, bitwise, etc.) or forward incoming MIDI and transport events. Generated notes are emitted as plain tables with `type`, `note`, `vel` and channel fields.

Each track builds a processing chain consisting of `auto`, `input`, `scale`, `mute` and `output` components. The chain is created by `Track:build_chain()` and called whenever the track processes MIDI or transport data. The relevant note path is:

```
Input → Scale → Mute → Output → DeviceManager
```

* `Scale` quantizes or follows other tracks and may change `data.note` by setting `data.new_note`.
* `Mute` optionally blocks events.
* `Output` forwards the (possibly modified) event to the configured output device using `track.output_device:send(data)`.

## DeviceManager responsibilities

`DeviceManager` wraps all physical and virtual devices. For MIDI devices the `MIDIDevice:send` method performs additional note handling:

1. When a `note_on` message is sent, the manager registers temporary listeners for the events `note_on`, `note_off`, `kill` and `interrupt` on that device.
2. It builds a pending `note_off` table that mirrors the sent note (using `data.new_note` when present).
3. If any of the watched events occurs, or if `send` is called with no further events, the pending `note_off` is transmitted and the listeners are removed.
4. `interrupt_note` or `interrupt_scale` events can trigger an early `note_off` when the active scale would change the sounding pitch. `interrupt_scale` checks the new scale by calling `scale:quantize_note(off)` and compares the resulting pitch class.

This mechanism ensures notes end correctly even when scales or tracks change between the on and off events.

Incoming MIDI from a device is routed in `MIDIDevice:process_midi` which dispatches events to tracks based on their `midi_in` settings. Tracks listening for triggers handle them via their `Input` modules.

## Event based note flow

1. **Track → Device**: a component sends a `note_on` table to the device manager.
2. **DeviceManager** sends the message to the hardware and attaches temporary listeners.
3. **Scale change or new note** may emit `interrupt_note` or `interrupt_scale`. These events propagate through the manager and can cause the pending `note_off` to fire immediately.
4. **Track → Device** later emits the matching `note_off`. If no interrupt occurred, the manager forwards it normally and clears the listener.

The result is that every note_on has exactly one corresponding note_off regardless of intervening events or scale changes.

## Sequencer integration

The forthcoming `seq` component will emit note events into the same pipeline. It
will record and play back note tables just like other inputs. When implemented it
should rely on the existing event based handling so that recorded phrases respect
scale interrupts and device‑level note management. Tests should verify that
sequenced notes also receive matching `note_off` messages even when scales change
mid phrase.
