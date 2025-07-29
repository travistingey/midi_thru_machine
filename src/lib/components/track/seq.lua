-- seq.lua
-- Refactored sequencer class.
-- The sequencer now continuously records MIDI events into a history buffer.
-- A portion of that history (or a separately recorded performance) can be quantized and
-- transferred to the playback buffer. Clips (or “banks”) can be saved from the playback buffer.
--
-- Requirements addressed:
--   • Increased ppqn (96) lets us remove coroutines and use simple tick‐based processing.
--   • Three buffers (history, recording, playback) are maintained as Lua tables.
--   • Buffer segmentation is supported so that a segment (e.g. one bar) can be mapped
--     to a grid pad, and clips can be saved “on the fly.”
--   • All major state changes use an event–based API (emit/on) inherited from TrackComponent.
--
local path_name = 'Foobar/lib/'
local utilities = require(path_name .. 'utilities')
local Grid = require(path_name .. 'grid')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

local Seq = {}
Seq.name = 'seq'
Seq.__index = Seq
setmetatable(Seq, { __index = TrackComponent })

-----------------------------------------------
-- Constructor & Initialization
-----------------------------------------------
function Seq:new(o)
  o = o or {}
  setmetatable(o, self)
  -- call TrackComponent’s set() to initialize common methods, etc.
  TrackComponent.set(o, o)
  o:initialize(o)
  return o
end

function Seq:initialize(o)
  -- Basic identification and timing
  self.id = self.id or 1
  self.tick = 0
  self.segment_length = self.segment_length or 48
  self.history_length = self.history_length or self.segment_length * 32

  -- Playback length defaults to one bar; you can change this to 4 or 32 bars as needed.
  self.length = self.length or self.segment_length

  -- Buffers:
  -- history_buffer: continuously records events (indexed by absolute tick)
  -- recording_buffer: a temporary buffer used when “recording” a clip segment (quantization is applied)
  -- playback_buffer: the clip currently being looped out (indexed 1…length)
  self.history_buffer   = {}  -- e.g. history_buffer[tick] = { event1, event2, ... }
  self.recording_buffer = {}  -- similarly segmented (by segment_length)
  self.playback_buffer  = {}  -- active clip for playback

  -- Bank for saved clips; each entry is a table with keys: clip and length.
  self.clip_bank = {}

  -- Recording/playback/arm state flags
  self.playing   = false
  self.recording = false
  self.armed     = false
  self.overdub   = false  -- if needed

end

-----------------------------------------------
-- Buffer Recording and Clip Management
-----------------------------------------------
-- Always record incoming events into the history buffer.
function Seq:record_event(event)
  -- Use the current absolute tick as key.
  local tick = ((self.tick - 1) % self.history_length) + 1
  if not self.history_buffer[tick] then
    self.history_buffer[tick] = {}
  end
  -- A shallow copy of event (in case later modifications occur)
  local evt = {}
  for k, v in pairs(event) do
    evt[k] = v
  end
  evt.tick = tick  -- tag with absolute tick
  table.insert(self.history_buffer[tick], evt)

  -- If in “recording” mode (for the current clip), also record into the recording buffer.
  if self.recording then
    -- Map tick into a step within the current quantize segment.
    local step = ((tick - 1) % self.segment_length) + 1
    if not self.recording_buffer[step] then
      self.recording_buffer[step] = {}
    end
    table.insert(self.recording_buffer[step], evt)
  end
end

-- Quantize the recording buffer (if needed) and move its contents into the playback buffer.
-- For simplicity, this example simply copies over the events, remapping their tick values.
function Seq:quantize_recording()
  local quantized = {}
  for step, events in pairs(self.recording_buffer) do
    quantized[step] = {}
    for _, event in ipairs(events) do
      local q_event = {}
      for k, v in pairs(event) do q_event[k] = v end
      -- Set the event’s tick relative to the clip (step number)
      q_event.tick = step
      table.insert(quantized[step], q_event)
    end
  end
  self.playback_buffer = quantized
  self.length = self.segment_length  -- update playback loop length accordingly
  self.recording_buffer = {}         -- clear recording buffer after quantizing
  -- Emit an event to notify listeners that quantization is complete.
  self:emit('quantized', self.playback_buffer)
end

-- Save the currently active playback buffer as a clip into the bank.
-- segment_range is optional here; if provided (as {start, end}), only that range is saved.
function Seq:save_clip(segment_range, bank_id)
  bank_id = bank_id or 1
  local clip = {}
  if segment_range then
    local start_tick, end_tick = segment_range[1], segment_range[2]
    for tick = start_tick, end_tick do
      if self.history_buffer[tick] then
        clip[tick - start_tick + 1] = self.history_buffer[tick]
      end
    end
  else
    -- If no range specified, save the current playback buffer.
    clip = self.playback_buffer
  end
  self.clip_bank[bank_id] = { clip = clip, length = #clip }
  self:emit('clip_saved', bank_id)
end

-- Load a clip from the bank into the playback buffer.
function Seq:load_clip(bank_id)
  local clip_data = self.clip_bank[bank_id]
  if clip_data then
    self.playback_buffer = clip_data.clip
    self.length = clip_data.length
    self.tick = 0
    self:emit('clip_loaded', bank_id)
  end
end

function Seq:load_history(start_tick, end_tick)
	-- Default values: if no range is provided, load from the beginning to the current tick.
	start_tick = start_tick or 1
	end_tick = end_tick or self.tick
  
	local segment = {}
	local seg_length = 0
  
	for t = start_tick, end_tick do
	  if self.history_buffer[t] then
		seg_length = seg_length + 1
		segment[seg_length] = self.history_buffer[t]
	  end
	end
  
	return segment, seg_length
  end

-- Clear all buffers.
function Seq:clear()
  self.history_buffer   = {}
  self.recording_buffer = {}
  self.playback_buffer  = {}
  self.clip_bank        = {}
  self:emit('cleared')
end

-----------------------------------------------
-- Transport and Timing
-----------------------------------------------
-- The transport_event method is called on every clock or transport event.
-- (Data such as 'start', 'stop' and 'clock' are expected.)
function Seq:transport_event(data)
	if data.type == 'start' then
	  self.tick = 0
	  -- Only set playing to true if a playback buffer exists (i.e. a clip is loaded)
	  if self.playback_buffer and next(self.playback_buffer) then
		self.playing = true
	  else
		self.playing = false
	  end
	elseif data.type == 'stop' then
	  self.playing = false
	  -- On stop, if recording was in progress, quantize and finalize it.
	  if self.recording then
		self:quantize_recording()
		self.recording = false
	  end
	elseif data.type == 'clock' then
	  self.tick = self.tick + 1
	  -- Only process playback events if playing is enabled
	  if self.playing then
		local current_step = ((self.tick - 1) % self.length) + 1
		local events = self.playback_buffer[current_step]
		if events then
		  for _, event in ipairs(events) do
			self:emit('play_event', event)
		  end
		end
		-- Every full quantize period, process any pending arm actions.
		if (self.tick % self.segment_length) == 0 and self.armed then
		  self:arm_event()
		end
	  end
	end
	self:emit('transport_event', data)
	return data
  end

-----------------------------------------------
-- MIDI Event Processing
-----------------------------------------------
-- midi_event is called when a MIDI message is received.
-- Here we always record incoming MIDI events.
function Seq:midi_event(data)
  -- Always record the incoming event into the history (and recording if enabled)
  self:record_event(data)

  -- Optionally, if you want to pass through events immediately (when not looping),
  -- you can do so here. Otherwise, playback will come from the playback buffer.
  if (not self.playing) or self.track.midi_thru then
    return data
  end
  -- Otherwise, do not return data here (the sequencer handles playback via transport ticks).
end

-----------------------------------------------
-- Arm / Overdub / Save Actions
-----------------------------------------------
-- When an “arm” event occurs (for example, triggered by a grid pad), quantize the recording buffer,
-- optionally save it, or start overdubbing.
function Seq:arm_event()
  if self.armed then
    if self.recording then
      -- Quantize what has been recorded so far into the playback buffer.
      self:quantize_recording()
      -- (Optionally, immediately save to the current bank.)
      self:save_clip(nil, self.current_bank or 1)
    end
    self.armed = false
    self:emit('arm')
  end
end

-----------------------------------------------
-- Utility: Iterate Over Sequence Events
-----------------------------------------------
function Seq:for_each(func)
  local results = {}
  for step, events in pairs(self.playback_buffer) do
    for _, event in ipairs(events) do
      results[#results + 1] = func(event)
    end
  end
  return results
end

-----------------------------------------------
-- (Optional) Legacy Methods
-----------------------------------------------
-- If needed, you can keep a “get_step” method for retrieving events
function Seq:get_step(step, div)
  div = div or 1
  local out = {}
  for i = (step - 1) * div + 1, step * div do
    if self.playback_buffer[i] then
      for _, event in ipairs(self.playback_buffer[i]) do
        table.insert(out, event)
      end
    end
  end
  return out
end

return Seq