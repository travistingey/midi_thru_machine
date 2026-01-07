# User Story: P1-S02 - Grid Control of Bitwise Triggers

## Story
**As a** performer  
**I want to** tap grid pads to toggle trigger states  
**So that** I can shape the algorithmic sequence during performance

## Details

### Description
Enable direct manipulation of bitwise trigger patterns via grid controller. Tapping a step should immediately toggle its trigger state (on→off or off→on), allowing real-time performance control of which notes play.

### Current State
- Grid displays trigger states (from P1-S01)
- No input handling for grid in bitwise mode
- Users cannot modify trigger pattern without diving into parameters

### Proposed Solution
- Map grid button presses to trigger toggles
- Implement immediate visual feedback (LED updates instantly)
- Maintain toggle state across sequence cycling
- Consider two interaction modes:
  - **Momentary**: Hold to temporarily enable/disable trigger
  - **Toggle**: Tap to permanently flip trigger state
- Start with toggle mode for simplicity

### Technical Considerations
- Grid input handled in grid mode components via `grid.key(x, y, z)` callback
- Need to map grid coordinates to bitwise step index
- Must update both `Bitwise.triggers[]` table and internal bit representation
- Consider whether to call `Bitwise:update()` or manipulate triggers directly
- May need to handle multi-track scenarios (which track's bitwise to control?)

### Acceptance Criteria
- [ ] Tapping a grid pad toggles corresponding trigger state
- [ ] Visual feedback is immediate (LED changes on press)
- [ ] Toggle persists across sequence loops
- [ ] Multiple rapid toggles work without lag or missed inputs
- [ ] Current playing step doesn't interfere with toggle operations
- [ ] Toggling works during both playback and stopped states

## Dependencies
- P1-S01: Grid visualization (must be complete)
- Grid input system (`lib/grid.lua`)
- Bitwise component toggle mechanism

## Blockers
- Need to decide: Does toggling modify the internal `track` value (16-bit number) or just the `triggers[]` array?
  - **Recommendation**: Modify both to maintain consistency
  - Use `Bitwise:flip(i)` method which handles both

## Estimated Effort
**Small** (1-2 days)
- Grid input handler: 2-3 hours
- Integration with Bitwise:flip(): 1-2 hours
- Visual feedback refinement: 2-3 hours
- Testing edge cases: 2-3 hours

## Priority
**Critical** - This transforms bitwise from "invisible algorithm" to "performable instrument"

## Related Stories
- P1-S01: Grid visualization (prerequisite)
- P1-S04: Lock visualization (will add complexity to input handling)
- P1-S05: Grid lock control (will modify input behavior)

## Notes
- Consider adding audio feedback (click/beep) on toggle for accessibility
- Future enhancement: Multi-select (hold button + tap multiple steps)
- Future enhancement: Copy/paste trigger patterns between tracks
- The `Bitwise:flip(i)` method already exists and handles bit flipping + update
