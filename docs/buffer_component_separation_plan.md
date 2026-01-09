# Buffer Component Separation Plan

## Executive Summary

This plan outlines the separation of buffer recording/playback functionality from the `auto` component into a dedicated `buffer` track component. This separation establishes clear boundaries: **Buffer = Recording/Playback**, **Auto = Automation**. The components will operate independently with their own tick counters and loop endpoints, enabling future expansion for quantization, clip storage, and clip launching.

## Reasoning

### 1. Separation of Concerns
- **Current State**: Auto component handles both automation (presets, scales, CC) and buffer recording/playback (~200 lines of buffer code mixed with automation)
- **Target State**: Clear separation where each component has a single, well-defined responsibility
- **Benefit**: Easier to understand, maintain, and extend each component independently

### 2. Independent State Management
- **Current State**: Buffer shares `auto.tick`, `auto.seq_start`, `auto.seq_length` with automation
- **Target State**: Buffer has its own `buffer.tick`, `buffer.seq_start`, `buffer.seq_length`
- **Benefit**: Components can operate independently without synchronization concerns
- **Benefit**: Enables different loop boundaries for recording vs automation

### 3. Future Expansion Path
- **Buffer Component**: Will handle quantization and clip storage/management
- **Auto Component**: Will handle launching clips and modified settings
- **Benefit**: Clear extension points for new features without cross-component complexity

### 4. Component Architecture Consistency
- **Pattern**: Matches existing track component structure (input, output, seq, scale, mute)
- **Pattern**: Components handle their own state; track holds shared state
- **Benefit**: Consistent architecture makes the codebase more predictable and maintainable

### 5. Modular Component Chain
- **Current**: Components are chained via `build_chain()` but buffer is embedded in auto
- **Target**: Buffer becomes a first-class component in the chain
- **Benefit**: Enables future component reordering and modular configurations

## Architecture Principles

### Component State Management
- **Component-Owned State**: Each component manages its own internal state
  - Buffer: `tick`, `seq_start`, `seq_length`, `buffer_write`, `buffer_read`, scrub state
  - Auto: `tick`, `seq_start`, `seq_length`, `seq`, `active_ccs`
- **Track-Owned State**: Shared state accessed by multiple components lives on track
  - `track.armed` (used by buffer for recording, auto for automation)
  - `track.output_device` (used by buffer for playback, auto for CC output)
  - `track.mute_input` (used by buffer for playback muting, input for processing)

### Component Communication
- **Events**: Components communicate via track's event system (`track:emit()`, `track:on()`)
- **Direct Access**: Components can access track properties (`self.track.armed`)
- **No Direct Component Access**: Components don't directly access other components

### Component Chain
- Components are processed in order via `build_chain()`
- Each component implements `transport_event()` and/or `midi_event()`
- Components return data to pass through the chain

## Execution Steps

### Phase 1: Create Buffer Component Structure

#### Step 1.1: Create `src/lib/components/track/buffer.lua`
- Create new Buffer component following TrackComponent pattern
- Copy buffer-specific state from Auto:
  - `buffer_write`, `buffer_read`
  - `buffer_step_length`
  - `buffer_playback`
  - `overwrite_cleared_steps`
  - `last_step_index`
  - Scrub mode state (`scrub_mode`, `scrub_tick`, `scrub_start`, `scrub_end`, `scrub_loop`, `scrub_length`)
- Add independent timing state:
  - `tick` (buffer's own playback position)
  - `seq_start` (buffer's loop start)
  - `seq_length` (buffer's loop length)
  - `playing` (buffer's playback state)

#### Step 1.2: Implement Buffer Component Methods
- `Buffer:set(o)` - Initialize buffer state
- `Buffer:transport_event(data)` - Handle buffer's own transport events
- `Buffer:record_buffer(midi_event)` - Record MIDI events to buffer
- `Buffer:run_buffer(events)` - Playback buffer events
- `Buffer:clear_buffer()` - Clear both write and read buffers
- `Buffer:set_loop(loop_start, loop_end)` - Set buffer loop boundaries
- `Buffer:start_scrub()`, `Buffer:update_scrub()`, `Buffer:stop_scrub()` - Scrub mode
- `Buffer:kill_notes()` - Kill active buffer notes
- Helper methods: `tick_to_step_index()`, `step_index_to_tick_range()`, `swap_buffer_step()`, etc.

#### Step 1.3: Register Buffer Component in Track
- Add `Buffer` require in `track.lua`
- Add `self.load_component(o, Buffer)` in `Track:new()`
- Add buffer to component chain in `build_chain()` (position TBD based on desired processing order)

### Phase 2: Migrate Buffer Functionality from Auto

#### Step 2.1: Remove Buffer State from Auto
- Remove from `Auto:set()`:
  - `buffer_write`, `buffer_read`
  - `buffer_step_length`
  - `buffer_playback`
  - `buffer_length` (if not needed)
  - `overwrite_cleared_steps`
  - `last_step_index`
  - Scrub mode state
- Keep in Auto:
  - `tick`, `seq_start`, `seq_length` (for automation)
  - `seq` (automation data)
  - `active_ccs` (CC automation)

#### Step 2.2: Remove Buffer Methods from Auto
- Remove `record_buffer()`
- Remove `run_buffer()`
- Remove `clear_buffer()`, `clear_buffer_tick()`, `clear_buffer_step()`
- Remove `swap_buffer_step()`
- Remove `start_scrub()`, `update_scrub()`, `stop_scrub()`
- Remove `kill_notes()` (or move to track if shared)
- Remove buffer helper methods
- Keep automation methods: `run_preset()`, `run_scale()`, `run_cc()`, `update_cc()`

#### Step 2.3: Simplify Auto Transport Event
- Remove buffer-specific logic from `Auto:transport_event()`
- Remove buffer step swapping logic
- Remove buffer overwrite clearing logic
- Remove buffer playback calls
- Keep automation event handling
- Auto's `transport_event()` becomes focused on automation only

### Phase 3: Update Track Integration

#### Step 3.1: Update Track Event Handlers
- Update `track:on('record_buffer')` to call `buffer:record_buffer()` instead of `auto:record_buffer()`
- Ensure buffer receives transport events via component chain
- Update armed state handling to work with buffer component

#### Step 3.2: Update Track Parameters
- Move `track_X_buffer_playback` parameter handling to Buffer component
- Update parameter registration to set buffer state
- Ensure backward compatibility with existing presets

#### Step 3.3: Update Component Chain
- Add Buffer to chain in appropriate position
- Consider: Should buffer process before or after auto?
  - **Before Auto**: Buffer records input, auto processes automation
  - **After Auto**: Auto processes automation, buffer records/plays
  - **Recommendation**: After Auto (buffer is recording/playback, automation affects processing)

### Phase 4: Update Mode Components

#### Step 4.1: Update BufferSeq Component
- Change `get_component()` to return `buffer` instead of `auto`
- Update all references from `auto.buffer_*` to `buffer.*`
- Update loop setting: `buffer:set_loop()` (optionally sync to auto if desired)
- Update scrub methods to use `buffer:start_scrub()`, etc.
- Update grid visualization to use `buffer.tick`, `buffer.seq_start`, `buffer.seq_length`

#### Step 4.2: Update BufferDefault Component
- Update menu items to access `track.buffer` instead of `track.auto.buffer_*`
- Update clear buffer action to call `buffer:clear_buffer()`
- Update playback status to read from `buffer.buffer_playback`

#### Step 4.3: Update Other Mode Components
- Search for any references to `auto.buffer_*` or buffer methods on auto
- Update to use `buffer` component instead

### Phase 5: Handle Loop Boundary Synchronization (Optional)

#### Step 5.1: Decide on Sync Strategy
- **Option A**: Always sync (when user sets loop in bufferseq, set both)
- **Option B**: Never sync (completely independent)
- **Option C**: Configurable sync (parameter to control sync behavior)
- **Recommendation**: Option A for initial implementation (explicit sync in bufferseq)

#### Step 5.2: Implement Sync (if Option A)
- In `BufferSeq:set_loop()`, after calling `buffer:set_loop()`, also call `auto:set_loop()`
- This keeps them aligned by default but allows independent operation

### Phase 6: Backward Compatibility & Migration

#### Step 6.1: Handle Existing Presets
- Add migration logic to convert old `auto.buffer_*` state to `buffer.*` state
- Handle migration of buffer data from `auto.seq[tick].buffer` to `buffer.buffer_write`
- Ensure existing presets load correctly

#### Step 6.2: Handle Existing Buffer Data
- In `Buffer:set()`, check for legacy buffer data in `o.seq`
- Migrate `seq[tick].buffer` entries to `buffer_write` and `buffer_read`
- Clear legacy data after migration

### Phase 7: Testing & Validation

#### Step 7.1: Functional Testing
- Test buffer recording with track armed
- Test buffer playback with `buffer_playback` enabled
- Test overwrite vs overdub modes
- Test scrub mode (single pad, multi-pad)
- Test loop boundary handling
- Test one-shot vs loop recording

#### Step 7.2: Integration Testing
- Test buffer + auto working independently
- Test loop boundary sync (if implemented)
- Test transport events through component chain
- Test mode components (bufferseq, bufferdefault)

#### Step 7.3: Edge Case Testing
- Test buffer with different loop boundaries than auto
- Test scrub mode with different loop boundaries
- Test buffer clearing during playback
- Test rapid arm/disarm cycles

## Future Expansion Points

### Buffer Component Extensions
- **Quantization**: Add `Buffer:quantize()` method to quantize recorded events
- **Clip Storage**: Add `Buffer:save_clip(name, start_tick, end_tick)` method
- **Clip Loading**: Add `Buffer:load_clip(name)` method
- **Clip Management**: Add clip library and clip selection methods

### Auto Component Extensions
- **Clip Launching**: Add `Auto:launch_clip(clip_name)` method
- **Modified Settings**: Add methods to apply settings when launching clips
- **Clip Triggers**: Add automation events to trigger clip launches

### Component Communication
- **Events**: Use track events for clip launch requests (`track:emit('launch_clip', clip_name)`)
- **State Sharing**: Use track properties for shared clip state if needed

## Component Chain Order

### Recommended Order
```
Input → Auto → Buffer → Scale → Mute → Output
```

**Rationale**:
1. **Input**: First in chain, receives raw MIDI
2. **Auto**: Processes automation (presets, scales, CC) - affects downstream processing
3. **Buffer**: Records input and plays back recorded events - needs processed input
4. **Scale**: Applies scale transformations
5. **Mute**: Applies mute logic
6. **Output**: Final output stage

**Alternative Consideration**: Buffer could be before Auto if we want to record pre-automation input, but current behavior suggests recording happens after automation processing.

## File Changes Summary

### New Files
- `src/lib/components/track/buffer.lua` (~400-500 lines)

### Modified Files
- `src/lib/components/track/auto.lua` (remove ~200 lines of buffer code)
- `src/lib/components/app/track.lua` (add buffer component, update event handlers)
- `src/lib/components/mode/bufferseq.lua` (update to use buffer component)
- `src/lib/components/mode/bufferdefault.lua` (update to use buffer component)
- Any other mode components that reference buffer functionality

### Migration Considerations
- Preset files may need migration
- Existing buffer data needs migration path
- Parameter names may need backward compatibility layer

## Success Criteria

1. ✅ Buffer component is fully independent with own tick/loop state
2. ✅ Auto component only handles automation (no buffer code)
3. ✅ All buffer functionality works as before
4. ✅ Mode components (bufferseq, bufferdefault) work correctly
5. ✅ Existing presets load and work correctly
6. ✅ Component chain processes correctly
7. ✅ No performance regressions
8. ✅ Code is cleaner and more maintainable

## Risks & Mitigations

### Risk 1: Breaking Existing Functionality
- **Mitigation**: Comprehensive testing, migration path for existing data
- **Mitigation**: Incremental migration with feature flags if needed

### Risk 2: Performance Impact
- **Mitigation**: Minimal - just moving code, not adding complexity
- **Mitigation**: Profile before/after if concerns arise

### Risk 3: State Synchronization Issues
- **Mitigation**: Independent state eliminates sync issues
- **Mitigation**: Clear documentation of when sync happens (if at all)

### Risk 4: Component Chain Order Issues
- **Mitigation**: Test different orders, document rationale
- **Mitigation**: Make chain order configurable if needed

## Timeline Estimate

- **Phase 1**: 2-3 hours (create buffer component structure)
- **Phase 2**: 2-3 hours (migrate functionality from auto)
- **Phase 3**: 1-2 hours (update track integration)
- **Phase 4**: 2-3 hours (update mode components)
- **Phase 5**: 1 hour (loop sync if needed)
- **Phase 6**: 2-3 hours (backward compatibility)
- **Phase 7**: 3-4 hours (testing)

**Total**: ~13-19 hours of focused development time

## Next Steps After Separation

1. Implement quantization in Buffer component
2. Implement clip storage/loading in Buffer component
3. Implement clip launching in Auto component
4. Add clip management UI in mode components
5. Add clip visualization in grid components

