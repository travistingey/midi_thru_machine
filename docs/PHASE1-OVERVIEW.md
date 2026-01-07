# Phase 1: "Capture & Morph" - Implementation Overview

## Vision
**Create a system where you can play freely, capture your performance, and watch it morph algorithmically while maintaining musical coherence.**

## User Experience Flow
1. Sit down at keyboard, start playing → **Always recording** (P1-S00)
2. Play something you like → Press "Freeze" → **Buffer captured**
3. Press "To Bitwise" → **Sequence becomes algorithmic** (P1-S06)
4. **See it on grid** → Understand what's happening (P1-S01)
5. **Adjust mutation** → Control how much it morphs (P1-S03)
6. **Lock key phrases** → Protect what you want to keep (P1-S04, P1-S05)
7. **Change keys** → Everything stays musical (P1-S07)
8. **Perform** → Toggle triggers live (P1-S02)

## Success Criteria
You can improvise → capture → morph → perform, all without leaving flow state.

## User Stories (Priority Order)

### Foundation
- **P1-S00**: Always-On Buffer Recording System ⚠️ BLOCKING ALL OTHERS
  - Continuous 64-bar circular buffer
  - Instant freeze/swap mechanism
  - No dropped notes, efficient storage

### Visibility & Control
- **P1-S01**: Grid Visualization of Bitwise Triggers
  - See what the algorithm is doing
  - Real-time updates, clear on/off states
  
- **P1-S02**: Grid Control of Bitwise Triggers  
  - Tap to toggle triggers
  - Immediate feedback, performable

- **P1-S03**: Encoder Control of Mutation Chance
  - Dial in morph amount (0-100%)
  - Live control during performance

### Locking System
- **P1-S04**: Lock Visualization on Grid
  - Distinguish locked vs unlocked steps
  - Color-coded, intuitive

- **P1-S05**: Grid Lock Control
  - Hold K2 + tap step to lock/unlock
  - Protect phrases from mutation

### Integration
- **P1-S06**: Freeze Buffer into Bitwise Sequence
  - Convert recording → algorithmic seed
  - Preserves timing and note values
  - Auto-locks captured notes

- **P1-S07**: Scale-Aware Bitwise Mutation
  - Mutations respect active scale
  - Stay in key while morphing
  - Works with all follow modes

## Implementation Order

### Week 1: Foundation
**Goal**: Get buffer recording rock-solid
- Day 1-2: Investigate current `auto.lua` implementation
- Day 3-4: Implement double-buffer architecture
- Day 5: Integration testing, freeze mechanism

**Deliverable**: Always-on recording with instant freeze

### Week 2: Visualization
**Goal**: Make bitwise visible and controllable
- Day 1-2: P1-S01 Grid visualization
- Day 2-3: P1-S02 Grid control  
- Day 4: P1-S03 Encoder control
- Day 5: Polish and testing

**Deliverable**: Bitwise is visible and performable

### Week 3: Locking & Integration
**Goal**: Complete the capture → morph pipeline
- Day 1-2: P1-S04 Lock visualization
- Day 2-3: P1-S05 Lock control
- Day 3-4: P1-S06 Buffer → Bitwise conversion
- Day 5: Integration testing

**Deliverable**: Can capture performances and protect key phrases

### Week 4: Musical Intelligence
**Goal**: Make it sound musical
- Day 1-3: P1-S07 Scale-aware mutation
- Day 4: End-to-end testing
- Day 5: Performance optimization, bug fixes

**Deliverable**: Phase 1 complete - ship it!

## Dependencies Graph
```
P1-S00 (Buffer)
    â†"
P1-S06 (Buffer→Bitwise) ← Requires buffer data
    â†"
P1-S01 (Visualization) ← Needs bitwise to display
    â†"
â"œâ"€â"€ P1-S02 (Grid Control)
â"‚   
â"œâ"€â"€ P1-S04 (Lock Viz)
â"‚       â†"
â"‚   P1-S05 (Lock Control)
â"‚
└── P1-S03 (Encoder)
    
P1-S07 (Scale Aware) ← Integrates with everything above
```

## Risk Assessment

### High Risk
- **P1-S00**: Buffer architecture is complex, must be efficient
  - *Mitigation*: Profile early, optimize data structures
- **P1-S06**: Buffer→Bitwise conversion requires understanding auto.lua
  - *Mitigation*: Investigation phase before implementation

### Medium Risk  
- **P1-S07**: Scale quantization integration could impact performance
  - *Mitigation*: Profile per-step quantization cost
- **P1-S02**: Grid input handling might conflict with other modes
  - *Mitigation*: Clear mode separation, testing

### Low Risk
- **P1-S01, P1-S03, P1-S04, P1-S05**: Mostly UI work, well-understood

## Testing Strategy

### Unit Tests
- Buffer circular logic (wrap-around, pruning)
- Bitwise mutation with locks
- Scale quantization accuracy

### Integration Tests  
- Buffer → Bitwise conversion accuracy
- Grid visualization updates correctly
- Lock state persists across operations

### Performance Tests
- Buffer recording at high MIDI input rates
- Grid refresh rate with bitwise visualization  
- Scale quantization per-step overhead

### User Acceptance Tests
- Can you play → freeze → morph without thinking?
- Does mutation sound musical?
- Is grid feedback clear and immediate?

## What We're NOT Building (Phase 1)

❌ Clip launching (Phase 2)  
❌ Multiple clips per track (Phase 2)  
❌ Clip arrangement view (Phase 2)  
❌ Markov chain generation (Phase 3)  
❌ MIDI effects/stutters (Maybe never)  
❌ Complex sequencer UI (Phase 2)  
❌ Save/load clips (Phase 2)

**Stay focused. Ship Phase 1. Get feedback. Then decide on Phase 2.**

## Success Metrics

### Technical
- [ ] Buffer records continuously for 1+ hour without issues
- [ ] Freeze operation < 10ms latency
- [ ] Grid updates at 30+ fps
- [ ] No dropped MIDI notes during any operation
- [ ] Memory usage stable over long sessions

### User Experience
- [ ] Can capture idea within 1 second (press freeze)
- [ ] Can understand bitwise state within 3 seconds (grid viz)
- [ ] Can control mutation within 5 seconds (encoder)
- [ ] Mutations sound musical 90%+ of the time
- [ ] Users report "flow state" experience

### Market Validation
- [ ] Users say "I've never seen this before"
- [ ] Users create music in first 10 minutes
- [ ] Users request Phase 2 features (validates direction)
- [ ] No major "this doesn't work" complaints

## Next Steps

1. **Read these user stories carefully**
2. **Investigate `auto.lua` current implementation** (critical for P1-S00, P1-S06)
3. **Start with P1-S00** (blocking everything else)
4. **Build iteratively** (don't skip stories)
5. **Test constantly** (don't accumulate bugs)
6. **Ship Phase 1** (resist feature creep)

---

*Remember: The goal is "play → freeze → morph → perform" in flow state. Every feature should serve this core experience.*
