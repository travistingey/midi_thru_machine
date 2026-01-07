# User Story: P1-S05 - Grid Lock Control

## Story
**As a** performer  
**I want to** lock/unlock steps by holding a button and tapping the grid  
**So that** I can protect specific notes from mutation during performance

## Details

### Description
Implement a modifier-based grid interaction for toggling lock state. Users hold a designated button (e.g., shift/alt button on grid or Norns) and tap steps to lock/unlock them. Locked steps maintain their current value and trigger state even when mutation occurs.

### Current State
- Lock visualization exists (from P1-S04)
- Grid control of triggers exists (from P1-S02)
- No mechanism to change lock state via grid
- Users cannot protect specific steps during performance

### Proposed Solution
- **Modifier Button**: Designate a grid button or Norns key as "lock mode"
- **Interaction**: Hold modifier + tap step = toggle lock state
- **Visual Feedback**: Immediate LED update showing new lock state
- **Safety**: Prevent accidental unlocks (require deliberate hold+tap)

### Modifier Options
1. **Norns K2**: Use K2 as modifier (simple, no grid button consumed)
2. **Grid Row 8**: Dedicate bottom row to functions, one button for lock
3. **Double-tap**: Double-tap step to lock/unlock (no modifier needed)

**Recommendation**: Use Norns K2 as modifier for simplicity

### Technical Considerations
- Track modifier button state (pressed/released)
- Modify `Bitwise.lock[i]` array on modifier+tap
- Ensure lock toggle doesn't also toggle trigger (prevent dual-action)
- Consider edge case: What if user holds modifier while sequence plays?
- Must work smoothly with P1-S02 trigger control (same button, different mode)

### Interaction Flow
```
1. User holds K2 (modifier)
2. Grid enters "lock mode" (visual feedback?)
3. User taps step on grid
4. Step's lock state toggles: lock[i] = !lock[i]
5. LED updates to show new lock state (from P1-S04)
6. User releases K2
7. Grid returns to normal trigger mode
```

### Acceptance Criteria
- [ ] Holding modifier + tapping step toggles lock state
- [ ] Locked steps don't mutate values or triggers
- [ ] Visual feedback confirms lock state change immediately
- [ ] Trigger control still works when modifier not held
- [ ] Multiple locks can be toggled in quick succession
- [ ] Lock state persists across sequence loops
- [ ] Works during both playback and stopped states

## Dependencies
- P1-S02: Grid control (must not conflict with trigger toggle)
- P1-S04: Lock visualization (provides visual feedback)
- Bitwise `lock[]` array
- Norns key input system or grid button mapping

## Blockers
- **Decision needed**: Which modifier button to use?
  - **K2 (Recommended)**: Accessible, doesn't consume grid space
  - **Grid button**: More "hands-on" but uses grid real estate
- **Decision needed**: Should there be visual indication that lock mode is active?
  - **Recommendation**: Flash/pulse locked steps while K2 held

## Estimated Effort
**Small-Medium** (2 days)
- Modifier button handling: 2-3 hours
- Lock toggle logic: 1-2 hours
- Integration with existing grid input: 3-4 hours
- Visual feedback for lock mode: 2-3 hours
- Testing interaction flows: 2-3 hours

## Priority
**High** - This is the "control" part of the lock system. Without this, users can see locks (P1-S04) but not change them.

## Related Stories
- P1-S02: Grid control (must coexist with this)
- P1-S04: Lock visualization (provides feedback for this)
- P1-S03: Encoder control (mutation chance works with locks)
- P1-S06: Buffer → Bitwise (will use locks to preserve captured notes)

## Notes
- Consider adding "lock all" / "unlock all" commands
- Future enhancement: "Lock pattern" (lock every other step, etc.)
- Future enhancement: Probability-based locks (90% locked = rare mutation)
- The `Bitwise:mutate(i)` method already checks `self.lock[i]` before mutating
- Consider Norns K3 for "unlock all" quick-clear function
- Test with rapid lock/unlock toggles to ensure responsiveness
