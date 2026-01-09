# Buffer Functionality Implementation Plan v2

**Updated:** Based on user clarifications regarding persistence, clip system, quantization, and play-through behavior.

## Executive Summary

This document outlines the finalized implementation plan for buffer recording and playback functionality in MIDI Thru Machine. Key decisions:

- **Per-track buffers only** (no global buffers initially)
- **Buffer clips saved as separate files** (future-proofing for clip system)
- **Launch quantization** parameter for scrub/clip launching
- **Play-through mode** with intuitive long-press length setting
- **Always-on recording deprioritized** (can default tracks to armed)
- **No buffer size limits initially** (test performance first)

## Current Implementation Analysis

### What's Working

#### Auto Component (auto.lua)
- ✅ Basic buffer recording to `seq[tick].buffer` structure
- ✅ Overwrite mode with step-based clearing (`clear_buffer_step`)
- ✅ Loop boundary handling and overwrite tracking
- ✅ Scrub playback system (`start_scrub`, `stop_scrub`, `update_scrub`)
- ✅ Buffer playback respecting `buffer_playback` and `mute_input_on_playback` params
- ✅ Smart note-off handling via `kill_notes()`

#### BufferSeq Component (bufferseq.lua)
- ✅ Grid visualization of buffer content
- ✅ Multi-pad selection for scrub range
- ✅ Dynamic scrub range recalculation from held pads
- ✅ Loop point setting via alt+long press (same as presetseq)
- ✅ Step length adjustment
- ✅ Visual feedback for scrub regions

#### Track Component (track.lua)
- ✅ Recording trigger when track is armed
- ✅ Recording disabled during scrub playback
- ✅ Overwrite vs overdub logic

#### Input Component (input.lua)
- ✅ Input muting when buffer playback is active (via `mute_input_on_playback`)

### Critical Gaps & Mismatches

#### 1. **Terminology Confusion: Steps vs Ticks**
**Current State:**
- Code uses "step" ambiguously - sometimes means a tick position, sometimes means a duration
- `auto.step` is the current tick position
- `buffer_step_length` is a duration in ticks

**User Requirement:**
> "we explicitly say 'tick' and let 'step' reflect a specific duration"

**Impact:** Confusion in code, harder to maintain

#### 2. **Play-Through Mode Missing**
**Current State:**
- Only loop mode exists (`App.buffer_scrub_loop` toggle)
- No distinction between momentary, hold, and long-press behaviors

**User Requirements:**
- Long-hold single pad: set length to 1 step
- Long-hold two pads: set length to span between pads
- While held: play through buffer respecting loop points
- Momentary press: play for defined length
- Length changes during playback should update immediately

**Impact:** Missing entire play-through interaction model

#### 3. **Alt Lock for Scrub Not Implemented**
**User Requirement:**
> "if the bufferseq has a pad held down and then taps the alt, it should lock the scrub playback"

**Current State:** Alt mode only used for loop point setting, no lock behavior

**Impact:** Can't sustain scrub without holding pads

#### 4. **Double Buffer Solution Not Addressed**
**User Requirement:**
> "Buffer should always be recording... but if we're playing back from the buffer and it loops back over the same steps during buffer playback, we dont want to overwrite or change whats being played"

**Current State:**
- Single buffer (`seq[tick].buffer`)
- Recording stops during buffer playback in overwrite mode

**Impact:** Can't record and playback simultaneously without conflicts

#### 5. **Launch Quantization Missing**
**User Requirement:**
> "track parameter for 'Launch Quantization' that would be used both for scrub playback and launching clips"

**Current State:** No quantization parameter for launches

**Impact:** Scrub launches can feel unrhythmic

#### 6. **Buffer/Clip Persistence System Missing**
**User Requirement:**
> "saving a buffer from the tool should use the built in feature that will write tables to a file... We will want to have the ability to save clips based on where the loop points in a buffer are set"

**Current State:** No clip saving/loading system

**Impact:** Can't save or reuse recorded material

## Architecture Decisions

### 1. Terminology Refactoring: Tick vs Step

**Definitions:**
- **tick**: Atomic time unit (1 tick = 1/24th of a quarter note at 24 PPQN). Position in time.
- **step**: A duration measured in ticks, defined by `buffer_step_length`
- **step_index**: Which step we're in (1-based for user display, 0-based internally)

**Refactoring:**
- Rename `auto.step` → `auto.tick` (current playback position)
- Keep `auto.buffer_step_length` (duration of one step in ticks)
- Add helper methods for conversions

**Helper Functions:**
```lua
-- Get current step index (0-based)
function Auto:get_current_step_index()
    return math.floor(self.tick / self.buffer_step_length)
end

-- Convert tick to step index
function Auto:tick_to_step_index(tick)
    return math.floor(tick / self.buffer_step_length)
end

-- Convert step index to tick range (inclusive)
function Auto:step_index_to_tick_range(step_index)
    local start_tick = step_index * self.buffer_step_length
    local end_tick = start_tick + self.buffer_step_length - 1
    return start_tick, end_tick
end

-- Convert step index to start tick
function Auto:step_index_to_start_tick(step_index)
    return step_index * self.buffer_step_length
end
```

### 2. Double Buffer Architecture

**Implementation: Read/Write Buffer Separation**

```lua
-- In auto.lua:set()
self.buffer_read = {}   -- Buffer being played back
self.buffer_write = {}  -- Buffer being recorded to
```

**Recording:**
- Always record to `buffer_write`
- Recording happens when track is armed (for now)
- Recording disabled during scrub mode

**Playback:**
- Always playback from `buffer_read`
- Respects `buffer_playback` parameter

**Buffer Swap:**
```lua
-- In auto:transport_event() at loop boundary
if next_tick >= self.seq_start + self.seq_length then
    if not self.scrub_mode then
        -- Swap: copy write buffer to read buffer
        self:swap_buffers()
    end
    -- ... existing loop boundary logic
end

function Auto:swap_buffers()
    -- Clear read buffer
    self.buffer_read = {}

    -- Copy write buffer to read buffer (shallow copy within loop range)
    for tick = self.seq_start, self.seq_start + self.seq_length - 1 do
        if self.buffer_write[tick] then
            self.buffer_read[tick] = self.buffer_write[tick]
        end
    end
end
```

**Benefits:**
- Recording never interferes with playback
- Scrub playback stays frozen while recording continues
- Clean separation of concerns

**Migration:**
- On load: if `seq[tick].buffer` exists, migrate to `buffer_write` and `buffer_read`

### 3. Launch Quantization

**New Track Parameter:**
```lua
-- In track.lua parameter registration
local quantize_options = {
    'off',      -- Launch immediately (next tick)
    'default',  -- Launch on next step boundary (bufferseq's step_length)
    '1/64',     -- 1.5 ticks (24ppqn / 16)
    '1/32',     -- 3 ticks
    '1/16',     -- 6 ticks
    '1/8',      -- 12 ticks
    '1/4',      -- 24 ticks
    '1/2',      -- 48 ticks
    '1/1',      -- 96 ticks (whole note)
}

Registry.add('add_option', track .. 'launch_quantize', 'Launch Quantize', quantize_options)
```

**Usage:**
- When scrub starts, calculate next quantized tick
- Delay scrub start until that tick
- "default" uses current `buffer_step_length` from bufferseq
- "off" launches on next tick (immediate)

**Implementation:**
```lua
function Auto:calculate_launch_tick(requested_tick, quantize_setting, step_length)
    if quantize_setting == 'off' then
        return self.tick + 1
    end

    local quantize_ticks
    if quantize_setting == 'default' then
        quantize_ticks = step_length
    else
        -- Parse note value and convert to ticks
        quantize_ticks = self:note_value_to_ticks(quantize_setting)
    end

    -- Calculate next boundary
    local ticks_since_seq_start = self.tick - self.seq_start
    local next_boundary = math.ceil(ticks_since_seq_start / quantize_ticks) * quantize_ticks
    return self.seq_start + next_boundary
end
```

### 4. Play-Through Mode State Machine

**Mode Selection:**
- `App.buffer_scrub_mode` = 'loop' | 'play_through'
- Stored globally, applies to all tracks

**Play-Through State:**
```lua
-- In bufferseq.lua
self.playthrough_length = nil -- nil = use buffer_step_length, or custom length in ticks
self.playthrough_mode = nil   -- nil, 'oneshot', 'sustained'
```

**Behavior Matrix:**

| Event | Pads Held | Action |
|-------|-----------|--------|
| pad_long | 1 pad | Set playthrough_length = 1 step |
| pad_long | 2+ pads | Set playthrough_length = span between earliest/latest |
| pad down | 1 pad (after long) | Play momentarily for playthrough_length |
| pad down | 1 pad (normal) | Play sustained from that point, respect auto loop points |
| pad down | 2+ pads | Play loop between pads |
| pad up | All released | Stop playback, return to normal |
| length change | During playback | Adjust scrub_end, jump back if needed |

**Key Implementation Points:**

1. **Long Press Length Setting (No Playback):**
```lua
function BufferSeq:handle_pad_long(data)
    local held_count = #data.pad_down + 1 -- +1 for current pad

    if held_count == 1 then
        -- Single pad long: set length to 1 step
        self.playthrough_length = self:get_step_length()
        print('Play-through length: 1 step (' .. self.playthrough_length .. ' ticks)')
    else
        -- Multiple pads long: set length to span
        local min_pad, max_pad = self:get_pad_range(data)
        local start_tick, _ = self:pad_to_tick_range(min_pad)
        local _, end_tick = self:pad_to_tick_range(max_pad)
        self.playthrough_length = end_tick - start_tick + 1
        print('Play-through length: ' .. self.playthrough_length .. ' ticks')
    end
end
```

2. **Pad Down Playback:**
```lua
function BufferSeq:handle_pad_down(pad_index, data)
    if App.buffer_scrub_mode ~= 'play_through' then return end

    local auto = self:get_component()
    local held_count = #data.pad_down + 1

    if held_count == 1 then
        -- Single pad: check if we should play momentarily or sustained
        if self.playthrough_length then
            -- Length was set by long press: play for that duration (oneshot)
            local start_tick, _ = self:pad_to_tick_range(pad_index)
            local end_tick = start_tick + self.playthrough_length - 1
            self:start_scrub_oneshot(start_tick, end_tick)
        else
            -- No length set: play sustained (until released)
            local start_tick, _ = self:pad_to_tick_range(pad_index)
            local end_tick = auto.seq_start + auto.seq_length - 1
            self:start_scrub_sustained(start_tick, end_tick)
        end
    else
        -- Multiple pads: loop between them
        local min_pad, max_pad = self:get_pad_range(data)
        local start_tick, _ = self:pad_to_tick_range(min_pad)
        local _, end_tick = self:pad_to_tick_range(max_pad)
        self:start_scrub_loop(start_tick, end_tick)
    end
end
```

3. **Length Update During Playback:**
```lua
function Auto:update_scrub_length(new_end_tick)
    if not self.scrub_mode then return end

    -- Update end point
    self.scrub_end = new_end_tick
    self.scrub_length = self.scrub_end - self.scrub_start + 1

    -- If current tick is now outside range, jump back to start
    if self.tick > new_end_tick then
        self:kill_notes()
        self.tick = self.scrub_start
        print('Scrub jumped to start (tick outside new range)')
    end
end
```

### 5. Alt Lock for Scrub

**State:**
```lua
-- In bufferseq.lua
self.scrub_locked = false
```

**Behavior:**
- While scrub is active, tap alt → lock scrub
- Locked scrub continues playing even after releasing pads
- Unlock triggers: pad press, alt tap, alt reset

**Implementation:**
```lua
function BufferSeq:alt_event(data)
    if data.state and self.mode.alt then
        -- Entering alt mode
        if self.scrub_active and not self.scrub_locked then
            -- Lock the scrub
            self.scrub_locked = true
            self.held_pads = {} -- Release tracking but keep playing
            print('Scrub locked')
            -- Don't enter normal alt mode (loop point setting)
            return
        end
        -- Normal alt mode behavior for loop point setting
        self:start_blink()
    elseif not data.state and not self.mode.alt then
        -- Exiting alt mode
        if self.scrub_locked then
            -- Unlock but keep playing
            self.scrub_locked = false
            print('Scrub unlocked')
        end
    end
end

function BufferSeq:grid_event(component, data)
    -- Any pad press unlocks
    if self.scrub_locked and data.type == 'pad' and data.state then
        self.scrub_locked = false
        print('Scrub unlocked by pad press')
    end

    -- Don't process pad events if locked (keep current scrub)
    if self.scrub_locked then return end

    -- ... existing pad handling logic
end

-- Listen for alt reset
self:on('alt_reset', function()
    if self.scrub_locked then
        self.scrub_locked = false
        self:stop_scrub()
        print('Scrub stopped by alt reset')
    end
end)
```

### 6. Buffer/Clip Persistence Architecture

**File Structure:**
```
~/dust/data/midi_thru_machine/
├── buffers/
│   ├── track_1_buffer.lua
│   ├── track_2_buffer.lua
│   └── ...
└── clips/
    ├── clip_001.lua
    ├── clip_002.lua
    └── ...
```

**Buffer File Format:**
```lua
-- track_1_buffer.lua
return {
    buffer_step_length = 24,
    seq_start = 0,
    seq_length = 384,
    buffer = {
        [0] = {
            {type = 'note_on', note = 60, vel = 100, ch = 1},
            {type = 'note_off', note = 60, vel = 0, ch = 1},
        },
        [24] = {
            {type = 'note_on', note = 64, vel = 100, ch = 1},
        },
        -- ... sparse table of tick -> events
    }
}
```

**Clip File Format (Future):**
```lua
-- clip_001.lua
-- Clips are zero-indexed (first tick is 0)
-- This clip was extracted from loop points 64-128, remapped to 0-64
return {
    name = "Bassline Loop",
    length = 64, -- ticks
    step_length = 24,
    buffer = {
        [0] = {
            {type = 'note_on', note = 48, vel = 100, ch = 1},
        },
        -- ...
    }
}
```

**Save/Load API:**
```lua
-- In persistence.lua or new clips.lua utility

function save_buffer(track_id)
    local auto = App.track[track_id].auto
    local data = {
        buffer_step_length = auto.buffer_step_length,
        seq_start = auto.seq_start,
        seq_length = auto.seq_length,
        buffer = auto.buffer_write, -- Save write buffer
    }

    local path = _path.data .. 'midi_thru_machine/buffers/track_' .. track_id .. '_buffer.lua'
    tab.save(data, path)
    print('Buffer saved: ' .. path)
end

function load_buffer(track_id)
    local path = _path.data .. 'midi_thru_machine/buffers/track_' .. track_id .. '_buffer.lua'
    local data = tab.load(path)

    if data then
        local auto = App.track[track_id].auto
        auto.buffer_step_length = data.buffer_step_length or 24
        auto.seq_start = data.seq_start or 0
        auto.seq_length = data.seq_length or 384
        auto.buffer_write = data.buffer or {}
        auto.buffer_read = {} -- Empty initially, will fill on next swap
        print('Buffer loaded: ' .. path)
        return true
    end
    return false
end

-- Future: Save clip from current loop points
function save_clip_from_loop(track_id, clip_name)
    local auto = App.track[track_id].auto
    local loop_start = auto.seq_start
    local loop_end = auto.seq_start + auto.seq_length - 1

    -- Extract and remap buffer events to 0-indexed clip
    local clip_buffer = {}
    for tick = loop_start, loop_end do
        if auto.buffer_write[tick] then
            local clip_tick = tick - loop_start
            clip_buffer[clip_tick] = auto.buffer_write[tick]
        end
    end

    local data = {
        name = clip_name,
        length = auto.seq_length,
        step_length = auto.buffer_step_length,
        buffer = clip_buffer,
    }

    -- Generate unique clip ID
    local clip_id = generate_clip_id()
    local path = _path.data .. 'midi_thru_machine/clips/clip_' .. clip_id .. '.lua'
    tab.save(data, path)
    print('Clip saved: ' .. path)
    return clip_id
end
```

**Integration with PSET:**
- PSETs save/load track parameters but NOT buffer contents
- Buffer contents saved separately to avoid bloating PSET files
- On PSET load, check for corresponding buffer files and load if available
- User can manually save/load buffers via menu

## Revised User Stories

### Phase 1: Foundation & Double Buffer (Critical)

#### STORY 1.1: Refactor Tick/Step Terminology
**As a** developer
**I want** clear distinction between "tick" (position) and "step" (duration)
**So that** the codebase is maintainable

**Acceptance Criteria:**
- [ ] Rename `auto.step` to `auto.tick` throughout codebase
- [ ] Add helper methods: `get_current_step_index()`, `tick_to_step_index()`, `step_index_to_tick_range()`
- [ ] Update all transport_event logic to use `auto.tick`
- [ ] Update bufferseq to use tick-based calculations
- [ ] Update comments to clarify tick vs step
- [ ] All existing functionality still works

**Files to Modify:**
- `src/lib/components/track/auto.lua`
- `src/lib/components/mode/bufferseq.lua`
- `src/lib/components/mode/presetseq.lua`

---

#### STORY 1.2: Implement Step-Based Read/Write Buffer Structure
**As a** user
**I want** my recordings to appear in playback within one step
**So that** I get immediate feedback without waiting for long loops

**Acceptance Criteria:**
- [ ] Add `auto.buffer_read = {}` and `auto.buffer_write = {}`
- [ ] Add `auto.last_step_index` to track step transitions
- [ ] Change `record_buffer()` to write to `buffer_write`
- [ ] Change `run_buffer()` to read from `buffer_read`
- [ ] Implement `auto:swap_buffer_step(step_index)` method
- [ ] Detect step transitions in `transport_event` (compare current vs last step index)
- [ ] Call `swap_buffer_step()` on step exit (when entering new step, swap completed step)
- [ ] Don't swap during scrub mode
- [ ] Only swap ticks within step range and loop boundaries
- [ ] Migrate existing `seq[tick].buffer` to new structure on load
- [ ] Update `clear_buffer()` to clear both buffers
- [ ] Update `clear_buffer_step()` to only clear `buffer_write`

**Technical Implementation:**
```lua
-- In auto.lua:set()
self.buffer_read = {}
self.buffer_write = {}
self.last_step_index = nil

-- Step-based swap (called on step transition)
function Auto:swap_buffer_step(step_index)
    local start_tick, end_tick = self:step_index_to_tick_range(step_index)

    -- Clamp to loop boundaries
    local loop_start = self.seq_start
    local loop_end = self.seq_start + self.seq_length - 1
    start_tick = math.max(start_tick, loop_start)
    end_tick = math.min(end_tick, loop_end)

    -- Clear old read data for this step
    for tick = start_tick, end_tick do
        self.buffer_read[tick] = nil
    end

    -- Copy write to read for this step
    for tick = start_tick, end_tick do
        if self.buffer_write[tick] then
            self.buffer_read[tick] = self.buffer_write[tick]
        end
    end
end

-- In transport_event()
if data.type == 'clock' and self.playing then
    local current_step_index = self:tick_to_step_index(self.tick)

    -- Detect step transition (swap on exit)
    if self.last_step_index and current_step_index ~= self.last_step_index then
        if not self.scrub_mode then
            self:swap_buffer_step(self.last_step_index)
        end
    end

    self.last_step_index = current_step_index
    -- ... rest of transport logic
end
```

**Files to Modify:**
- `src/lib/components/track/auto.lua`

---

#### STORY 1.3: Freeze Playback During Scrub
**As a** user
**I want** scrubbing to play a frozen snapshot
**So that** I'm not hearing my new recordings while exploring

**Acceptance Criteria:**
- [ ] When scrub starts: stop swapping buffer steps
- [ ] Recording continues to `buffer_write` during scrub
- [ ] When scrub ends: resume normal step-based swapping
- [ ] Steps recorded during scrub swap lazily as they're encountered in normal playback
- [ ] Scrub always plays from frozen `buffer_read`
- [ ] After scrub, normal playback gradually shows new recordings (step by step)

**Technical Notes:**
- No special handling needed - just skip swapping when `self.scrub_mode` is true
- When scrub ends, next step transition will resume swapping
- Lazy swap approach keeps UI responsive

**Files to Modify:**
- `src/lib/components/track/auto.lua` (transport_event step transition logic)

---

#### STORY 1.4: Handle Step Length Changes
**As a** user
**I want** step length changes to update buffer visualization correctly
**So that** the buffer display stays consistent with step boundaries

**Acceptance Criteria:**
- [ ] When `buffer_step_length` changes, invalidate `buffer_read`
- [ ] Re-swap all steps within loop boundaries with new step length
- [ ] Reset `last_step_index` to trigger fresh step tracking
- [ ] Update bufferseq display to reflect new step boundaries
- [ ] Performance should be acceptable (test with large buffers)

**Technical Implementation:**
```lua
-- In auto.lua or wherever buffer_step_length is changed
function Auto:set_buffer_step_length(new_length)
    local old_length = self.buffer_step_length
    self.buffer_step_length = new_length

    if old_length ~= new_length then
        -- Invalidate and re-swap with new boundaries
        self:invalidate_and_reswap()
    end
end

function Auto:invalidate_and_reswap()
    -- Clear read buffer
    self.buffer_read = {}

    -- Re-swap all steps within current loop
    local loop_start = self.seq_start
    local loop_end = self.seq_start + self.seq_length - 1
    local first_step = self:tick_to_step_index(loop_start)
    local last_step = self:tick_to_step_index(loop_end)

    for step_idx = first_step, last_step do
        self:swap_buffer_step(step_idx)
    end

    -- Reset step tracking
    self.last_step_index = nil

    print('Buffer re-swapped with new step length: ' .. self.buffer_step_length)
end
```

**Files to Modify:**
- `src/lib/components/track/auto.lua`
- `src/lib/components/mode/bufferseq.lua` (call `set_buffer_step_length` when changing)

---

### Phase 2: Play-Through Mode (High Priority)

#### STORY 2.1: Add Scrub Mode Selection
**As a** user
**I want** to choose between loop and play-through scrub modes
**So that** I can explore the buffer different ways

**Acceptance Criteria:**
- [ ] Add `App.buffer_scrub_mode` param: 'loop' | 'play_through'
- [ ] Default: 'loop'
- [ ] Param in buffer menu (bufferdefault.lua)
- [ ] Mode selection updates bufferseq behavior
- [ ] Visual indicator shows current mode

**Files to Modify:**
- `src/lib/app.lua` (add global param)
- `src/lib/components/mode/bufferdefault.lua` (add to menu)

---

#### STORY 2.2: Implement Long-Press Length Setting (Single Pad)
**As a** user in play-through mode
**I want** to long-hold a single pad to set play length to 1 step
**So that** subsequent taps play one step

**Acceptance Criteria:**
- [ ] Long-hold (> 0.3s) single pad sets `playthrough_length = buffer_step_length`
- [ ] No playback triggered (just sets length)
- [ ] Visual feedback: "Length: 1 step"
- [ ] Subsequent momentary presses use this length

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (handle pad_long event)

---

#### STORY 2.3: Implement Long-Press Length Setting (Two Pads)
**As a** user in play-through mode
**I want** to long-hold two pads to set play length to the span
**So that** I can define custom play lengths

**Acceptance Criteria:**
- [ ] Long-hold with exactly 1 other pad held sets `playthrough_length = span`
- [ ] Span calculated from earliest to latest pad (inclusive)
- [ ] No playback triggered (just sets length)
- [ ] Visual feedback: "Length: X steps (Y ticks)"
- [ ] Subsequent momentary presses use this length

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (handle pad_long event)

---

#### STORY 2.4: Implement Momentary Press (One-Shot)
**As a** user in play-through mode
**I want** to tap a pad and hear the defined length
**So that** I can trigger segments rhythmically

**Acceptance Criteria:**
- [ ] Momentary press plays for `playthrough_length` (default: 1 step)
- [ ] Playback starts on pad down
- [ ] After length elapses, playback stops automatically (one-shot)
- [ ] Multiple quick taps trigger multiple one-shots
- [ ] Works with launch quantization

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (handle pad down/up)
- `src/lib/components/track/auto.lua` (add oneshot scrub mode)

---

#### STORY 2.5: Implement Sustained Hold (Single Pad)
**As a** user in play-through mode
**I want** to hold a pad and hear from that point onward
**So that** I can ride a segment as long as I want

**Acceptance Criteria:**
- [ ] Holding single pad (no length set) plays from that point
- [ ] Respects auto's loop points (seq_start + seq_length)
- [ ] Playback wraps at auto loop end (not scrub start)
- [ ] Release stops playback
- [ ] Works with launch quantization

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (handle pad down/up)
- `src/lib/components/track/auto.lua` (sustained scrub mode)

---

#### STORY 2.6: Implement Multi-Pad Loop
**As a** user in play-through mode
**I want** to hold multiple pads to loop between them
**So that** I can define loop regions on the fly

**Acceptance Criteria:**
- [ ] Holding 2+ pads loops between earliest and latest
- [ ] Release all pads stops loop
- [ ] Works identically to loop mode (existing behavior)

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (existing logic should work)

---

#### STORY 2.7: Update Length During Playback
**As a** user
**I want** length changes to affect active playback immediately
**So that** I can adjust on the fly

**Acceptance Criteria:**
- [ ] Long-press to change length while scrub is active updates `scrub_end`
- [ ] If current tick > new scrub_end, jump back to scrub_start
- [ ] If still in bounds, continue playing
- [ ] Kill notes before jumping to prevent stuck notes
- [ ] Visual feedback shows new range

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (handle long press during active scrub)
- `src/lib/components/track/auto.lua` (add `update_scrub_length()` method)

---

### Phase 3: Launch Quantization (High Priority)

#### STORY 3.1: Add Launch Quantization Parameter
**As a** user
**I want** to quantize scrub/clip launches to rhythmic boundaries
**So that** launches feel musical

**Acceptance Criteria:**
- [ ] Add per-track param `launch_quantize`
- [ ] Options: 'off', 'default', '1/64', '1/32', '1/16', '1/8', '1/4', '1/2', '1/1'
- [ ] 'default' uses bufferseq's current step_length
- [ ] 'off' launches on next tick (immediate)
- [ ] Param accessible in track settings

**Files to Modify:**
- `src/lib/components/app/track.lua` (add param)

---

#### STORY 3.2: Implement Launch Quantization Logic
**As a** user
**I want** scrub starts to wait for quantization boundary
**So that** launches are in time

**Acceptance Criteria:**
- [ ] When scrub requested, calculate next quantized tick
- [ ] Delay scrub start until that tick
- [ ] Works with all quantize values
- [ ] Works with both loop and play-through modes
- [ ] Visual feedback shows pending launch (blinking pads?)

**Files to Modify:**
- `src/lib/components/track/auto.lua` (add `calculate_launch_tick()` and `schedule_scrub_start()`)
- `src/lib/components/mode/bufferseq.lua` (call scheduled launch)

---

### Phase 4: Alt Lock & UX Polish (Medium Priority)

#### STORY 4.1: Implement Scrub Lock on Alt Tap
**As a** user
**I want** to tap alt while scrubbing to lock it
**So that** I can let go and it keeps playing

**Acceptance Criteria:**
- [ ] While scrub active, tap alt → lock scrub
- [ ] Release pads doesn't stop scrub when locked
- [ ] Visual feedback: locked indicator (blinking alt, different colors)
- [ ] Works in both loop and play-through modes

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (alt_event, grid_event)

---

#### STORY 4.2: Unlock Scrub on Pad Press
**As a** user
**I want** any pad press to unlock and start new scrub
**So that** I can change the region

**Acceptance Criteria:**
- [ ] Any pad press while locked unlocks
- [ ] New pad press starts new scrub
- [ ] No interruption or glitches
- [ ] Visual feedback shows unlock

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (grid_event)

---

#### STORY 4.3: Unlock Scrub on Alt Tap or Reset
**As a** user
**I want** alt tap/reset to unlock scrub
**So that** I can stop or prepare to change it

**Acceptance Criteria:**
- [ ] Alt tap while locked → unlock (keep playing)
- [ ] Alt reset while locked → unlock and stop
- [ ] Visual feedback

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (alt_event, listen for alt_reset)

---

#### STORY 4.4: Visual Feedback for Scrub States
**As a** user
**I want** clear visual indication of scrub state
**So that** I understand what's happening

**Acceptance Criteria:**
- [ ] Scrub region highlighted on grid (already done)
- [ ] Locked scrub: different color/pattern
- [ ] Play-through oneshot: visual countdown
- [ ] Pending quantized launch: blinking
- [ ] Screen shows mode, length, lock state

**Files to Modify:**
- `src/lib/components/mode/bufferseq.lua` (set_grid method)
- `src/lib/components/mode/bufferdefault.lua` (screen rendering)

---

### Phase 5: Persistence & Clip System (Future)

#### STORY 5.1: Save/Load Buffer to File
**As a** user
**I want** to save buffer contents to disk
**So that** I don't lose my recordings

**Acceptance Criteria:**
- [ ] Menu option: "Save Buffer"
- [ ] Saves to `~/dust/data/midi_thru_machine/buffers/track_X_buffer.lua`
- [ ] Includes: buffer_step_length, seq_start, seq_length, buffer table
- [ ] Only saves non-empty ticks (sparse table)
- [ ] Menu option: "Load Buffer"
- [ ] On PSET save: optionally save buffers alongside

**Files to Modify:**
- `src/lib/utilities/persistence.lua` (add save/load functions)
- `src/lib/components/mode/bufferdefault.lua` (add menu items)

---

#### STORY 5.2: Clip System Foundation
**As a** developer
**I want** architecture for saving loop regions as clips
**So that** users can build a clip library

**Acceptance Criteria:**
- [ ] Function: `save_clip_from_loop(track_id, clip_name)`
- [ ] Extracts buffer events within current loop points
- [ ] Remaps ticks to 0-indexed clip (first tick = 0)
- [ ] Saves to `~/dust/data/midi_thru_machine/clips/clip_XXX.lua`
- [ ] Generates unique clip IDs
- [ ] Clip file includes: name, length, step_length, buffer

**Files to Modify:**
- `src/lib/utilities/persistence.lua` or new `src/lib/utilities/clips.lua`

---

#### STORY 5.3: Clip Browser (Future Epic)
**As a** user
**I want** to browse and load saved clips
**So that** I can reuse my recordings

**Acceptance Criteria:**
- [ ] Clip browser mode/menu
- [ ] List all saved clips
- [ ] Preview clips (with playback)
- [ ] Load clip into track buffer
- [ ] Delete clips
- [ ] Rename clips

**Files to Create:**
- `src/lib/components/mode/clipbrowser.lua`
- `src/lib/modes/clips.lua`

---

### Phase 6: Input Muting Fixes (Low Priority)

#### STORY 6.1: Mute Input During Scrub
**As a** user
**I want** input muted during scrub
**So that** I only hear the buffer

**Acceptance Criteria:**
- [ ] Input component checks `track.auto.scrub_mode`
- [ ] When scrub active, return nil from `Input:midi_event`
- [ ] Works in both loop and play-through modes

**Files to Modify:**
- `src/lib/components/track/input.lua` (update line 31)

---

#### STORY 6.2: Respect Overdub for Input Muting
**As a** user
**I want** input to pass through in overdub mode
**So that** I can layer onto buffer playback

**Acceptance Criteria:**
- [ ] When `App.buffer_overdub` is true, input passes through
- [ ] When false (overwrite), input muted during playback

**Files to Modify:**
- `src/lib/components/track/input.lua` (update muting logic)

---

## Implementation Roadmap

### Sprint 1: Foundation (2-3 days)
- STORY 1.1: Terminology refactoring (tick vs step)
- STORY 1.2: Step-based double buffer implementation
- STORY 1.3: Freeze during scrub
- STORY 1.4: Handle step length changes

**Deliverable:** Solid foundation with clean code, step-based buffer swapping, and separation of recording/playback

---

### Sprint 2: Play-Through Core (2-3 days)
- STORY 2.1: Mode selection
- STORY 2.2: Single pad long-press length
- STORY 2.3: Two pad long-press length
- STORY 2.4: Momentary one-shot

**Deliverable:** Basic play-through mode working

---

### Sprint 3: Play-Through Polish (2 days)
- STORY 2.5: Sustained hold
- STORY 2.6: Multi-pad loop (verify existing code)
- STORY 2.7: Dynamic length updates

**Deliverable:** Complete play-through mode

---

### Sprint 4: Quantization (1-2 days)
- STORY 3.1: Quantization parameter
- STORY 3.2: Quantization logic

**Deliverable:** Musical, quantized launches

---

### Sprint 5: UX Polish (2-3 days)
- STORY 4.1: Alt lock
- STORY 4.2: Unlock on pad
- STORY 4.3: Unlock on alt/reset
- STORY 4.4: Visual feedback

**Deliverable:** Professional, polished scrub experience

---

### Sprint 6: Persistence Foundation (2 days)
- STORY 5.1: Buffer save/load
- STORY 5.2: Clip system foundation

**Deliverable:** Buffers can be saved and reused

---

### Sprint 7: Input Muting (1 day)
- STORY 6.1: Mute during scrub
- STORY 6.2: Respect overdub

**Deliverable:** Clean input/playback separation

---

### Future: Clip Browser (5-7 days)
- STORY 5.3: Full clip browser/manager

---

## Testing Strategy

### Unit Tests
- Tick/step conversion helpers
- Buffer swap logic
- Launch quantization calculations
- Scrub state transitions
- Play-through length calculations

### Integration Tests
- Record → swap → playback cycle
- Scrub during recording
- Length updates during playback
- Alt lock/unlock flows
- Quantized launch timing

### Manual Test Scenarios
1. Record a loop in overwrite mode, verify swap on next loop
2. Start scrub while recording, verify frozen playback
3. Set play-through length with long-press, trigger with taps
4. Lock scrub with alt, release pads, unlock with pad press
5. Change length during active scrub, verify jump/continue behavior
6. Test all quantization values
7. Save buffer, reload, verify contents
8. Extract clip from loop, verify tick remapping

---

## Performance Considerations

### Buffer Size
- No initial limits (test performance first)
- Sparse tables minimize memory usage
- Monitor performance with multiple armed tracks

### File I/O
- Save buffers asynchronously if possible
- Don't block UI during save/load
- Consider compression for large buffers (future)

### Grid Refresh Rate
- Maintain 24fps UI refresh
- Optimize `set_grid` for large buffers (only draw visible region)
- Use dirty flags to minimize unnecessary redraws

---

## Success Criteria

- [ ] Buffer records continuously to write buffer
- [ ] Playback reads from read buffer (never corrupted by recording)
- [ ] Play-through mode feels intuitive and musical
- [ ] Long-press length setting is discoverable and responsive
- [ ] Alt lock enables hands-free scrub performances
- [ ] Launch quantization makes triggers feel tight
- [ ] Buffers can be saved and reloaded reliably
- [ ] Clip foundation enables future clip library
- [ ] No stuck notes or playback glitches
- [ ] Performance is acceptable with multiple armed tracks
- [ ] All edge cases covered by tests
- [ ] Documentation is clear

---

## Open Design Questions (Resolved)

✅ **Buffer size limits?** → Test performance first, no initial limits
✅ **Persistence strategy?** → Separate files using tab.save, future clip system
✅ **Global buffers?** → Stick with per-track for now
✅ **Scrub quantization?** → Yes, launch quantization parameter
✅ **Play-through default length?** → Current step_length from bufferseq
✅ **Always-on recording?** → Deprioritized, can default tracks to armed

---

## Next Steps

1. **Review this plan** with stakeholders
2. **Set up testing framework** for buffer logic
3. **Begin Sprint 1:** Terminology refactoring and double buffer
4. **Iterate and adjust** based on findings during implementation
