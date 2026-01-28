# Buffer and Clip Component Architecture

## Overview

The Buffer and Clip components work together to provide a double-buffered recording and playback system with clear separation of concerns:

- **Buffer Component**: Handles **recording only** - continuously records MIDI events to `buffer_write`
- **Clip Component**: Handles **playback only** - plays back from either live buffer (`buffer_read`) or saved clips

## Double Buffer Architecture

### `buffer_write` (Recording Buffer)
- **Purpose**: Always receives new MIDI events during recording
- **Written to**: When track is `armed` and transport is `playing`
- **Read from**: Never directly read for playback (only for saving clips)
- **Updated**: Continuously as MIDI events come in

### `buffer_read` (Playback Buffer)
- **Purpose**: Read-only buffer for Clip component playback
- **Written to**: Populated by `swap_buffer_step()` at step boundaries
- **Read from**: Clip component reads from this for live buffer playback
- **Updated**: At step transitions (not loop boundaries) for immediate feedback

### Buffer Swapping
```lua
-- Called on step transitions during recording
Buffer:swap_buffer_step(step_index)
```
- Swaps data from `buffer_write` to `buffer_read` for a single step
- Happens at **step boundaries** (not loop boundaries) for immediate feedback
- Only swaps when track is `armed` and during step transitions
- Ensures Clip can play back recently recorded data within one step

## Recording Conditions

A track records into `buffer_write` when **ALL** of the following are true:

1. **Track is armed**: `track.armed == true`
2. **Transport is playing**: `App.playing == true` and `buffer.playing == true`
3. **MIDI events are received**: Events flow through the track's input chain

### Recording Flow

```
MIDI Input → Track Input Component → Track Processing Chain → Buffer:record_buffer()
                                                                  ↓
                                                          buffer_write[tick] = events
```

### Recording Behavior

- **Buffer always loops**: When `buffer.tick` reaches `seq_start + seq_length`, it wraps to `seq_start`
- **Always overwrites**: When entering a new step, that step is cleared (unless already cleared in current loop)
- **Step-based clearing**: Uses `overwrite_cleared_steps` to track which steps have been cleared in current loop iteration
- **Continuous recording**: `buffer.tick` continuously increments, wrapping at loop boundaries

### Step Swapping During Recording

```lua
-- In Buffer:transport_event() on clock tick
local current_step_index = self:tick_to_step_index(self.tick)
-- Swap on step exit (when entering new step, swap the completed step)
if self.last_step_index and current_step_index ~= self.last_step_index and self.track.armed then
    self:swap_buffer_step(self.last_step_index)
end
```

This ensures that:
- Recorded data becomes available for playback within one step
- Clip can play back data that was just recorded
- No race conditions between recording and playback

## Playback: Buffer vs Clip

The Clip component decides what to play back based on `current_slot`:

### Live Buffer Playback

**Condition**: `clip.current_slot == nil` (no clip loaded)

**Source**: `clip.buffer.buffer_read` (the read-only playback buffer)

**Playback Position**: 
- `clip.tick` syncs to `buffer.tick` when transport starts
- Uses `buffer.seq_start` and `buffer.seq_length` for loop boundaries
- `clip.tick` wraps at loop boundaries

**When Enabled**: 
- `buffer.buffer_playback == true` (parameter controlled)
- Or `clip.scrub_mode == true` (grid-triggered scrub)

### Loaded Clip Playback

**Condition**: `clip.current_slot ~= nil` and `clip.clip_bank[current_slot]` exists

**Source**: `clip.clip_bank[current_slot].buffer` (saved clip data)

**Playback Position**:
- `clip.tick` starts at `1` (clips are 1-based internally)
- Uses `clip_entry.length` for loop boundaries
- `clip.tick` wraps at clip length

**When Enabled**:
- `clip.playing == true` (transport is playing)
- Clip is loaded and transport is running

### Playback Source Selection

```lua
function Clip:get_playback_source()
    if self.current_slot and self.clip_bank[self.current_slot] then
        -- Return loaded clip buffer
        return self.clip_bank[self.current_slot].buffer
    else
        -- Return live buffer
        if self.buffer then return self.buffer.buffer_read end
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

**Source**: Always reads from `buffer.buffer_read` (live buffer only)

**Position**: Uses `clip.scrub_tick` (separate from `clip.tick`)

**Events Read**: `buffer.buffer_read[scrub_tick]`

```lua
-- In Clip:transport_event() during scrub mode
if self.scrub_mode and self.buffer.buffer_read[self.scrub_tick] then
    self:run_events(self.buffer.buffer_read[self.scrub_tick])
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

### Scrub vs Normal Playback

- **Normal Playback**: Uses `clip.tick` and `get_playback_source()` (can be clip or buffer)
- **Scrub Mode**: Always uses `clip.scrub_tick` and `buffer.buffer_read` (only live buffer)
- **Scrub takes precedence**: When `scrub_mode == true`, normal playback is bypassed

## State Management

### Buffer State
- `buffer.tick`: Recording position (continuously running, wraps at loop boundaries)
- `buffer.playing`: Transport state (for recording timing)
- `buffer.armed`: Not stored in buffer (track-level property)

### Clip State
- `clip.tick`: Playback position (for normal playback)
- `clip.scrub_tick`: Playback position (for scrub mode)
- `clip.playing`: Transport state (for playback timing)
- `clip.current_slot`: Which clip is loaded (nil = live buffer)

### Synchronization

- **On transport start**: 
  - Buffer: `tick = seq_start`
  - Clip (live buffer): `tick = buffer.tick` (syncs to buffer)
  - Clip (loaded clip): `tick = 1` (starts at clip beginning)

- **On transport stop**:
  - Buffer: `tick = seq_start` (resets to loop start)
  - Clip: `tick` not reset (buffer is continuously running)

## Key Differences

| Aspect | Buffer | Clip |
|--------|--------|------|
| **Purpose** | Recording | Playback |
| **Writes to** | `buffer_write` | Never writes |
| **Reads from** | Never reads | `buffer_read` or `clip_bank[slot].buffer` |
| **Tick management** | Continuous, wraps at loop | Separate for normal/scrub playback |
| **Loop behavior** | Always loops | Configurable (loop vs one-shot) |
| **Overwrite** | Always overwrites | N/A (read-only) |

## Example Scenarios

### Scenario 1: Recording and Immediate Playback
1. Track is armed, transport starts
2. MIDI events recorded to `buffer_write[tick]`
3. At step boundary: `swap_buffer_step()` copies to `buffer_read`
4. If `buffer_playback == true`: Clip plays from `buffer_read[tick]`
5. User hears what they just recorded within one step

### Scenario 2: Loading a Clip
1. User loads clip from bank slot: `clip:load_clip_from_bank(slot)`
2. `clip.current_slot = slot`
3. `clip.tick = 1` (clip starts at beginning)
4. On transport start: Clip plays from `clip_bank[slot].buffer`
5. Live buffer continues recording in background (if armed)

### Scenario 3: Scrub Mode
1. User holds grid pad in BufferSeq mode
2. `clip:start_scrub(start_tick, end_tick, loop_mode)` called
3. `clip.scrub_mode = true`
4. On each clock tick: Reads `buffer.buffer_read[scrub_tick]`
5. `scrub_tick` increments, wrapping at scrub boundaries
6. Normal playback (`clip.tick`) continues in background but is bypassed

### Scenario 4: Recording While Clip Plays
1. Clip is playing from loaded clip
2. Track is armed
3. Monitor setting determines if input flows:
   - **IN**: Input always flows → overdub
   - **AUTO**: Input flows (clip playing + armed) → overdub
   - **OFF**: Input never flows
4. New events recorded to `buffer_write` (live buffer)
5. Clip continues playing from loaded clip (unaffected)
