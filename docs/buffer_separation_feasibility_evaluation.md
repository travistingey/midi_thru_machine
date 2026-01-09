# Buffer Recording and Autosave Separation - Feasibility Evaluation

**Evaluation Date:** 2026-01-09
**Branch:** claude/evaluate-buffer-autosave-separation-6iaQg
**Evaluator:** Claude (AI Assistant)

## Executive Summary

After analyzing the current codebase against the separation plans in the `ai` branch, I've identified a **critical mismatch** between the plans and actual implementation:

- **The plans assume** buffer recording exists in the `Auto` component
- **The reality is** buffer recording is implemented in the `Seq` component
- **Result:** The plans need significant revision to align with current architecture

**Overall Feasibility:** ⚠️ **MODERATE with Major Revisions Required**

---

## Current Implementation Analysis

### 1. Auto Component (`src/lib/components/track/auto.lua`)

**Current Responsibilities:**
- Preset automation (track presets)
- Scale automation
- CC automation with Bezier curves
- Transport event handling (tick tracking)

**Buffer-Related Code:** ❌ **NONE**

**Key Findings:**
- Uses `self.step` (not `self.tick`) for position tracking
- Uses `self.seq` table for automation data
- Has NO buffer recording/playback functionality
- Already focused on automation only

**Code Size:** ~265 lines

### 2. Seq Component (`src/lib/components/track/seq.lua`)

**Current Responsibilities:**
- ✅ Buffer recording (`buffer` table)
- ✅ Playback buffer (`playback_buffer` table)
- ✅ Clip management system (`clips` library)
- ✅ Record with timing offset tracking
- ✅ Loop boundary handling (`playback_start`, `playback_end`)
- ✅ Clip save/load with non-blocking chunked copy

**Code Size:** ~233 lines

**Key Implementation Details:**

```lua
-- Recording buffer (circular history)
self.buffer = {}
self.buffer_length = App.ppqn * 124  -- ~124 bars

-- Playback buffer (what's being played)
self.playback_buffer = {}
self.playback_length = App.ppqn * 4  -- 4 bars default
self.playback_start = 0
self.playback_end = self.playback_length
self.playback_loop = true

-- In-memory clip library
self.clips = {}
```

**Recording Mechanism:**
```lua
function Seq:record(data)
    if App.playing then
        local step = App.tick % self.buffer_length
        local dt = os.clock() - self.last_tick
        local offset = (dt / tick_len) - 1  -- Sub-tick timing!

        if not self.buffer[step] then
            self.buffer[step] = {}
        end
        table.insert(self.buffer[step], {data = data, off = offset})
    end
end
```

**Playback Mechanism:**
```lua
function Seq:run(step)
    local events = self.playback_buffer[step]
    if not events then return end

    for _, ev in ipairs(events) do
        if ev.off ~= 0 then
            -- Async playback with timing offset
            clock.run(function()
                clock.sleep(ev.off * tick_len)
                self.track:send(ev.data)
            end)
        else
            self.track:send(ev.data)
        end
    end
end
```

**Clip System:**
```lua
-- Non-blocking clip save with chunking
function Seq:save_clip(name, first_step, length, chunk)
    self.clips[name] = {}
    clock.run(function()
        for i = 0, length - 1 do
            local src = (first_step + i) % self.buffer_length
            if self.buffer[src] then
                dst[i + 1] = deep_copy(self.buffer[src])
            end
            if i % chunk == 0 then
                clock.sleep(0)  -- Yield to avoid audio dropouts
            end
        end
        self:emit("clip_saved", name, dst)
    end)
end
```

### 3. Track Component (`src/lib/components/app/track.lua`)

**Component Chain Architecture:**

```lua
function Track:build_chain()
    -- Main processing chain
    local chain = {
        self.auto,      -- Automation
        self.input,     -- Input processing
        self.seq,       -- Buffer/sequencer
        self.scale,     -- Scale processing
        self.mute,      -- Mute logic
        self.output     -- Output
    }

    self.process_transport = self:chain_components(chain, 'process_transport')
    self.process_midi = self:chain_components(chain, 'process_midi')
end
```

**Component Loading:**
```lua
-- In Track:new()
self.load_component(o, Auto)
self.load_component(o, Input)
self.load_component(o, Seq)
self.load_component(o, Mute)
self.load_component(o, Output)
```

**Key Finding:** Seq is already a separate component in the chain!

### 4. TrackComponent Base Class

**Architecture Pattern:**
- Components inherit from `TrackComponent`
- Implement `process_transport(data, track)` for transport events
- Implement `process_midi(data, track)` for MIDI events
- Use event system (`emit`, `on`, `off`) for communication
- Access parent track via `self.track`

---

## Plan vs. Reality Analysis

### Separation Plan (buffer_component_separation_plan.md)

**Plan's Core Premise:**
> "This plan outlines the separation of buffer recording/playback functionality from the `auto` component into a dedicated `buffer` track component."

**Reality Check:** ❌ **FUNDAMENTALLY INCORRECT**

Buffer functionality is NOT in Auto - it's in Seq!

**Plan's Architecture Goals:**
1. ✅ **Clear separation of concerns** - Already achieved (Auto = automation, Seq = buffer)
2. ✅ **Independent state management** - Already achieved (separate components)
3. ⚠️ **Future expansion path** - Partially achieved (clips exist, but limited features)
4. ✅ **Component architecture consistency** - Already achieved (Seq follows TrackComponent pattern)
5. ✅ **Modular component chain** - Already achieved (Seq in chain)

### Implementation Plan v2 (buffer_implementation_plan_v2.md)

**Plan Assumptions:**
- Buffer code is in `auto.lua` (~200 lines of buffer code)
- Need to refactor `auto.step` to `auto.tick`
- Need double buffer (read/write) system
- Need step-based buffer swapping
- Need play-through mode, scrub mode, alt lock, launch quantization

**Reality:**
- Buffer code is in `seq.lua` (~233 lines total, ~150 for buffer logic)
- Auto already uses `self.step` for automation position (correct naming)
- Seq uses single buffer + playback buffer (different from proposed double buffer)
- No scrub mode, play-through mode, or grid interaction yet
- No mode components (bufferseq, bufferdefault) exist

---

## Component Responsibilities Matrix

| Component | Current | Plan Assumes | Reality Gap |
|-----------|---------|--------------|-------------|
| **Auto** | Preset/Scale/CC automation | Buffer + Automation | ❌ No buffer code |
| **Seq** | Buffer recording/playback | Not mentioned | ✅ Already handles buffers |
| **Buffer** (proposed) | N/A | Recording/playback from Auto | ⚠️ Would duplicate Seq |
| **Track** | Component management | Same | ✅ Matches |
| **Mode Components** | None exist | bufferseq, bufferdefault | ❌ Need to create |

---

## Feasibility Assessment by Feature

### Phase 1: Foundation & Double Buffer

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| **Refactor tick/step terminology** | ✅ HIGH | Auto uses `step`, Seq uses `step` - both correct for context |
| **Double buffer (read/write)** | ⚠️ MEDIUM | Seq has buffer + playback_buffer (different model) |
| **Step-based swapping** | ⚠️ MEDIUM | Current model: async copy via `save_clip()` |
| **Freeze playback during scrub** | ❌ LOW | No scrub functionality exists yet |

**Recommendation:** Review if double buffer is needed. Current model works differently:
- `buffer` = continuous circular history (always recording)
- `playback_buffer` = active clip (what's being played)
- Transfer via `save_clip()` (non-blocking chunked copy)

### Phase 2: Play-Through Mode

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| **Scrub mode selection** | 🆕 NEW | No scrub system exists - build from scratch |
| **Long-press length setting** | 🆕 NEW | No grid interaction for buffer - build from scratch |
| **Momentary press (one-shot)** | 🆕 NEW | New feature |
| **Sustained hold** | 🆕 NEW | New feature |
| **Multi-pad loop** | 🆕 NEW | New feature |
| **Update length during playback** | 🆕 NEW | New feature |

**Recommendation:** These are entirely new features. Need to create:
1. BufferSeq mode component (grid interface)
2. BufferDefault mode component (screen/menu)
3. Scrub system in Seq component
4. Grid event handling

### Phase 3: Launch Quantization

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| **Launch quantization parameter** | ✅ HIGH | Easy to add to Track params |
| **Quantized launch logic** | ✅ HIGH | Standard timing calculation |

**Recommendation:** Straightforward implementation once scrub system exists.

### Phase 4: Alt Lock & UX Polish

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| **Scrub lock on alt tap** | ✅ HIGH | Once scrub exists, easy to add |
| **Unlock on pad press/alt** | ✅ HIGH | Standard mode component behavior |
| **Visual feedback** | ✅ HIGH | Grid LED patterns |

**Recommendation:** Standard mode component features, well-understood pattern.

### Phase 5: Persistence & Clip System

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| **Save/load buffer to file** | ✅ HIGH | `tab.save()` exists, pattern established |
| **Clip file format** | ✅ DONE | Already implemented in Seq! |
| **Save clip from loop points** | ⚠️ PARTIAL | `save_clip()` exists but no loop point UI |
| **Load clip to playback** | ✅ DONE | `load_clip()` already exists! |

**Recommendation:** Core clip system is done. Need:
1. UI for saving clips (mode component)
2. UI for loading clips (mode component)
3. File persistence integration

---

## Critical Architecture Questions

### 1. Should Buffer Be Separated from Seq?

**Current State:**
- Seq handles buffer recording + playback + clips
- Works as designed, follows component pattern
- Already separate from Auto

**Plan's Goal:**
- Create new Buffer component
- Separate from Auto (which doesn't have buffer code)

**Analysis:**
- ❌ Plan's premise is incorrect (buffer not in Auto)
- ❓ Is Seq doing too much? (buffer + playback + clips)
- ✅ Seq is already modular and separate

**Recommendation:**
**DO NOT create separate Buffer component.** Instead:
1. Enhance Seq with planned features (scrub, quantization)
2. Create mode components (BufferSeq, BufferDefault) for UI
3. Consider renaming Seq to Buffer if name better reflects purpose

### 2. What About the Double Buffer System?

**Plan's Model:**
```
buffer_write (recording target)
buffer_read (playback source)
swap on step boundaries
```

**Current Model:**
```
buffer (circular history, always recording)
playback_buffer (active clip)
save_clip() copies segments from buffer to clips
load_clip() swaps playback_buffer
```

**Analysis:**
- Current model is more sophisticated
- Supports multiple saved clips
- Non-blocking copy prevents audio dropouts
- Can record while playing different clip

**Recommendation:**
**Keep current model**, enhance with:
1. Auto-swap option (copy buffer → playback at loop end)
2. Overdub mode (merge new recording into playback)
3. Scrub from buffer OR playback_buffer

### 3. What About Terminology (Tick vs Step)?

**Plan Says:**
> "Refactor auto.step to auto.tick for clarity"

**Current Reality:**
- Auto uses `self.step` for automation position ✅ CORRECT
- Seq uses `self.step` for playback position ✅ CORRECT
- App uses `self.tick` for global transport ✅ CORRECT

**Analysis:**
- Terminology is already correct
- `step` = component's local position
- `tick` = global transport position
- No confusion in practice

**Recommendation:**
**NO REFACTORING NEEDED.** Current naming is semantically correct.

---

## Revised Implementation Strategy

### Phase 1: Create Mode Components (NEW)
**Priority:** 🔴 CRITICAL - Foundation for all features

1. **Create BufferSeq Mode Component**
   - Grid visualization of buffer content
   - Pad interaction for scrub/playback
   - Loop point setting
   - Step length adjustment
   - **Files:** `src/lib/components/mode/bufferseq.lua`

2. **Create BufferDefault Mode Component**
   - Screen display of buffer state
   - Menu for buffer parameters
   - Playback status
   - **Files:** `src/lib/components/mode/bufferdefault.lua`

3. **Create Session Mode for Buffer**
   - Integrate BufferSeq + BufferDefault
   - **Files:** `src/lib/modes/session-buffer.lua`

**Estimated Effort:** 2-3 days

### Phase 2: Enhance Seq with Scrub System
**Priority:** 🟡 HIGH - Core feature

1. **Add Scrub State to Seq**
   ```lua
   self.scrub_mode = false
   self.scrub_start = 0
   self.scrub_end = 0
   self.scrub_loop = false
   self.scrub_playback_buffer = {}
   ```

2. **Implement Scrub Methods**
   - `Seq:start_scrub(start_tick, end_tick, loop)`
   - `Seq:stop_scrub()`
   - `Seq:update_scrub(start_tick, end_tick)`

3. **Scrub Playback Logic**
   - Extract segment from buffer
   - Copy to scrub_playback_buffer
   - Switch playback source during scrub

**Estimated Effort:** 1-2 days

### Phase 3: Play-Through & Launch Quantization
**Priority:** 🟡 HIGH - UX enhancement

1. **Implement in BufferSeq**
   - Long-press length setting
   - Momentary vs sustained playback
   - Multi-pad loop
   - Alt lock

2. **Add Launch Quantization**
   - Track parameter
   - Calculate launch tick
   - Delay scrub start

**Estimated Effort:** 2-3 days

### Phase 4: Auto-Swap & Overdub
**Priority:** 🟢 MEDIUM - Nice to have

1. **Auto-swap at Loop End**
   ```lua
   -- In Seq:transport_event()
   if next_step >= self.playback_start + self.playback_length then
       if self.auto_swap then
           self:swap_buffers()
       end
   end
   ```

2. **Overdub Mode**
   - Merge recorded events into playback_buffer
   - Keep both old and new notes

**Estimated Effort:** 1 day

### Phase 5: Clip Management UI
**Priority:** 🟢 MEDIUM - Polish

1. **Save Clip UI** (in BufferSeq or BufferDefault)
   - Name entry
   - Save from loop points
   - Visual confirmation

2. **Load Clip UI**
   - Clip browser
   - Preview
   - Load to playback

**Estimated Effort:** 2 days

---

## Risk Assessment

### High Risk ⚠️

1. **Plan Alignment**
   - **Risk:** Plans assume incorrect architecture
   - **Impact:** Wasted effort if followed literally
   - **Mitigation:** Update plans before implementation

2. **Feature Creep**
   - **Risk:** Plans are very ambitious (19 hours estimated, likely 40+ hours)
   - **Impact:** Project may never complete
   - **Mitigation:** Prioritize ruthlessly, MVP first

### Medium Risk ⚠️

3. **Performance**
   - **Risk:** Grid updates, buffer copies, scrub playback may cause audio dropouts
   - **Impact:** Unusable if audio glitches
   - **Mitigation:** Use existing non-blocking patterns (see `save_clip()`)

4. **Backward Compatibility**
   - **Risk:** Changing Seq may break existing functionality
   - **Impact:** Regression in working features
   - **Mitigation:** Add features, don't change existing behavior

### Low Risk ✅

5. **Component Integration**
   - **Risk:** New mode components may not integrate cleanly
   - **Impact:** UI/workflow issues
   - **Mitigation:** Follow existing mode component patterns (PresetSeq, PresetGrid)

---

## Technical Debt & Code Quality

### Existing Strengths ✅

1. **Clean Component Architecture**
   - Well-defined TrackComponent base class
   - Clear separation of concerns (Auto, Seq, Input, Output, etc.)
   - Event-driven communication

2. **Non-Blocking Patterns**
   - `save_clip()` uses coroutines and chunking
   - Prevents audio dropouts during long operations

3. **Sub-Tick Timing**
   - Recording captures timing offsets
   - Playback respects offsets (humanization)

### Areas for Improvement ⚠️

1. **Documentation**
   - Limited inline comments
   - No component interaction diagrams
   - Plans don't match reality

2. **Testing**
   - No visible test infrastructure
   - Complex timing logic needs tests

3. **Parameter Organization**
   - Track parameters in Track component (good)
   - Buffer parameters should be in Seq, but may be scattered

---

## Recommendations

### 🔴 CRITICAL - Do First

1. **Update Separation Plans**
   - Acknowledge buffer is in Seq, not Auto
   - Revise architecture diagrams
   - Update file change lists

2. **Define MVP Scope**
   - What's the minimum viable feature set?
   - What can be deferred to v2?
   - Recommendation: Mode components + basic scrub only

### 🟡 HIGH - Do Soon

3. **Create Architecture Diagram**
   - Current: Auto, Seq, Input, Output, Scale, Mute
   - Proposed: Same, but enhanced Seq + new mode components
   - Data flow between components

4. **Implement Mode Components**
   - Start with BufferSeq (grid interface)
   - Then BufferDefault (screen/menu)
   - Test integration before adding features

### 🟢 MEDIUM - Nice to Have

5. **Feature Implementation Priority**
   1. Basic scrub (loop between pads)
   2. Visual feedback (grid LEDs)
   3. Play-through mode
   4. Launch quantization
   5. Alt lock
   6. Auto-swap
   7. Clip management UI

6. **Documentation Updates**
   - Add inline comments to Seq component
   - Document buffer model (circular history + playback)
   - Create user guide for buffer workflow

---

## Conclusion

### Feasibility Summary

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Overall Feasibility** | ⚠️ MODERATE | Doable, but plans need major revision |
| **Technical Feasibility** | ✅ HIGH | Codebase is well-structured |
| **Architecture Fit** | ✅ EXCELLENT | Component system supports expansion |
| **Plan Accuracy** | ❌ POOR | Plans assume wrong architecture |
| **Scope Realism** | ⚠️ LOW | Too ambitious for stated timeline |

### Key Insights

1. **Buffer separation is ALREADY DONE** - Seq component exists and is separate from Auto
2. **Plans are fundamentally misaligned** - Based on incorrect understanding of current code
3. **Core clip system exists** - save_clip() and load_clip() are implemented
4. **Need mode components** - This is the missing piece, not separation
5. **Feature scope is large** - 19 hours estimated, likely 40+ hours actual

### Recommended Path Forward

**Option A: Minimal Viable Product (Recommended)**
- Focus: Create BufferSeq mode component with basic grid scrub
- Timeline: 1-2 weeks
- Risk: Low
- Value: Unlocks buffer interaction

**Option B: Full Feature Set**
- Focus: Implement all features in plans
- Timeline: 4-6 weeks
- Risk: High (feature creep, incomplete)
- Value: High if completed

**Option C: Incremental Enhancement**
- Focus: Add one feature category at a time
- Timeline: 2-4 weeks per phase
- Risk: Medium
- Value: Balanced, sustainable

### Final Verdict

✅ **PROCEED with revised plan:**
1. Update plans to reflect Seq-based architecture
2. Start with mode components (BufferSeq, BufferDefault)
3. Add scrub system to Seq
4. Implement features incrementally
5. Test thoroughly at each phase

❌ **DO NOT proceed** with plans as written:
- Incorrect architecture assumptions
- Would create unnecessary duplication
- High risk of failure

---

## Appendix: Current vs Planned Component Structure

### Current Architecture
```
Track
├── Auto (automation only)
├── Input (MIDI/Crow input)
├── Seq (buffer + playback + clips) ← BUFFER IS HERE
├── Scale (note transformation)
├── Mute (mute logic)
└── Output (MIDI/Crow output)
```

### Plan's Assumed Architecture (INCORRECT)
```
Track
├── Auto (automation + buffer) ← PLANS THINK BUFFER IS HERE
├── Input
├── Scale
├── Mute
└── Output
```

### Plan's Proposed Architecture (UNNECESSARY)
```
Track
├── Auto (automation only)
├── Buffer (separated from Auto) ← WOULD DUPLICATE SEQ
├── Input
├── Scale
├── Mute
└── Output
```

### Recommended Architecture (ENHANCE EXISTING)
```
Track
├── Auto (automation)
├── Input
├── Seq (enhanced buffer + scrub + clips) ← ENHANCE THIS
├── Scale
├── Mute
└── Output

New Mode Components:
├── BufferSeq (grid interface) ← CREATE THIS
└── BufferDefault (screen/menu) ← CREATE THIS
```

---

**End of Evaluation**
