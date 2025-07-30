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

		local current_time = os.clock()
		local time_diff = current_time - self.last_tick
    print('recording time diff', time_diff)
		print('average tick', clock.get_beat_sec())

		if not self.buffer[step] then
			self.buffer[step] = {}
		end
		table.insert(self.buffer[step], data)
	end
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
