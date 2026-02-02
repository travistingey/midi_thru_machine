# Buffer and Clip Component Architecture

## Overview

The Buffer and Clip components work together to provide a single-buffer recording and playback system with clear separation of concerns:

- **Buffer Component**: Handles **recording only** - continuously records MIDI events silently to `buffer.buffer`
- **Clip Component**: Handles **playback only** - plays back from frozen buffers, scrub buffers, or saved clips

## Single Buffer Architecture

### `buffer.buffer` (Recording Buffer)
- **Purpose**: Continuously receives new MIDI events during recording
- **Written to**: Always when transport is playing (regardless of armed state)
- **Read from**: Never directly read for playback (only for creating frozen buffers, scrub buffers, or saving clips)
- **Updated**: Continuously as MIDI events come in
- **Behavior**: Always loops and overwrites - wraps at `buffer_start + buffer_length`

## Recording Conditions

A track records into `buffer.buffer` when **ALL** of the following are true:

1. **Transport is playing**: `App.playing == true` and `buffer.playing == true`
2. **MIDI events are received**: Events flow through the track's input chain
3. **Event doesn't have `buffer_sent` flag**: Prevents playback events from being recorded back

### Recording Flow

```
MIDI Input → Track Input Component → Track Processing Chain → Buffer:record_buffer()
                                                                  ↓
                                                          buffer.buffer[tick] = events
```

### Recording Behavior

- **Buffer always loops**: When `buffer.tick` reaches `buffer_start + buffer_length`, it wraps to `buffer_start`
- **Always overwrites**: When entering a new step, that step is cleared (unless already cleared in current loop)
- **Step-based clearing**: Uses `overwrite_cleared_steps` to track which steps have been cleared in current loop iteration
- **Continuous recording**: `buffer.tick` continuously increments, wrapping at loop boundaries
- **Silent recording**: Buffer never plays back - all playback is handled by Clip component

## Playback: Clip Component Only

The Clip component handles all playback through three mechanisms:

### 1. Scrub Mode Playback

**Condition**: `clip.scrub_mode == true` (grid-triggered playback)

**Source**: `clip.scrub_buffer` (shallow copy of buffer range)

**Behavior**:
- Creates shallow copy of buffer range `[start_tick, end_tick]` into `scrub_buffer` when scrub starts
- Updates `scrub_buffer` when scrub range changes
- Clears `scrub_buffer` when scrub ends
- **Always blocks input** regardless of monitoring setting (`mute_input = true`)
- Uses `clip.scrub_tick` for playback position

**When Enabled**: Grid pad is pressed/held in BufferSeq mode

### 2. Frozen Buffer Playback

**Condition**: `clip.buffer_frozen == true` and `clip.frozen_buffer` exists

**Source**: `clip.frozen_buffer` (shallow copy of buffer playback range)

**Behavior**:
- Creates shallow copy of buffer range `[playback_start, playback_start + playback_length - 1]` when frozen
- Updates `frozen_buffer` when `playback_length` changes
- **Respects monitoring settings**: AUTO mode mutes input unless armed
- Uses `clip.tick` for playback position

**When Enabled**: Buffer is frozen via BufferSeq mode or other mechanisms

### 3. Loaded Clip Playback

**Condition**: `clip.current_slot ~= nil` and `clip.clip_bank[current_slot]` exists

**Source**: `clip.clip_bank[current_slot].buffer` (saved clip data)

**Playback Position**:
- `clip.tick` starts at `1` (clips are 1-based internally)
- Uses `clip_entry.length` for loop boundaries
- `clip.tick` wraps at clip length

**When Enabled**:
- `clip.playing == true` (transport is playing)
- Clip is loaded and transport is running

**Behavior**:
- **Respects monitoring settings**: AUTO mode mutes input unless armed
- Continues playing when recording starts (clip playback events have `buffer_sent` flag to prevent feedback)
- Playback events are processed according to playback settings (mutations like mutes are applied)

### Playback Source Selection

```lua
function Clip:get_playback_source()
    if self.current_slot and self.clip_bank[self.current_slot] then
        -- Return loaded clip buffer
        return self.clip_bank[self.current_slot].buffer
    else
        -- Return frozen buffer if frozen, otherwise live buffer (for reference only)
        if self.buffer_frozen and self.frozen_buffer then
            return self.frozen_buffer
        elseif self.buffer then
            return self.buffer.buffer
        end
        return nil
    end
end
```

## Scrub Mode

Scrub mode is a special playback mode triggered by grid interactions (e.g., BufferSeq mode).

### Scrub Mode Activation

**Triggered by**: `Clip:start_scrub(start_tick, end_tick, loop_mode)`

**Conditions**:
- Grid pad is pressed/held
- Sync quantization may delay start until next sync boundary

### Scrub Mode Behavior

**Source**: Always reads from `clip.scrub_buffer` (shallow copy of buffer range)

**Position**: Uses `clip.scrub_tick` (separate from `clip.tick`)

**Events Read**: `clip.scrub_buffer[scrub_tick]`

**Input Blocking**: Always blocks input (`mute_input = true`) regardless of monitoring setting

```lua
-- In Clip:transport_event() during scrub mode
if self.scrub_mode and self.scrub_buffer[scrub_lookup_tick] then
    self:run_events(self.scrub_buffer[scrub_lookup_tick])
end
```

### Scrub Mode States

1. **Scrub Loop Mode** (`scrub_loop == true`):
   - Loops within scrub range (`scrub_start` to `scrub_end`)
   - When `scrub_tick > scrub_end`, wraps to `scrub_start`

2. **Scrub Play-Through Mode** (`scrub_loop == false`):
   - Plays through scrub range once
   - If `buffer_loop == false`: stops after one pass
   - If `buffer_loop == true`: continues playing full buffer after scrub range

### Scrub Buffer Management

- **On start**: Creates shallow copy of buffer range into `scrub_buffer`
- **On update**: Updates `scrub_buffer` when range changes (clears old entries, adds new entries)
- **On stop**: Clears `scrub_buffer` and restores input monitoring

## Frozen Buffer

Frozen buffer is a snapshot of the live buffer used for playback, allowing the live buffer to continue recording.

### Frozen Buffer Behavior

**Source**: `clip.frozen_buffer` (shallow copy of buffer playback range)

**When Created**: `Clip:freeze_buffer()` copies buffer range `[playback_start, playback_start + playback_length - 1]`

**When Updated**:
- Incrementally updated during playback (via `update_frozen_step()`)
- Updated when `playback_length` changes (via `set_playback_loop()`)

**Monitoring**: Respects monitoring settings (AUTO mode mutes input during playback)

**When Unfrozen**: `Clip:unfreeze_buffer()` clears frozen buffer and restores input monitoring

## State Management

### Buffer State
- `buffer.tick`: Recording position (continuously running, wraps at loop boundaries)
- `buffer.playing`: Transport state (for recording timing)
- `buffer.buffer`: Single buffer for recording (always loops and overwrites)

### Clip State
- `clip.tick`: Playback position (for normal playback)
- `clip.scrub_tick`: Playback position (for scrub mode)
- `clip.playing`: Transport state (for playback timing)
- `clip.current_slot`: Which clip is loaded (nil = no clip loaded)
- `clip.scrub_buffer`: Shallow copy of buffer range for scrub mode
- `clip.frozen_buffer`: Shallow copy of buffer range for frozen playback
- `clip.buffer_frozen`: Whether buffer is frozen

### Synchronization

- **On transport start**: 
  - Buffer: `tick = buffer_start`
  - Clip (frozen buffer): `tick = playback_start`
  - Clip (loaded clip): `tick = 1` (starts at clip beginning)

- **On transport stop**:
  - Buffer: `tick` continues (buffer is continuously running)
  - Clip: `tick` not reset (playback stops but position preserved)

## Key Differences

| Aspect | Buffer | Clip |
|--------|--------|------|
| **Purpose** | Recording only | Playback only |
| **Writes to** | `buffer.buffer` | Never writes |
| **Reads from** | Never reads | `scrub_buffer`, `frozen_buffer`, or `clip_bank[slot].buffer` |
| **Tick management** | Continuous, wraps at loop | Separate for scrub/frozen/clip playback |
| **Loop behavior** | Always loops | Configurable (loop vs one-shot) |
| **Overwrite** | Always overwrites | N/A (read-only) |
| **Playback** | Never plays back | Handles all playback |

## Example Scenarios

### Scenario 1: Recording and Scrub Playback
1. Transport starts, MIDI events recorded to `buffer.buffer[tick]`
2. User holds grid pad in BufferSeq mode
3. `Clip:start_scrub()` creates `scrub_buffer` shallow copy of buffer range
4. Scrub mode plays from `scrub_buffer[scrub_tick]`
5. Input is blocked regardless of monitoring setting
6. When pad released, `scrub_buffer` is cleared and input monitoring restored

### Scenario 2: Loading a Clip
1. User loads clip from bank slot: `clip:load_clip_from_bank(slot)`
2. `clip.current_slot = slot`
3. `clip.tick = 1` (clip starts at beginning)
4. On transport start: Clip plays from `clip_bank[slot].buffer`
5. Live buffer continues recording in background (if transport is playing)
6. Monitoring respects AUTO mode (mutes input unless armed)

### Scenario 3: Frozen Buffer
1. User sets playback loop boundaries: `clip:set_playback_loop(start, length)`
2. User freezes buffer: `clip:freeze_buffer()`
3. `frozen_buffer` is created as shallow copy of buffer range
4. Live buffer continues recording while frozen buffer plays back
5. Monitoring respects AUTO mode (mutes input unless armed)
6. When unfrozen, `frozen_buffer` is cleared and input monitoring restored

### Scenario 4: Recording While Clip Plays
1. Clip is playing from loaded clip
2. Track is armed for recording
3. Monitor setting determines if input flows:
   - **IN**: Input always flows → overdub
   - **AUTO**: Input flows (clip playing + armed) → overdub
   - **OFF**: Input never flows
4. New events recorded to `buffer.buffer` (live buffer)
5. Clip continues playing from loaded clip (unaffected)
6. Clip playback events have `buffer_sent` flag to prevent feedback
