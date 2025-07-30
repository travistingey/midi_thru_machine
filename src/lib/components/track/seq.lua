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
local path_name = "Foobar/lib/"
local utilities = require(path_name .. "utilities")

-- Lightweight recursive table copy (avoids GC spikes vs. util.table_copy on huge buffers)
local function deep_copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do
    c[k] = deep_copy(v)
  end
  return c
end
local Grid = require(path_name .. "grid")
local TrackComponent = require("Foobar/lib/components/track/trackcomponent")

local Seq = {}
Seq.name = "seq"
Seq.__index = Seq
setmetatable(Seq, { __index = TrackComponent })

-----------------------------------------------
-- Constructor & Initialization
-----------------------------------------------
function Seq:new(o)
	o = o or {}
	setmetatable(o, self)
	TrackComponent.set(o, o)
	o:set(o)
	return o
end

function Seq:set(o)
	-- Basic identification and timing
	self.id = self.id or 1
	self.step = 0
	self.last_tick = 0
	self.buffer = o.buffer or {}
	self.buffer_length = o.buffer_length or App.ppqn * 124

	self.playback_buffer = o.playback_buffer or {}
	self.playback_length = o.playback_length or App.ppqn * 4 -- length of clip in ticks
	self.playback_start = o.playback_start or 0 -- start of clip in ticks
	self.playback_end = o.playback_end or self.playback_length -- end of clip in ticks
	self.playback_loop = o.playback_loop or true -- loop the clip

  -- In‑memory clip library (saved buffers / presets)
  self.clips = o.clips or {}

	-- Recording/playback/arm state flags
	self.playing = false
	self.overdub = false

	self.track:on("midi_send", function(data)
		self:record(data)
	end)
end

-- -- Quantize the recording buffer (if needed) and move its contents into the playback buffer.
-- -- For simplicity, this example simply copies over the events, remapping their tick values.
-- function Seq:quantize_recording()
--   local quantized = {}
--   for step, events in pairs(self.recording_buffer) do
--     quantized[step] = {}
--     for _, event in ipairs(events) do
--       local q_event = {}
--       for k, v in pairs(event) do q_event[k] = v end
--       -- Set the event’s tick relative to the clip (step number)
--       q_event.tick = step
--       table.insert(quantized[step], q_event)
--     end
--   end
--   self.playback_buffer = quantized
--   self.length = self.segment_length  -- update playback loop length accordingly
--   self.recording_buffer = {}         -- clear recording buffer after quantizing
--   -- Emit an event to notify listeners that quantization is complete.
--   self:emit('quantized', self.playback_buffer)
-- end

-----------------------------------------------
-- Record Events
-----------------------------------------------
function Seq:record(data)
	if App.playing then
		local step = App.tick % self.buffer_length

		local tick_len = clock.get_beat_sec() / App.ppqn 

		local dt = os.clock() - self.last_tick 
		local offset = (dt / tick_len) - 1 
		offset = util.clamp(offset, -0.5, 0.5)

		if not self.buffer[step] then
			self.buffer[step] = {}
		end
		table.insert(self.buffer[step], {data = data, off = offset})
	end
end

function Seq:run(step)
  local events   = self.playback_buffer[step]
  if not events then return end

  local tick_len = clock.get_beat_sec() / App.ppqn
  for _, ev in ipairs(events) do
    if ev.off ~= 0 then
      clock.run(function()
        clock.sleep(ev.off * tick_len)
        self.track:send(ev.data)
      end)
    else
      self.track:send(ev.data)
    end
  end
end


-----------------------------------------------
-- Clip / Preset Handling (non‑blocking)
-----------------------------------------------
-- Save a region of the circular history buffer into self.clips[name].
-- Copy is chunked inside a clock coroutine so UI/audio never hitch.
--  * name        : string key for the clip library
--  * first_step  : starting tick index (defaults to 0)
--  * length      : number of ticks to copy (defaults to full buffer_length)
--  * chunk       : ticks copied before yielding (defaults to 128)
function Seq:save_clip(name, first_step, length, chunk)
  assert(name, "Seq:save_clip requires a name")
  first_step = first_step or 0
  length     = length     or self.buffer_length
  chunk      = chunk      or 128

  -- Reserve slot so callers can check existence while copy runs
  self.clips[name] = {}
  local dst = self.clips[name]

  clock.run(function()
    for i = 0, length - 1 do
      local src = (first_step + i) % self.buffer_length
      if self.buffer[src] then
        dst[i + 1] = deep_copy(self.buffer[src])
      end
      if i % chunk == 0 then
        clock.sleep(0)        -- yield to scheduler, avoids audio dropouts
      end
    end
    -- Notify listeners when finished
    self:emit("clip_saved", name, dst)
  end)
end

-- Quickly load a saved clip into playback; cheap because we just re‑point.
function Seq:load_clip(name)
  local clip = self.clips and self.clips[name]
  if not clip then return false end
  self.playback_buffer = clip
  self.playback_length = #clip
  self.step = 0
  self:emit("clip_loaded", name, clip)
  return true
end


function Seq:set_loop(loop_start, loop_end)
	self.playback_start = loop_start
	self.playback_end = loop_end
end

-----------------------------------------------
-- Transport and Timing
-----------------------------------------------
-- Transport Event Handling
function Seq:transport_event(data)
	if data.type == "start" then
		self.last_tick = os.clock()
		self.step = 0
	elseif data.type == "stop" then
		self.playing = false
	elseif data.type == "clock" then
		self.last_tick = os.clock()
		if self.playing and self.playback_buffer[self.step] then
			self:run(self.step)
		end

		-- Calculate the next step
		local next_step = self.step + 1

		if next_step >= self.playback_start + self.playback_length then
			next_step = self.playback_start
			self.step = self.playback_start
		else
			self.step = next_step
		end
	end

	return data
end

-----------------------------------------------
-- MIDI Event Processing
-----------------------------------------------
function Seq:midi_event(data)
	-- we will need to perform note handling when input
	return data
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

return Seq
