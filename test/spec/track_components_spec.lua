-- Track Components Test Suite
-- Tests individual track components and their integration

package.path = './?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;;' .. package.path
require('norns')

describe('Track Components', function()
  local helpers = require('test.spec.support.helpers')
  
  -- Test Input Component
  describe('Input Component', function()
    local Input = require('lib.components.track.input')
    local input
    
    before_each(function()
      input = Input:new({ id = 1 })
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
      input.arp_step = 0
      
      local result = input:transport_event({ type = 'tick', beat = 1 })
      assert.is_not_nil(result)
      assert.equal(1, input.arp_step)
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
      auto = Auto:new({ id = 1 })
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
      auto:clear_action(1)
      
      local result = auto:transport_event({ type = 'tick', beat = 1 })
      -- Should not generate any automation events
      assert.is_nil(result)
    end)
  end)
  
  -- Test Scale Component
  describe('Scale Component', function()
    local Scale = require('lib.components.track.scale')
    local scale
    
    before_each(function()
      scale = Scale:new({ id = 1 })
    end)
    
    it('should quantize notes correctly', function()
      scale:set_scale(0xAB5) -- Major scale
      scale.root = 0 -- C
      
      local event = { type = 'note_on', note = 61 } -- C#
      local result = scale:midi_event(event)
      
      assert.is_not_nil(result)
      -- Should quantize to C (60) or D (62) depending on implementation
    end)
    
    it('should handle scale following', function()
      scale.follow = true
      scale.follow_method = 'last_note'
      
      local event = { type = 'note_on', note = 65 } -- F
      local result = scale:midi_event(event)
      
      assert.is_not_nil(result)
      assert.equal(65 % 12, scale.root)
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
      mute = Mute:new({ id = 1 })
    end)
    
    it('should mute events when enabled', function()
      mute.muted = true
      
      local event = { type = 'note_on', note = 60 }
      local result = mute:midi_event(event)
      
      assert.is_nil(result) -- Should be muted
    end)
    
    it('should pass through events when not muted', function()
      mute.muted = false
      
      local event = { type = 'note_on', note = 60 }
      local result = mute:midi_event(event)
      
      assert.is_not_nil(result)
      assert.same(event, result)
    end)
    
    it('should handle conditional muting', function()
      mute.condition = function(event)
        return event.note and event.note > 65
      end
      
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
      output = Output:new({ id = 1 })
    end)
    
    it('should send MIDI events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = output:midi_event(event)
      
      assert.is_not_nil(result)
      -- In real environment, this would send to MIDI device
    end)
    
    it('should handle different output types', function()
      output.output_type = 'midi'
      output.midi_channel = 1
      
      local event = { type = 'note_on', note = 60, velocity = 100 }
      local result = output:midi_event(event)
      
      assert.is_not_nil(result)
      assert.equal(1, result.channel)
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
      seq = Seq:new({ id = 1 })
    end)
    
    it('should record MIDI events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      seq:midi_event(event)
      
      assert.is_not_nil(seq.recorded_events)
      assert.equal(1, #seq.recorded_events)
    end)
    
    it('should play back recorded events', function()
      local event = { type = 'note_on', note = 60, velocity = 100 }
      seq:midi_event(event)
      
      seq.playing = true
      local result = seq:transport_event({ type = 'tick', beat = 1 })
      
      assert.is_not_nil(result)
    end)
    
    it('should handle quantization', function()
      seq.quantize = true
      seq.quantize_grid = 0.25 -- 16th notes
      
      local event = { type = 'note_on', note = 60, velocity = 100, time = 0.1 }
      seq:midi_event(event)
      
      -- Should quantize to nearest grid position
      assert.is_not_nil(seq.recorded_events[1])
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
      track:add_component('mute', { muted = false })
      track:add_component('output', { output_type = 'midi', midi_channel = 1 })
      
      -- Send a transport event
      local result = track:transport_event({ type = 'tick', beat = 1 })
      
      -- Should process through the entire chain
      assert.is_not_nil(result)
    end)
    
    it('should handle MIDI events through the chain', function()
      track:add_component('input', { input_type = 'midi' })
      track:add_component('scale', { scale = 0xAB5, root = 0 })
      track:add_component('mute', { muted = false })
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