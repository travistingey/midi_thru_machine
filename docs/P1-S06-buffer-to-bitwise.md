# User Story: P1-S06 - Freeze Buffer into Bitwise Sequence

## Story
**As a** improviser  
**I want to** freeze my current buffer recording into a bitwise sequence  
**So that** my played notes become the seed for algorithmic morphing

## Details

### Description
Convert the contents of the active buffer recording into a bitwise sequence seed. The buffer's note values and timings become the initial state of the bitwise algorithm, which can then be morphed, locked, and performed.

### Current State
- Buffer recording exists in `auto.lua` component
- Bitwise sequencer runs independently with random seeds
- No connection between what you play and what bitwise generates
- Users must manually program bitwise or rely on random initialization

### Proposed Solution
- Add "Freeze to Bitwise" command (triggered by button/key)
- Extract note events from buffer at step boundaries
- Map buffer note values to bitwise `values[]` array
- Map buffer note timings to bitwise `triggers[]` array
- Quantize buffer data to bitwise step resolution (1/16, 1/8, etc.)
- Optionally lock all captured steps initially (user can unlock to allow morphing)

### Technical Considerations

#### Buffer Data Structure
- Buffer stores MIDI events with timestamps: `{note, velocity, timestamp}`
- Need to find buffer data structure in `auto.lua` component
- Must understand buffer's time resolution (ticks per step)

#### Bitwise Data Mapping
```lua
-- Pseudocode for conversion
function buffer_to_bitwise(buffer, length, step_resolution)
  local bitwise = Bitwise:new({length = length})
  
  for step = 1, length do
    local time_window = step * step_resolution
    local notes_at_step = buffer:get_notes_at_time(time_window)
    
    if #notes_at_step > 0 then
      -- Take first note (or highest, or lowest?)
      local note = notes_at_step[1]
      bitwise.triggers[step] = true
      bitwise.values[step] = note.velocity / 127  -- Normalize
      bitwise.lock[step] = true  -- Lock captured notes initially
    else
      bitwise.triggers[step] = false
      bitwise.values[step] = 0
      bitwise.lock[step] = false
    end
  end
  
  bitwise:update()  -- Regenerate internal track value
  return bitwise
end
```

#### Quantization Strategy
- Buffer may have notes at arbitrary times
- Must "snap" to nearest step boundary
- Options:
  1. **Nearest step**: Round to closest step
  2. **Floor**: Always round down
  3. **Threshold**: Only capture if within X% of step boundary

**Recommendation**: Nearest step for most intuitive results

### Acceptance Criteria
- [ ] "Freeze to Bitwise" command accessible via grid/key
- [ ] Buffer notes accurately captured to bitwise steps
- [ ] Timing quantization feels musical (steps align sensibly)
- [ ] Captured notes are locked by default (don't immediately mutate)
- [ ] Empty buffer sections create silent steps (triggers off)
- [ ] Velocity information preserved in bitwise values
- [ ] Conversion completes quickly (< 100ms, imperceptible)
- [ ] Multiple freezes overwrite previous bitwise seed

## Dependencies
- Buffer recording system in `auto.lua`
- Bitwise component (`lib/utilities/bitwise.lua`)
- Understanding of buffer data structure and access methods
- P1-S04: Lock visualization (to show locked captured notes)

## Blockers
- **Critical**: Need to examine `auto.lua` buffer implementation
  - How is data stored? (`events` table? `note_events`?)
  - How to query notes at specific times?
  - What's the time resolution? (ticks? milliseconds?)
- **Decision needed**: What to do with polyphonic buffer content?
  - Take highest note? Lowest note? First note?
  - **Recommendation**: Take lowest note (typical bass/melody behavior)
- **Decision needed**: Should velocity map to bitwise value or be separate?
  - **Recommendation**: Store separately - velocity should affect MIDI output

## Estimated Effort
**Medium-Large** (3-4 days)
- Buffer investigation and data extraction: 4-6 hours
- Conversion algorithm implementation: 4-6 hours
- Quantization and timing logic: 3-4 hours
- Integration with existing bitwise: 2-3 hours
- Lock initialization: 1-2 hours
- Testing with various buffer contents: 4-6 hours

## Priority
**Critical** - This is the bridge between "playing" and "morphing". Without this, bitwise remains disconnected from user input.

## Related Stories
- P1-S01: Grid visualization (will show the frozen sequence)
- P1-S04: Lock visualization (will show captured notes as locked)
- P1-S05: Grid lock control (allows unlocking steps to enable morphing)
- P1-S07: Scale-aware mutation (should respect buffer's original scale)

## Notes
- Consider preserving scale information from buffer (what scale was active during recording?)
- Future enhancement: Multiple freeze operations create variations
- Future enhancement: "Freeze region" to capture only part of buffer
- Future enhancement: Polyphonic freeze creates multiple bitwise tracks
- The `Bitwise:seed(track)` method can be used to set the initial state
- Consider audio/visual feedback when freeze happens (flash screen, beep)
- May want to normalize buffer length to bitwise length (stretch/compress timing)

## Investigation Needed
Before implementing, research:
1. Buffer data structure in `auto.lua`
2. Time resolution and units
3. How to efficiently query notes at specific times
4. Whether buffer stores note-off events (duration) or just note-on
