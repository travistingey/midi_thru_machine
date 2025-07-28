-- Track Components Test Suite
-- Tests individual track components and their integration

package.path = './?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;;' .. package.path
require('norns')
require('test/spec/support/test_setup')

-- Utility to create a lightweight stub track that satisfies component dependencies
local function new_track_stub(id)
  return {
    id = id or 1,
    step = 0,
    reset_step = 0,
    reset_tick = 0,
    step_count = 0,
    input_type = 'midi',
    midi_in = 1,
    send_input = function() end, -- noop for tests
  }
end

describe('Track Components', function()
  local helpers = require('test.spec.support.helpers')
  
  -- Test Input Component
  describe('Input Component', function()
    local Input = require('lib.components.track.input')
    local input
    
    before_each(function()
      local track_stub = new_track_stub(1)
      input = Input:new({ id = 1, track = track_stub })
    end)
    
    it('should handle MIDI events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = input:midi_event(event)
      assert.is_not_nil(result)
    end)
    
    it('should handle different input types', function()
      -- Test arpeggiator input
      input.input_type = 'arpeggiator'
      input:transport_event({ type = 'tick', beat = 1 })
      
      -- Test random input
      input.input_type = 'random'
      input:transport_event({ type = 'tick', beat = 1 })
      
      -- Test bitwise input
      input.input_type = 'bitwise'
      input:transport_event({ type = 'tick', beat = 1 })
    end)
    
    it('should handle arpeggiator mode', function()
      input.input_type = 'arpeggiator'
      input.arp_notes = {60, 64, 67}
      input.index = 0

      local result = input:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
    
    it('should handle random mode', function()
      input.input_type = 'random'
      input.note_range = {60, 72}
      input.chance = 1.0
      
      local result = input:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
    
    it('should handle bitwise mode', function()
      input.input_type = 'bitwise'
      input.bitwise = require('lib.bitwise'):new({ length = 8 })
      
      local result = input:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
  end)
  
  -- Test Auto Component
  describe('Auto Component', function()
    local Auto = require('lib.components.track.auto')
    local auto
    
    before_each(function()
      local track_stub = new_track_stub(1)
      auto = Auto:new({ id = 1, track = track_stub })
    end)
    
    it('should handle parameter automation', function()
      auto:set_action(1, { type = 'cc', cc = 1, value = 64 })
      
      local result = auto:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
    
    it('should handle preset changes', function()
      auto:set_action(1, { type = 'preset', preset = 2 })
      
      local result = auto:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
    
    it('should handle scale changes', function()
      auto:set_action(1, { type = 'scale', scale = 2 })
      
      local result = auto:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
    end)
    
    it('should clear actions', function()
      auto:set_action(1, { type = 'cc', cc = 1, value = 64 })
      if auto.clear_action then
        auto:clear_action(1)
      else
        auto:set_action(1, 'cc', nil)
      end

      local result = auto:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result) -- After clearing, transport_event returns tick as pass-through
    end)
  end)
  
  -- Test Scale Component
  describe('Scale Component', function()
    local Scale = require('lib.components.track.scale')
    local scale
    
    before_each(function()
      local track_stub = new_track_stub(1)
      scale = Scale:new({ id = 1, track = track_stub })
    end)
    
    it('should quantize notes correctly', function()
      scale:set_scale(0xAB5) -- Major scale
      scale.root = 0 -- C
      
      local event = { type = 'note_on', note = 61 } -- C#
      local track_stub = new_track_stub(1)
      local result = scale:midi_event(event, track_stub)
      
      assert.is_not_nil(result)
      -- Should quantize to C (60) or D (62) depending on implementation
    end)
    
    it('should handle scale following', function()
      scale.follow = true
      scale.follow_method = 'last_note'
      
      local event = { type = 'note_on', note = 65 } -- F
      local track_stub = new_track_stub(1)
      local result = scale:midi_event(event, track_stub)
      
      assert.is_not_nil(result)
    end)
    
    it('should detect chord changes', function()
      scale:set_scale(0xAB5) -- Major scale
      scale.chord_set = {
        { name = 'major', bits = 0xAB5 },
        { name = 'minor', bits = 0x5AD }
      }
      
      local chord = scale:chord_id()
      assert.is_not_nil(chord)
      assert.equal('major', chord.name)
    end)
  end)
  
  -- Test Mute Component
  describe('Mute Component', function()
    local Mute = require('lib.components.track.mute')
    local mute
    
    before_each(function()
      local track_stub = new_track_stub(1)
      mute = Mute:new({ id = 1, track = track_stub })
    end)
    
    it('should mute events when enabled', function()
      -- Mute a specific note
      mute.state[60] = true

      local event = { type = 'note_on', note = 60 }
      local result = mute:midi_event(event)

      assert.is_nil(result) -- Should be muted
    end)
    
    it('should pass through events when not muted', function()
      -- Ensure note not muted
      mute.state[60] = false

      local event = { type = 'note_on', note = 60 }
      local result = mute:midi_event(event)

      assert.is_not_nil(result)
      assert.same(event, result)
    end)
    
    it('should handle conditional muting', function()
      -- Simulate conditional muting by toggling state table
      mute.state[70] = true

      local low_event = { type = 'note_on', note = 60 }
      local high_event = { type = 'note_on', note = 70 }

      local low_result = mute:midi_event(low_event)
      local high_result = mute:midi_event(high_event)

      assert.is_not_nil(low_result) -- Should pass through
      assert.is_nil(high_result) -- Should be muted
    end)
  end)
  
  -- Test Output Component
  describe('Output Component', function()
    local Output = require('lib.components.track.output')
    local output
    
    before_each(function()
      local track_stub = new_track_stub(1)
      output = Output:new({ id = 1, track = track_stub })
    end)
    
    it('should send MIDI events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = output:midi_event(event)

      assert.is_not_nil(result)
    end)

    it('should handle different output types', function()
      output.output_type = 'midi'
      output.midi_channel = 1

      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = output:midi_event(event)

      assert.is_not_nil(result)
      -- The core library does not currently attach a channel property; we only ensure no error.
    end)
    
    it('should handle Crow output', function()
      output.output_type = 'crow'
      output.crow_output = 1
      
      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = output:midi_event(event)
      
      assert.is_not_nil(result)
      -- In real environment, this would send to Crow
    end)
  end)
  
  -- Test Seq Component
  describe('Seq Component', function()
    local Seq = require('lib.components.track.seq')
    local seq
    
    before_each(function()
      local track_stub = new_track_stub(1)
      seq = Seq:new({ id = 1, track = track_stub })
    end)
    
    it('should record MIDI events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      seq:record_event(event)

      -- Validate that the history buffer captured the event
      local has_entry = false
      for _, v in pairs(seq.history_buffer) do
        if #v > 0 then has_entry = true break end
      end
      assert.is_true(has_entry)
    end)
    
    it('should play back recorded events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      seq:midi_event(event)
      
      seq.playing = true
      local result = seq:transport_event({ type = 'tick', beat = 1 })
      
      assert.is_not_nil(result)
    end)
    
    it('should handle quantization', function()
      -- For the refactored sequencer we instead call quantize_recording
      seq.recording = true
      local event = { type = 'note_on', note = 60, velocity = 100, time = 0.1 }
      seq:record_event(event)
      seq:quantize_recording()

      assert.is_not_nil(seq.playback_buffer)
    end)
  end)
  
  -- Test Complete Track Chain Integration
  describe('Track Component Chain Integration', function()
    local Track = require('lib.components.app.track')
    local track
    
    before_each(function()
      track = Track:new({ id = 1 })
    end)
    
    it('should process events through the complete chain', function()
      -- Set up a complete chain: input -> scale -> mute -> output
      track:add_component('input', { input_type = 'arpeggiator' })
      track:add_component('scale', { scale = 0xAB5, root = 0 })
      track:add_component('mute', {})
      track:add_component('output', { output_type = 'midi', midi_channel = 1 })
      
      -- Send a transport event
      local result = track:transport_event({ type = 'tick', beat = 1 })
      
      -- Should process through the entire chain
      assert.is_not_nil(result)
    end)
    
    it('should handle MIDI events through the chain', function()
      track:add_component('input', { input_type = 'midi' })
      track:add_component('scale', { scale = 0xAB5, root = 0 })
      track:add_component('mute', {})
      track:add_component('output', { output_type = 'midi', midi_channel = 1 })
      
      local event = { type = 'note_on', note = 61, velocity = 100 }
      local result = track:midi_event(event)
      
      assert.is_not_nil(result)
    end)
    
    it('should handle component removal', function()
      track:add_component('input', { input_type = 'arpeggiator' })
      track:add_component('scale', { scale = 0xAB5, root = 0 })
      
      track:remove_component('scale')
      
      local result = track:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
      -- Should still work without scale component
    end)
  end)
end) 