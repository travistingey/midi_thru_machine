# User Story: P1-S01 - Grid Visualization of Bitwise Triggers

## Story
**As a** performer  
**I want to** see the bitwise trigger pattern displayed on my grid controller  
**So that** I can understand what the algorithm is playing in real-time

## Details

### Description
Display the current state of the bitwise sequencer's trigger pattern on the grid controller (Launchpad/Monome). Each step should show whether it will trigger a note (on) or remain silent (off).

### Current State
- Bitwise sequencer runs internally with triggers stored in `self.triggers[]` table
- Grid controller exists but doesn't visualize bitwise state
- Users cannot see what the algorithm is doing

### Proposed Solution
- Map bitwise sequencer steps to grid columns (16 steps across)
- Use LED brightness/color to indicate trigger state:
  - **Bright/On**: Trigger active (will play note)
  - **Dim/Off**: Trigger inactive (will skip note)
- Update display on every transport tick to show current position
- Highlight the currently playing step with different color/brightness

### Technical Considerations
- Bitwise component has `length` property (default 16)
- Triggers are boolean array: `self.triggers[i]`
- Grid modes exist in `lib/modes/` - need to create or extend bitwise mode
- Grid refresh rate needs to match transport tick rate
- Consider grid button layout: one row = one track's bitwise pattern

### Acceptance Criteria
- [ ] Bitwise trigger pattern displays on grid when bitwise mode is active
- [ ] On/off states are clearly visually distinguishable
- [ ] Display updates in real-time as sequence plays
- [ ] Current step position is highlighted distinctly
- [ ] Display works for sequences from 1-16 steps

## Dependencies
- Existing grid controller integration (`lib/grid.lua`)
- Bitwise component (`lib/utilities/bitwise.lua`)
- Transport/clock system for step updates

## Blockers
- None currently identified

## Estimated Effort
**Medium** (2-3 days)
- Grid mode component: 4-6 hours
- Integration with bitwise component: 2-3 hours
- Visual design/LED mapping: 2-3 hours
- Testing across different grid controllers: 2-3 hours

## Priority
**Critical** - This is the foundation for all other bitwise UI work. Without visualization, users cannot understand or control the algorithm.

## Related Stories
- P1-S02: Grid control (depends on this)
- P1-S04: Lock visualization (extends this)

## Notes
- Consider supporting both Launchpad and Monome grid layouts
- May need separate visualization strategies for 8×8 vs 16×8 grids
- Future: Could show both triggers AND values in different grid sections
