# User Story: P1-S04 - Lock Visualization on Grid

## Story
**As a** composer  
**I want to** see which steps are locked on the grid  
**So that** I can understand which parts of my sequence are fixed vs morphing

## Details

### Description
Visually distinguish locked steps from unlocked steps on the grid display. Locked steps should not mutate their values, creating stable "anchor points" in an otherwise evolving sequence.

### Current State
- Bitwise component has `lock[]` table (boolean per step)
- Locked steps don't mutate when `Bitwise:mutate(i)` is called
- Grid shows trigger on/off but not lock state (from P1-S01)
- Users cannot see which steps are protected from mutation

### Proposed Solution
- Use different LED colors/brightness to indicate lock state:
  - **Locked + Trigger On**: Bright color (e.g., amber/orange)
  - **Unlocked + Trigger On**: Standard bright (e.g., white/green)
  - **Locked + Trigger Off**: Dim color
  - **Unlocked + Trigger Off**: Standard dim
- Consider adding border/pulsing effect for locked steps
- Ensure lock state is visible at a glance without mental translation

### Technical Considerations
- Grid LED capabilities vary by controller:
  - Launchpad: RGB, multiple brightness levels
  - Monome: Monochrome, 16 brightness levels
- Need unified color scheme that works across controllers
- Lock state stored in `Bitwise.lock[]` array
- Must check both `triggers[i]` and `lock[i]` when rendering each step
- Consider performance: rendering happens every frame/tick

### Color Scheme Proposal (Launchpad RGB)
```
Unlocked + Trigger On:  GREEN (bright)
Unlocked + Trigger Off: BLACK (off)
Locked + Trigger On:    AMBER (bright)
Locked + Trigger Off:   AMBER (dim)
Current Step (playing): WHITE (pulse)
```

### Acceptance Criteria
- [ ] Locked steps are visually distinct from unlocked steps
- [ ] Lock state is visible whether trigger is on or off
- [ ] Visual distinction works on both RGB and monochrome grids
- [ ] Lock state updates immediately when changed
- [ ] Playing position indicator doesn't obscure lock state
- [ ] Color scheme is intuitive (no training needed to understand)

## Dependencies
- P1-S01: Grid visualization (extends this)
- Grid controller LED capabilities
- Bitwise `lock[]` array

## Blockers
- **Decision needed**: Color scheme that works universally
  - Test on actual Launchpad and Monome hardware
  - May need separate implementations per controller type

## Estimated Effort
**Small** (1-2 days)
- Color scheme design and testing: 3-4 hours
- Implementation in grid renderer: 2-3 hours
- Cross-controller compatibility: 2-3 hours
- Visual polish and refinement: 2-3 hours

## Priority
**High** - Essential for understanding the bitwise sequencer's behavior. Without this, users won't know what's locked.

## Related Stories
- P1-S01: Grid visualization (prerequisite)
- P1-S05: Grid lock control (this provides visual feedback for that)
- P1-S06: Buffer → Bitwise (captured notes will likely be locked initially)

## Notes
- Consider accessibility: Don't rely on color alone (use brightness too)
- Future enhancement: Gradient showing "lock strength" (probability of mutation even when "locked")
- Future enhancement: Group locks (lock entire phrases)
- The lock system prevents both trigger AND value mutations - clarify in documentation
- Consider showing lock count on screen (e.g., "7/16 steps locked")
