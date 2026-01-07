# MIDI Thru Machine - User Stories

This directory contains detailed user stories for the MIDI Thru Machine project, organized into implementation phases.

## Quick Links

- **[Phase 1 Overview](PHASE1-OVERVIEW.md)** - Complete implementation plan
- **[Phase 2 Stories](PHASE2-OVERVIEW.md)** - Future: Build songs (not yet written)
- **[Phase 3 Stories](PHASE3-OVERVIEW.md)** - Future: Generative intelligence (not yet written)

## Phase 1: "Capture & Morph" Stories

**Goal**: Enable live playing → algorithmic transformation loop

| ID | Story | Priority | Effort | Status |
|---|---|---|---|---|
| [P1-S00](P1-S00-always-on-buffer.md) | Always-On Buffer Recording | CRITICAL | Large (4-5d) | 📝 Not Started |
| [P1-S01](P1-S01-grid-visualization.md) | Grid Visualization | CRITICAL | Medium (2-3d) | 📝 Not Started |
| [P1-S02](P1-S02-grid-control.md) | Grid Control of Triggers | CRITICAL | Small (1-2d) | 📝 Not Started |
| [P1-S03](P1-S03-encoder-mutation-control.md) | Encoder Mutation Control | HIGH | Small (1-2d) | 📝 Not Started |
| [P1-S04](P1-S04-lock-visualization.md) | Lock Visualization | HIGH | Small (1-2d) | 📝 Not Started |
| [P1-S05](P1-S05-grid-lock-control.md) | Grid Lock Control | HIGH | Small-Med (2d) | 📝 Not Started |
| [P1-S06](P1-S06-buffer-to-bitwise.md) | Buffer → Bitwise Conversion | CRITICAL | Med-Large (3-4d) | 📝 Not Started |
| [P1-S07](P1-S07-scale-aware-mutation.md) | Scale-Aware Mutation | HIGH | Medium (2-3d) | 📝 Not Started |

**Total Estimated Effort**: 19-23 days (4-5 weeks)

## User Story Template

Each story uses the following structure:

```markdown
# User Story: [ID] - [Title]

## Story
**As a** [role]
**I want to** [action]
**So that** [benefit]

## Details
- Current State
- Proposed Solution
- Technical Considerations
- Acceptance Criteria

## Dependencies
## Blockers
## Estimated Effort
## Priority
## Related Stories
## Notes
```

## How to Use These Stories

### For Implementation
1. Read the Phase 1 Overview first
2. Work through stories in order (respect dependencies)
3. Mark stories as "In Progress" → "Done" as you work
4. Update blockers if you discover new issues
5. Reference story ID in commit messages

### For Planning
- Use effort estimates for sprint planning
- Check dependencies before starting a story
- Review blockers weekly
- Adjust priorities based on feedback

### For Review
- Each story has clear acceptance criteria
- Test against these criteria before marking done
- Get user feedback at story completion (especially UX stories)

## Implementation Order

### Week 1: Foundation (P1-S00)
Start here. Everything else depends on buffer recording working correctly.

### Week 2: Visibility (P1-S01, P1-S02, P1-S03)  
Make bitwise visible and controllable. Test with users early.

### Week 3: Locking & Integration (P1-S04, P1-S05, P1-S06)
Complete the capture → morph pipeline.

### Week 4: Musical Intelligence (P1-S07)
Make it sound good. Polish and ship.

## Status Legend

- 📝 **Not Started** - Story not yet begun
- 🚧 **In Progress** - Currently being worked on
- ✅ **Done** - Acceptance criteria met, tested
- ⏸️ **Blocked** - Waiting on dependency or decision
- ❌ **Cancelled** - Decided not to implement

## Contributing

When adding new stories:
1. Use the template above
2. Add to this index with ID, title, priority, effort
3. Link to related stories
4. Update dependency graphs
5. Get approval before starting implementation

## Questions?

See `docs/components_overview.md` for architecture details, or the main README for project context.

---

*Last Updated: 2026-01-07*  
*Phase: 1 (Capture & Morph)*  
*Status: Planning Complete, Implementation Not Started*
