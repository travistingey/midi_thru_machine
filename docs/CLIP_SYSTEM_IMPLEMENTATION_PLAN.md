# Clip System Implementation Plan

## Executive Summary

This document outlines the feasibility and implementation plan for adding a persistent clip system to the MIDI Thru Machine. The system will enable recording MIDI into buffers, saving them as clips with metadata, and playing them back via the Seq component with launch quantization.

---

## 1. Feasibility Audit

### ✅ Existing Foundation (STRONG)

| Component | Status | Notes |
|-----------|--------|-------|
| **Buffer Recording** | ✅ Fully implemented | Auto component has dual-buffer architecture (`buffer_write`, `buffer_read`) |
| **MIDI Event Storage** | ✅ Well-defined | Clear data structures with tick-indexed arrays |
| **File I/O System** | ✅ Operational | `Persistence` module handles tab.save/load |
| **Seq Component** | ⚠️ WIP but usable | Already has `clips`, `save_clip()`, `load_clip()` methods |
| **Loop Boundaries** | ✅ Implemented | `seq_start`, `seq_length` for defining regions |
| **Transport System** | ✅ Robust | Event-driven with tick-level precision |

### 🔨 Required Additions (FEASIBLE)

| Feature | Difficulty | Risk |
|---------|-----------|------|
| **Clip File Format** | Low | None - extend existing persistence |
| **Buffer → Clip Export** | Low | None - similar to existing `save_clip()` |
| **Clip Metadata Storage** | Low | None - simple table structure |
| **Seq Slot Management** | Medium | Low - architectural changes needed |
| **Launch Quantization** | Medium | Low - transport integration required |
| **Clip Launch/Stop** | Medium | Low - state management needed |
| **UI Integration** | Medium | Medium - grid layout complexity |

### 🚧 Technical Challenges

1. **Buffer/Seq Relationship**: Currently Auto handles buffer recording/playback, Seq is separate. Need clear handoff.
2. **Multiple Clips Per Track**: Seq needs expansion to handle multiple slots (currently single playback_buffer).
3. **Launch Quantization**: Requires scheduling system to defer clip start to beat/bar boundaries.
4. **Clip State Management**: Need to track which clips are loaded, playing, queued, stopped per track.

### ✅ Overall Feasibility: **HIGH**

The existing architecture is well-suited for this enhancement. All core primitives exist; mainly requires:
- Extending Seq component with slot architecture
- Creating clip file I/O layer
- Adding launch scheduling logic
- UI updates

---

## 2. Clip File Format

### File Structure

```lua
-- Location: /home/we/dust/data/midi_thru_machine/clips/
-- Filename: <clip_name>.clip

{
  version = 1,
  name = "My Clip",
  created = 1642534800,  -- Unix timestamp
  length = 384,          -- Ticks (1 bar @ 96ppqn)

  -- MIDI event data (tick-indexed)
  events = {
    [0] = {
      { type = 'note_on', note = 60, vel = 100, ch = 1 },
      { type = 'note_on', note = 64, vel = 95, ch = 1 },
    },
    [6] = {
      { type = 'note_off', note = 60, ch = 1 },
    },
    [12] = {
      { type = 'note_off', note = 64, ch = 1 },
    },
    -- ... more events
  },

  -- Settings that apply when clip launches
  settings = {
    scale_select = 0,          -- Scale/key
    program_change = nil,      -- MIDI program (nil = don't change)
    arp = nil,                 -- Arpeggiator mode (nil = don't change)
    slew = nil,                -- Note slew amount
    chance = nil,              -- Note probability
    step_length = nil,         -- Step length
    -- Any other App.preset parameters
  },

  -- Playback metadata
  loop = true,                 -- Loop or one-shot
  loop_start = 0,             -- Loop start point (ticks)
  loop_end = 384,             -- Loop end point (ticks)

  -- Optional metadata
  tags = { "drums", "live" },
  color = 3,                   -- For UI display
  description = "Live recorded drum pattern",
}
```

### File Operations

**Save Clip:**
```lua
Clips.save(clip_name, buffer, start_tick, end_tick, settings, metadata)
-- Writes to: norns.state.data .. "clips/" .. clip_name .. ".clip"
```

**Load Clip:**
```lua
local clip_data = Clips.load(clip_name)
-- Returns table with events, settings, metadata
```

**List Clips:**
```lua
local clip_list = Clips.list()
-- Returns array of clip names
```

---

## 3. Implementation Plan

### Phase 1: Clip File I/O Layer

**New File:** `src/lib/utilities/clips.lua`

```lua
local Clips = {}

-- Create clips directory if it doesn't exist
function Clips.init()
  -- Check/create norns.state.data .. "clips/"
end

-- Save buffer region as clip
function Clips.save(clip_name, buffer, start_tick, end_tick, settings, metadata)
  -- Extract events from buffer[start_tick..end_tick]
  -- Build clip data structure
  -- tab.save() to clip file
end

-- Load clip from file
function Clips.load(clip_name)
  -- tab.load() from clip file
  -- Return clip data or nil if not found
end

-- List all available clips
function Clips.list()
  -- Scan clips directory
  -- Return array of clip names
end

-- Delete clip file
function Clips.delete(clip_name)
  -- Remove file
end

-- Get clip metadata without loading full event data
function Clips.get_metadata(clip_name)
  -- Load only metadata fields (name, length, tags, etc.)
end

return Clips
```

**Properties:**
- None (utility module)

**Functions:**
- `Clips.init()` - Initialize clips directory
- `Clips.save(name, buffer, start, end, settings, metadata)` - Export buffer to clip file
- `Clips.load(name)` - Load clip data from file
- `Clips.list()` - List all clip files
- `Clips.delete(name)` - Remove clip file
- `Clips.get_metadata(name)` - Load metadata only

---

### Phase 2: Buffer Export Functionality

**Updated File:** `src/lib/components/track/auto.lua`

**New Methods:**

```lua
-- Export buffer region as clip
function Auto:export_clip(clip_name, start_tick, end_tick, include_settings)
  local settings = nil
  if include_settings then
    -- Capture current track preset settings
    settings = {
      scale_select = self.track.scale_select,
      program_change = self.track.program_change,
      arp = self.track.arp,
      -- ... etc
    }
  end

  -- Extract events from buffer_read
  local events = self:extract_buffer_region(start_tick, end_tick)

  -- Save via Clips module
  Clips.save(clip_name, events, 0, end_tick - start_tick, settings, {
    loop = App.buffer_loop,
    loop_start = 0,
    loop_end = end_tick - start_tick,
  })
end

-- Extract events from buffer region
function Auto:extract_buffer_region(start_tick, end_tick)
  local events = {}
  for tick = start_tick, end_tick do
    if self.buffer_read[tick] then
      events[tick - start_tick] = tab.copy(self.buffer_read[tick])
    end
  end
  return events
end
```

**New Properties:**
- None (adds methods only)

**New Functions:**
- `Auto:export_clip(clip_name, start_tick, end_tick, include_settings)` - Export buffer region
- `Auto:extract_buffer_region(start_tick, end_tick)` - Helper to extract event data

---

### Phase 3: Seq Component Enhancement

**Updated File:** `src/lib/components/track/seq.lua`

**New Architecture:** Multi-slot clip system with launch scheduling

**New Properties:**

```lua
-- Slot system (8 slots per track)
self.slots = {}
for i = 1, 8 do
  self.slots[i] = {
    clip_data = nil,           -- Loaded clip data (events, settings, metadata)
    state = 'empty',          -- 'empty', 'loaded', 'playing', 'queued', 'stopping'
    playback_tick = 0,        -- Current playback position
    launch_quantize = 1,      -- Quantize launch to: 0=immediate, 1=bar, 2=2bars, 4=4bars
    stop_quantize = 0,        -- Quantize stop: 0=immediate, 1=bar
    scheduled_action = nil,   -- { action='start'|'stop', at_tick=384 }
  }
end

self.active_slot = nil         -- Currently playing slot index
self.next_slot = nil          -- Queued slot index
```

**New Methods:**

```lua
-- Load clip into slot
function Seq:load_clip_to_slot(slot_index, clip_name)
  local clip_data = Clips.load(clip_name)
  if not clip_data then return false end

  self.slots[slot_index].clip_data = clip_data
  self.slots[slot_index].state = 'loaded'
  self.slots[slot_index].playback_tick = 0
  return true
end

-- Launch clip from slot
function Seq:launch_slot(slot_index, quantize)
  local slot = self.slots[slot_index]
  if slot.state == 'empty' then return end

  quantize = quantize or slot.launch_quantize

  if quantize == 0 then
    -- Immediate launch
    self:_start_slot(slot_index)
  else
    -- Schedule launch
    local next_boundary = self:_calculate_next_quantize_boundary(quantize)
    slot.scheduled_action = { action = 'start', at_tick = next_boundary }
    slot.state = 'queued'
  end
end

-- Stop slot playback
function Seq:stop_slot(slot_index, quantize)
  local slot = self.slots[slot_index]
  if slot.state ~= 'playing' then return end

  quantize = quantize or slot.stop_quantize

  if quantize == 0 then
    self:_stop_slot(slot_index)
  else
    local next_boundary = self:_calculate_next_quantize_boundary(quantize)
    slot.scheduled_action = { action = 'stop', at_tick = next_boundary }
    slot.state = 'stopping'
  end
end

-- Calculate next quantize boundary
function Seq:_calculate_next_quantize_boundary(bars)
  local bar_length = App.ppqn * 4  -- 1 bar = 4 beats
  local quantize_length = bar_length * bars
  local current_tick = self.track.transport_tick
  local next_boundary = math.ceil(current_tick / quantize_length) * quantize_length
  return next_boundary
end

-- Internal: actually start slot playback
function Seq:_start_slot(slot_index)
  local slot = self.slots[slot_index]

  -- Stop current slot if any
  if self.active_slot then
    self:_stop_slot(self.active_slot)
  end

  -- Apply clip settings to track
  if slot.clip_data.settings then
    self:_apply_clip_settings(slot.clip_data.settings)
  end

  -- Start playback
  slot.state = 'playing'
  slot.playback_tick = slot.clip_data.loop_start or 0
  self.active_slot = slot_index
end

-- Internal: stop slot playback
function Seq:_stop_slot(slot_index)
  local slot = self.slots[slot_index]
  slot.state = 'loaded'
  slot.playback_tick = 0

  if self.active_slot == slot_index then
    self.active_slot = nil
  end

  -- Send note-offs for any hanging notes
  self:_send_all_notes_off()
end

-- Apply clip settings to track
function Seq:_apply_clip_settings(settings)
  for key, value in pairs(settings) do
    if self.track[key] ~= nil then
      self.track[key] = value
    end
  end
  -- Emit event for UI updates
  self.track:emit('clip_settings_applied', settings)
end

-- Send all notes off (panic)
function Seq:_send_all_notes_off()
  for note = 0, 127 do
    self.track:send({
      type = 'note_off',
      note = note,
      ch = self.track.output_channel
    })
  end
end

-- Process transport (main playback engine)
function Seq:transport_event(data)
  -- Check scheduled actions
  for i, slot in ipairs(self.slots) do
    if slot.scheduled_action and data.tick >= slot.scheduled_action.at_tick then
      if slot.scheduled_action.action == 'start' then
        self:_start_slot(i)
      elseif slot.scheduled_action.action == 'stop' then
        self:_stop_slot(i)
      end
      slot.scheduled_action = nil
    end
  end

  -- Playback active slot
  if self.active_slot then
    local slot = self.slots[self.active_slot]
    local clip = slot.clip_data

    -- Play events at current tick
    local events = clip.events[slot.playback_tick]
    if events then
      for _, event in ipairs(events) do
        self.track:send(event)
      end
    end

    -- Advance playback position
    slot.playback_tick = slot.playback_tick + 1

    -- Handle looping
    local loop_end = clip.loop_end or clip.length
    if slot.playback_tick >= loop_end then
      if clip.loop then
        slot.playback_tick = clip.loop_start or 0
      else
        -- One-shot finished
        self:_stop_slot(self.active_slot)
      end
    end
  end
end
```

**Updated Properties:**
- `self.slots` - Array of 8 clip slots with state management
- `self.active_slot` - Index of currently playing slot
- `self.next_slot` - Index of queued slot
- Remove/deprecate: `self.playback_buffer`, `self.clips` (replaced by slot system)

**New Functions:**
- `Seq:load_clip_to_slot(slot_index, clip_name)` - Load clip file into slot
- `Seq:launch_slot(slot_index, quantize)` - Launch clip playback
- `Seq:stop_slot(slot_index, quantize)` - Stop clip playback
- `Seq:_calculate_next_quantize_boundary(bars)` - Calculate launch timing
- `Seq:_start_slot(slot_index)` - Internal immediate start
- `Seq:_stop_slot(slot_index)` - Internal immediate stop
- `Seq:_apply_clip_settings(settings)` - Apply clip metadata to track
- `Seq:_send_all_notes_off()` - MIDI panic

**Updated Functions:**
- `Seq:transport_event(data)` - Add scheduled action processing + slot playback

---

### Phase 4: Launch Quantization System

**Quantization Levels:**
- `0` - Immediate (no quantization)
- `1` - Next bar (384 ticks @ 96ppqn)
- `2` - Next 2 bars (768 ticks)
- `4` - Next 4 bars (1536 ticks)

**Implementation Details:**

1. **Boundary Calculation:**
   ```lua
   function _calculate_next_quantize_boundary(bars)
     local bar_length = App.ppqn * 4
     local quantize_length = bar_length * bars
     local current_tick = self.track.transport_tick
     return math.ceil(current_tick / quantize_length) * quantize_length
   end
   ```

2. **Scheduling:**
   - Store `scheduled_action` with target tick
   - Check each transport_event for scheduled actions
   - Execute when `data.tick >= scheduled_action.at_tick`

3. **Queued State:**
   - Slot state changes to `'queued'` or `'stopping'`
   - UI can display pending status
   - User can cancel by re-triggering slot

---

### Phase 5: Track Integration

**Updated File:** `src/lib/app/track.lua`

**Changes:**

```lua
-- In Track:init()
-- Enable Seq component by default
table.insert(self.chain, self.seq)

-- Add parameter for Seq enable/disable
params:add {
  type = "option",
  id = "seq_enabled_" .. self.id,
  name = "Seq Mode",
  options = { "Off", "On" },
  default = 1,
  action = function(value)
    self.seq_enabled = (value == 2)
  end
}

-- New method: Export buffer to clip
function Track:export_buffer_clip(clip_name, start_tick, end_tick, include_settings)
  return self.auto:export_clip(clip_name, start_tick, end_tick, include_settings)
end

-- New method: Load clip to seq slot
function Track:load_clip(slot_index, clip_name)
  return self.seq:load_clip_to_slot(slot_index, clip_name)
end

-- New method: Launch seq slot
function Track:launch_slot(slot_index, quantize)
  self.seq:launch_slot(slot_index, quantize)
end

-- New method: Stop seq slot
function Track:stop_slot(slot_index, quantize)
  self.seq:stop_slot(slot_index, quantize)
end
```

**New Track Methods:**
- `Track:export_buffer_clip(name, start, end, include_settings)` - Export buffer region
- `Track:load_clip(slot_index, clip_name)` - Load clip to slot
- `Track:launch_slot(slot_index, quantize)` - Launch slot
- `Track:stop_slot(slot_index, quantize)` - Stop slot

---

### Phase 6: UI Components

**New Mode Component:** `src/lib/components/mode/clipbrowser.lua`

Grid interface for:
- Browse available clips
- Select and load into slots
- Preview clip metadata
- Delete clips

**New Mode Component:** `src/lib/components/mode/clipslots.lua`

Grid interface for:
- View 8 slot states per track
- Launch/stop slots via grid pads
- Visual feedback (empty/loaded/playing/queued)
- Set quantization per slot

**Updated Component:** `src/lib/components/mode/bufferseq.lua`

Add controls for:
- Export buffer region as clip
- Set export start/end points
- Name clip (text entry)
- Include/exclude settings

**Menu Integration:** `src/lib/components/mode/bufferdefault.lua`

Add menu items:
- "Export Buffer as Clip"
- "Load Clip to Slot"
- "Manage Clips"

---

## 4. Workflow Examples

### Recording and Saving a Clip

```
1. User arms track for recording
2. User plays MIDI into buffer (Auto component records)
3. User reviews buffer via BufferSeq grid UI
4. User sets start/end points for desired region
5. User selects "Export Buffer as Clip" from menu
6. User names clip "funky_bass_01"
7. User chooses whether to include current settings (scale, program, etc.)
8. System calls: Track:export_buffer_clip("funky_bass_01", start_tick, end_tick, true)
9. Clip file saved to clips/funky_bass_01.clip
```

### Loading and Launching a Clip

```
1. User navigates to ClipSlots mode
2. Grid shows 8 empty slots
3. User long-presses slot 1
4. ClipBrowser mode opens
5. User selects "funky_bass_01" from list
6. System calls: Track:load_clip(1, "funky_bass_01")
7. Slot 1 pad lights up (loaded state)
8. User presses slot 1 pad to launch
9. System calls: Track:launch_slot(1, quantize=1)
10. Slot 1 queued (flashing)
11. At next bar boundary, clip starts playing
12. Slot 1 pad solid bright (playing state)
13. Clip settings applied (scale, program change, etc.)
```

### Live Performance Loop

```
1. User loads 4 clips into slots 1-4
2. User launches slot 1 (playing immediately, quantize=0)
3. After 4 bars, user presses slot 2
4. Slot 2 queued (quantize=1, next bar)
5. At bar boundary, slot 2 starts, slot 1 stops
6. User continues switching between slots
7. Each clip brings its own scale/settings
8. Buffer recording continues independently in Auto component
```

---

## 5. Component State Diagram

```
SLOT STATES:

empty → loaded → queued → playing → stopping → loaded
  ↓                         ↑          ↓
  └─────────────────────────┴──────────┘
  (unload)                (stop immediate)

empty:    No clip loaded
loaded:   Clip loaded, not playing
queued:   Scheduled to start at quantize boundary
playing:  Actively playing back
stopping: Scheduled to stop at quantize boundary
```

---

## 6. Parameter Summary

### App Level
- `App.clip_dir` - Clips directory path

### Track Level
- `seq_enabled_[track_id]` - Enable/disable Seq mode

### Seq Slot Level (per slot)
- `launch_quantize` - 0=immediate, 1=bar, 2=2bars, 4=4bars
- `stop_quantize` - 0=immediate, 1=bar

---

## 7. File Structure Changes

```
/home/we/dust/data/midi_thru_machine/
├── clips/                          (NEW)
│   ├── funky_bass_01.clip
│   ├── drum_break_02.clip
│   └── ...
├── preset_data_01.txt
├── preset_data_02.txt
└── ...

src/lib/
├── utilities/
│   ├── persistence.lua
│   └── clips.lua                   (NEW)
├── components/
│   ├── track/
│   │   ├── auto.lua                (UPDATED)
│   │   └── seq.lua                 (UPDATED)
│   └── mode/
│       ├── bufferseq.lua           (UPDATED)
│       ├── clipbrowser.lua         (NEW)
│       └── clipslots.lua           (NEW)
└── app/
    └── track.lua                   (UPDATED)
```

---

## 8. Implementation Order

### Phase 1: Foundation (Week 1)
1. Create `clips.lua` utility module
2. Implement file save/load/list/delete
3. Test clip file I/O independently

### Phase 2: Buffer Export (Week 1)
1. Add `Auto:export_clip()` method
2. Add `Auto:extract_buffer_region()` helper
3. Test exporting buffer regions to files

### Phase 3: Seq Core (Week 2)
1. Implement slot architecture in `seq.lua`
2. Add `load_clip_to_slot()` method
3. Implement `_start_slot()` and `_stop_slot()`
4. Test basic playback without quantization

### Phase 4: Launch Quantization (Week 2)
1. Implement `launch_slot()` with scheduling
2. Implement `_calculate_next_quantize_boundary()`
3. Add scheduled action processing to `transport_event()`
4. Test quantized launches

### Phase 5: Track Integration (Week 3)
1. Add convenience methods to `Track`
2. Enable Seq in component chain
3. Test end-to-end workflow

### Phase 6: UI (Week 3-4)
1. Create ClipBrowser mode
2. Create ClipSlots mode
3. Update BufferSeq with export controls
4. Update BufferDefault menu

### Phase 7: Polish (Week 4)
1. Add error handling
2. Add visual feedback
3. Documentation
4. User testing

---

## 9. Risk Mitigation

### Risk: Performance Impact from Slot Polling
**Mitigation:** Only check slots with scheduled_action != nil, not all 8 slots every tick

### Risk: MIDI Event Memory Usage for Large Clips
**Mitigation:** Clips are loaded on-demand, not all at once. Consider lazy loading for clips >1000 ticks.

### Risk: Clip File Corruption
**Mitigation:** Use tab.save/load which is battle-tested. Add version field for future format changes.

### Risk: Timing Drift Between Buffer and Seq
**Mitigation:** Both use same transport tick source. Seq scheduled actions use absolute tick values.

### Risk: Settings Conflicts (Auto vs Seq)
**Mitigation:** Clear precedence: When Seq slot playing, its settings override. When stopped, track returns to Auto/preset settings.

---

## 10. Testing Checklist

- [ ] Clip save/load with various buffer sizes (1 step to 64 bars)
- [ ] Launch with quantize=0 (immediate)
- [ ] Launch with quantize=1 (next bar)
- [ ] Launch with quantize=2, 4 (multiple bars)
- [ ] Stop with quantize=0 vs quantize=1
- [ ] Slot switching (stop current, start next)
- [ ] Loop playback (verify loop points)
- [ ] One-shot playback (verify stop at end)
- [ ] Settings application (scale, program change, etc.)
- [ ] Empty slot behavior (no crash)
- [ ] All notes off when stopping (no stuck notes)
- [ ] Buffer recording while clip playing (independence)
- [ ] Multiple tracks with different clips
- [ ] File I/O errors (missing clip, corrupt file)
- [ ] UI feedback for all states

---

## 11. Success Criteria

✅ User can record MIDI into buffer via Auto component
✅ User can set buffer start/end points and export as named clip
✅ Clip files save to disk with events and metadata
✅ User can browse and load clips into Seq slots
✅ User can launch clips with configurable quantization
✅ Clips loop or play one-shot based on metadata
✅ Clip settings apply to track when launched
✅ Multiple clips can be loaded across 8 slots per track
✅ Clips can be shared between tracks
✅ No audio dropouts or timing issues during clip playback
✅ UI provides clear visual feedback for all slot states

---

## 12. Future Enhancements (Out of Scope)

- Clip editing (trim, quantize, transpose)
- Clip recording directly into Seq (bypass buffer)
- Clip chaining (auto-launch next clip)
- Scene launching (launch multiple clips across tracks)
- Clip tempo/pitch stretching
- MIDI file import/export
- Cloud clip sharing
- Clip tags and search
- Undo/redo for clip operations

---

## Conclusion

This implementation is **highly feasible** given the strong existing foundation. The architecture naturally supports this enhancement with minimal breaking changes. The phased approach allows for incremental development and testing. Primary work is in:

1. Creating clip file I/O layer (straightforward)
2. Expanding Seq to multi-slot architecture (moderate complexity)
3. Implementing launch quantization scheduling (moderate complexity)
4. Building UI for clip management (time-consuming but low risk)

**Estimated Effort:** 3-4 weeks for full implementation with testing and polish.

**Recommended Start:** Phase 1 (Clip I/O layer) - can be developed and tested independently.
