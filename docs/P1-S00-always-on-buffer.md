# User Story: P1-S00 - Always-On Buffer Recording System

## Story
**As a** improviser  
**I want** the system to always be recording the last 64 bars of my playing  
**So that** I never lose a good idea and can capture spontaneous moments

## Details

### Description
Implement a double-buffer recording system that continuously captures MIDI input. One buffer is "frozen" (available for playback/export), while another is always recording. Users can swap buffers at any time to preserve recent performance without stopping the flow.

### Current State
- `auto.lua` component has some buffer recording functionality
- Buffer recording may require manual start/stop
- No continuous/circular buffer implementation
- Risk of losing spontaneous musical ideas

### Proposed Solution

#### Double Buffer Architecture
```
Buffer A (Frozen):  [================] ← Available for playback/export
Buffer B (Recording): [=====>        ] ← Always capturing input

User presses "Freeze" → Buffers swap roles:
Buffer A (Recording): [>              ] ← Now capturing
Buffer B (Frozen):  [================] ← Contains previous recording
```

#### Key Features
- **Always recording**: One buffer continuously captures MIDI input
- **Circular buffer**: Oldest data is overwritten when buffer fills (64 bars)
- **Instant freeze**: Swap buffers on button press
- **No gaps**: Recording never stops, even during freeze operation
- **Timestamped events**: Store MIDI events with tick-accurate timestamps
- **Efficient storage**: Only store events (note-on/off), not empty ticks

### Technical Considerations

#### Buffer Data Structure
```lua
Buffer = {
  events = {},        -- Array of MIDI events
  start_tick = 0,     -- Tick when buffer started
  length_ticks = 0,   -- Total length in ticks (e.g., 64 bars * 96 ticks/bar)
  max_length = 6144,  -- 64 bars * 96 ticks (assuming 24 ppqn * 4 beats)
  recording = true,   -- Is this buffer currently recording?
}

Event = {
  tick = 0,           -- Relative tick position in buffer
  type = 'note_on',   -- 'note_on' or 'note_off'
  note = 60,          -- MIDI note number
  velocity = 100,     -- Velocity (0-127)
  channel = 1,        -- MIDI channel
}
```

#### Memory Management
- **Circular buffer**: When `tick > max_length`, wrap around
- **Event pruning**: Remove events older than `max_length`
- **Efficient insertion**: Use table insert, prune on overflow
- **Memory estimate**: 64 bars @ 4 notes/beat = ~1024 events max
  - Each event: ~5 fields × 8 bytes = 40 bytes
  - Total: ~40KB per buffer × 2 buffers = 80KB (negligible)

#### Integration with Transport
```lua
function Auto:transport_event(data)
  if data.type == 'tick' then
    local current_tick = data.tick
    
    -- Update recording buffer
    self.recording_buffer.length_ticks = current_tick - self.recording_buffer.start_tick
    
    -- Prune old events from circular buffer
    if self.recording_buffer.length_ticks > self.recording_buffer.max_length then
      self:prune_old_events(self.recording_buffer, current_tick - self.recording_buffer.max_length)
    end
  end
end

function Auto:midi_event(data)
  if self.recording_buffer.recording then
    local event = {
      tick = clock.get_ticks(),  -- or relative to buffer start
      type = data.type,
      note = data.note,
      velocity = data.velocity,
      channel = data.ch,
    }
    table.insert(self.recording_buffer.events, event)
  end
end
```

### Acceptance Criteria
- [ ] System records MIDI input continuously from script start
- [ ] Recording maintains 64 bars of history (circular buffer)
- [ ] "Freeze" command swaps buffers instantly (< 10ms)
- [ ] Frozen buffer contains accurate event data with timestamps
- [ ] Recording buffer never stops, even during freeze operation
- [ ] Memory usage stays bounded (no infinite growth)
- [ ] No dropped notes or timing inaccuracies
- [ ] Works with all MIDI input types (keyboard, arp, random, bitwise)
- [ ] Buffer state persists across preset changes
- [ ] Visual indicator shows recording is active

## Dependencies
- Transport/clock system for tick counting
- `auto.lua` component or new buffer management module
- MIDI event routing architecture
- Understanding of Norns clock resolution (ppqn)

## Blockers
- **Critical**: Investigate current `auto.lua` implementation
  - Does it already have buffer recording?
  - What's the data structure?
  - How does it integrate with transport?
- **Decision needed**: Where should buffers live?
  - Per-track? (each track has own buffer)
  - Global? (one system-wide buffer)
  - **Recommendation**: Per-track for multi-track recording
- **Decision needed**: What's the max buffer length?
  - 64 bars (your suggestion) = ~6144 ticks @ 24ppqn
  - Adjustable? Or fixed?
  - **Recommendation**: Start with fixed 64 bars, make adjustable later

## Estimated Effort
**Large** (4-5 days)
- Architecture design: 4-6 hours
- Buffer data structure implementation: 4-6 hours
- Circular buffer logic: 3-4 hours
- Integration with transport: 3-4 hours
- Integration with MIDI event flow: 4-6 hours
- Freeze/swap mechanism: 2-3 hours
- Memory optimization: 2-3 hours
- Testing and debugging: 6-8 hours

## Priority
**Critical** - This is the foundation of Phase 1. Without always-on recording, users can't capture spontaneous ideas.

## Related Stories
- P1-S06: Buffer → Bitwise (depends on this buffer system)
- All Phase 2 stories about clips (will use this buffer as source)

## Notes

### Performance Considerations
- Event insertion should be O(1) - use simple table.insert()
- Event pruning should be batched (don't prune every event, prune every N ticks)
- Consider using a ring buffer data structure for efficiency
- Profile memory usage with long recording sessions

### UX Considerations
- Show buffer fill state on screen (e.g., "Buffer: 32/64 bars")
- Visual feedback when freeze happens (flash screen, grid response)
- Consider auto-freeze on buffer full (optional safety feature)
- Make freeze operation reversible? (undo last freeze)

### Future Enhancements
- **Multiple buffers**: More than 2 (A/B/C/D for layering)
- **Buffer length adjustment**: User-configurable max length
- **Export buffer**: Save to MIDI file
- **Undo/redo**: Buffer history stack
- **Pre-roll**: Capture events from before freeze was pressed

### Testing Strategy
1. **Basic recording**: Verify events are captured with correct timestamps
2. **Circular wrap**: Fill buffer beyond 64 bars, verify oldest events pruned
3. **Freeze operation**: Verify swap happens without dropped notes
4. **Long sessions**: Run for hours, check memory doesn't grow
5. **Edge cases**: What happens on transport stop? Script reload?

### Investigation Needed
Look at `auto.lua` current implementation:
```lua
-- Questions to answer:
-- 1. Does buffer recording already exist?
-- 2. What's the data structure?
-- 3. How does it handle transport events?
-- 4. Is there existing freeze/capture functionality?
-- 5. How does it interact with playback?
```
