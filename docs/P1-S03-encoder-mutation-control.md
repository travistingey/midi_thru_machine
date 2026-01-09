# User Story: P1-S03 - Encoder Control of Mutation Chance

## Story
**As a** performer  
**I want to** adjust mutation probability with an encoder  
**So that** I can control how much the sequence morphs over time

## Details

### Description
Provide encoder-based control of the bitwise sequencer's mutation chance parameter. As the user turns the encoder, mutation probability should change from 0.0 (no mutation) to 1.0 (always mutate), with immediate audible results.

### Current State
- Bitwise component has `chance` property (default 0.5)
- `Bitwise:mutate(i)` method checks `math.random() < self.chance`
- No UI control for mutation chance
- Users cannot adjust mutation probability during performance

### Proposed Solution
- Dedicate one of Norns' 3 encoders to mutation chance
- Display current value on screen (e.g., "Mutation: 75%")
- Update value in real-time as encoder turns
- Consider logarithmic scaling for more control in "musical" range (0.1-0.5)
- Provide visual feedback on both screen and grid (optional)

### Technical Considerations
- Norns encoders: E1 (coarse), E2, E3 (fine)
- Encoder sensitivity: `delta * 0.01` for 0.00-1.00 range
- Need to determine which UI mode this control belongs to (bitwise mode?)
- Must update `track.input.bitwise.chance` or wherever bitwise instance lives
- Consider: Should this be a per-track parameter or global bitwise setting?
- Screen UI needs to show current value and respond to encoder turns

### Acceptance Criteria
- [ ] Turning encoder changes mutation chance from 0.0 to 1.0
- [ ] Current value displays on screen with clear labeling
- [ ] Changes take effect immediately (next mutation check uses new value)
- [ ] Encoder feel is smooth (appropriate sensitivity/resolution)
- [ ] Value persists when switching UI pages and returning
- [ ] Setting to 0.0 completely stops mutation
- [ ] Setting to 1.0 causes mutation every step (where not locked)

## Dependencies
- Norns encoder system (`function enc(n, delta)`)
- Bitwise component (`lib/utilities/bitwise.lua`)
- Screen UI rendering (`lib/ui.lua`)
- Understanding of which track/bitwise instance to control

## Blockers
- **Decision needed**: Is mutation chance per-track or global?
  - **Recommendation**: Per-track (stored in `track.input.bitwise.chance`)
  - Allows different tracks to have different mutation behaviors
- **Decision needed**: Which UI mode owns this control?
  - **Recommendation**: Active when track's input type is "bitwise"

## Estimated Effort
**Small** (1-2 days)
- Encoder handler implementation: 2-3 hours
- Screen UI for display: 2-3 hours
- Integration with active track selection: 2-3 hours
- Testing across different encoder speeds: 1-2 hours

## Priority
**High** - Core parameter for making bitwise musically useful. Without this, mutation is fixed at default 50%.

## Related Stories
- P1-S01: Grid visualization (complements visual control with numeric control)
- P1-S04: Lock visualization (locked steps ignore mutation chance)

## Notes
- Consider adding visual indicator of mutation on grid (steps that just mutated flash?)
- Future enhancement: Automate mutation chance over time (LFO, envelope)
- Future enhancement: MIDI CC control for external hardware
- Consider showing mutation history on screen (graph of last N mutations)
- The `Bitwise:mutate(i)` method is already called from somewhere - find where and ensure encoder changes are respected
