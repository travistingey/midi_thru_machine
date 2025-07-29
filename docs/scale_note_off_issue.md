# Scale Change Note Off Bug

This document summarizes how note on/off tracking interacts with the `Scale` component and explains
why notes may remain held when the scale changes between the `note_on` and `note_off` events.

## DeviceManager logic

When a `note_on` event is sent to a MIDI device, `MIDIDevice:send` registers temporary listeners and
stores a pending `note_off` message:

```
local off = {
    type = 'note_off',
    note_id = data.note_id or data.note,
    note = data.note,
    vel  = data.vel,
    ch   = data.ch,
}
if data.new_note then
    off.note = data.new_note
end
```

During an `interrupt_scale` event the manager checks the new scale and compares pitch classes:

```
local requantized = next.scale:quantize_note(off)
if off.note % 12 ~= requantized.new_note % 12 then
    self.device:send(off)
end
```

Lines 94‑141 of `devicemanager.lua` implement this logic.

## Intended interrupt behavior

`interrupt_scale` should only terminate notes that are no longer part of the
active scale. For example, if notes quantized to C major (`C`, `E` and `G`) are
held when the scale changes to D major, only the `C` notes should be stopped.
`E` and `G` remain valid in the new scale and must continue sounding until their
regular `note_off` events arrive.

## Interaction with `Scale:midi_event`

The `Scale` component modifies messages by setting `data.new_note` while leaving `data.note`
unchanged. Triggered inputs generate `note_off` events using the last played note
from `Input:midi_trigger` or `clock_trigger`:

```
local off = { type = 'note_off', note = event.note, vel = event.vel }
```

When a scale change occurs before this `note_off` is processed, the note is re‑quantized,
so the hardware receives a different pitch than was originally sounded.
`MIDIDevice` believes the note was turned off because the original `note` matches
`note_id`, but the device actually receives `note_off` for the wrong pitch.

## Gaps in the current logic

1. `interrupt_scale` only checks the pitch class (`% 12`). Transposing the scale by an
   octave keeps the same class and therefore does not trigger an interrupt.
2. The subsequent `note_off` event still uses the original `note` field, causing
   the manager to skip sending the stored `off` message even though the output
   note has changed.
3. This affects both physical MIDI input and internally generated notes, since
   they travel through the same `send` pipeline.

### Pitch‑class based interrupts

`interrupt_scale` intentionally checks only the note\'s pitch class because
scales are defined as collections of classes. A note should keep playing if the
same class still exists in the new scale, even when the octave changes. The
pending `off` table is transmitted only when the new scale no longer contains
that class.

Earlier versions stored the unquantized pitch in `Input.last_note`, so a
`note_off` was generated for the original key even if quantization changed the
outgoing note. The device therefore received a different note-off than it had
played, leaving it stuck on. This affected both physical MIDI and triggered
notes because they travel through the same pipeline.

`Input.last_note` now stores the quantized pitch, ensuring that internally
generated note-off events match the note actually sent to the device.
