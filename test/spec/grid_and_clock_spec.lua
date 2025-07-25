package.path = './?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;;' .. package.path
require('norns')

describe('Grid and Clock Integration', function()
  local helpers = require('test.spec.support.helpers')
  
  -- Test Grid Event Translation
  describe('Grid Event Translation', function()
    local Grid = require('lib.grid')
    local grid
    
    before_each(function()
      grid = Grid:new({ width = 8, height = 8 })
    end)
    
    it('should translate grid coordinates to MIDI events', function()
      local x, y = 3, 4
      local event = grid:translate_to_midi(x, y, true) -- key down
      
      assert.is_not_nil(event)
      assert.equal('note_on', event.type)
      assert.is_not_nil(event.note)
      assert.is_not_nil(event.velocity)
    end)
    
    it('should handle grid key up events', function()
      local x, y = 3, 4
      local event = grid:translate_to_midi(x, y, false) -- key up
      
      assert.is_not_nil(event)
      assert.equal('note_off', event.type)
    end)
    
    it('should handle long press events', function()
      local x, y = 3, 4
      local event = grid:handle_long_press(x, y, 1000) -- 1 second press
      
      assert.is_not_nil(event)
      -- Should generate a different type of event for long press
    end)
    
    it('should handle sub-grid regions', function()
      local sub_grid = grid:create_sub_grid(0, 0, 4, 4)
      
      assert.is_not_nil(sub_grid)
      assert.equal(4, sub_grid.width)
      assert.equal(4, sub_grid.height)
    end)
  end)
  
  -- Test Clock-Driven Automation
  describe('Clock-Driven Automation', function()
    local Auto = require('lib.components.track.auto')
    local auto
    
    before_each(function()
      auto = Auto:new({ id = 1 })
      -- Stub clock functions for testing
      clock.run = function(fn) return fn end
      clock.sleep = function() end
      clock.get_beats = function() return 1.0 end
      clock.get_tempo = function() return 120 end
    end)
    
    it('should handle clock ticks for automation', function()
      auto:set_action(1, { type = 'cc', cc = 1, value = 64 })
      auto:set_action(2, { type = 'cc', cc = 1, value = 127 })
      
      -- Simulate clock ticks
      local result1 = auto:transport_event({ type = 'tick', beat = 1.0 })
      local result2 = auto:transport_event({ type = 'tick', beat = 2.0 })
      
      assert.is_not_nil(result1)
      assert.is_not_nil(result2)
    end)
    
    it('should handle tempo changes', function()
      auto:set_action(1, { type = 'tempo', value = 140 })
      
      local result = auto:transport_event({ type = 'tick', beat = 1.0 })
      assert.is_not_nil(result)
    end)
    
    it('should handle swing timing', function()
      auto.swing = 0.5
      auto.swing_div = 6 -- 1/16 note swing
      
      local result = auto:transport_event({ type = 'tick', beat = 1.5 })
      assert.is_not_nil(result)
    end)
    
    it('should handle automation curves', function()
      auto:set_action(1, { 
        type = 'cc', 
        cc = 1, 
        value = 64,
        curve = 'linear',
        duration = 4 -- 4 beats
      })
      
      -- Simulate multiple ticks over the curve duration
      for i = 1, 4 do
        local result = auto:transport_event({ type = 'tick', beat = i })
        assert.is_not_nil(result)
      end
    end)
  end)
  
  -- Test Transport Events
  describe('Transport Events', function()
    local Track = require('lib.components.app.track')
    local track
    
    before_each(function()
      track = Track:new({ id = 1 })
      track:add_component('input', { input_type = 'arpeggiator' })
      track:add_component('auto', {})
      track:add_component('output', { output_type = 'midi' })
    end)
    
    it('should handle transport start', function()
      local result = track:transport_event({ type = 'start' })
      assert.is_not_nil(result)
    end)
    
    it('should handle transport stop', function()
      local result = track:transport_event({ type = 'stop' })
      assert.is_not_nil(result)
    end)
    
    it('should handle transport continue', function()
      local result = track:transport_event({ type = 'continue' })
      assert.is_not_nil(result)
    end)
    
    it('should handle clock ticks', function()
      local result = track:transport_event({ type = 'tick', beat = 1.0 })
      assert.is_not_nil(result)
    end)
    
    it('should handle beat changes', function()
      local result = track:transport_event({ type = 'beat', beat = 1.0 })
      assert.is_not_nil(result)
    end)
  end)
  
  -- Test Mode System Integration
  describe('Mode System Integration', function()
    local Mode = require('lib.components.app.mode')
    local mode
    
    before_each(function()
      mode = Mode:new({ id = 1 })
    end)
    
    it('should handle mode switching', function()
      mode:set_mode('scale')
      
      assert.equal('scale', mode.current_mode)
    end)
    
    it('should handle grid events in different modes', function()
      mode:set_mode('scale')
      local result = mode:handle_grid_event(3, 4, true)
      assert.is_not_nil(result)
      
      mode:set_mode('note')
      local result2 = mode:handle_grid_event(3, 4, true)
      assert.is_not_nil(result2)
    end)
    
    it('should handle encoder events', function()
      mode:set_mode('scale')
      local result = mode:handle_encoder(1, 1)
      assert.is_not_nil(result)
    end)
    
    it('should handle key events', function()
      mode:set_mode('scale')
      local result = mode:handle_key(1, true)
      assert.is_not_nil(result)
    end)
  end)
  
  -- Test Device Manager Clock Integration
  describe('Device Manager Clock Integration', function()
    local DeviceManager = require('lib.components.app.devicemanager')
    local device_manager
    
    before_each(function()
      device_manager = DeviceManager:new()
    end)
    
    it('should handle clock-driven device updates', function()
      -- Register a mock device
      local mock_device = {
        id = 1,
        name = 'Test Device',
        clock_update = function(self, beat)
          return { type = 'clock_update', beat = beat }
        end
      }
      
      device_manager:register_device(mock_device)
      
      local result = device_manager:clock_event({ type = 'tick', beat = 1.0 })
      assert.is_not_nil(result)
    end)
    
    it('should handle device clock synchronization', function()
      local result = device_manager:sync_devices({ type = 'start' })
      assert.is_not_nil(result)
    end)
    
    it('should handle device tempo changes', function()
      local result = device_manager:set_tempo(140)
      assert.is_not_nil(result)
    end)
  end)
  
  -- Test Integration Scenarios
  describe('Integration Scenarios', function()
    local App = require('lib.app')
    local app
    
    before_each(function()
      app = App:new()
    end)
    
    it('should handle complete grid-to-MIDI workflow', function()
      -- Simulate grid press
      local grid_event = { x = 3, y = 4, pressed = true }
      
      -- Process through the complete chain
      local result = app:handle_grid_event(grid_event)
      
      assert.is_not_nil(result)
    end)
    
    it('should handle clock-driven automation workflow', function()
      -- Set up automation
      app.track[1].auto:set_action(1, { type = 'cc', cc = 1, value = 64 })
      
      -- Simulate clock tick
      local result = app:handle_clock_tick({ type = 'tick', beat = 1.0 })
      
      assert.is_not_nil(result)
    end)
    
    it('should handle mode switching with grid events', function()
      -- Switch to scale mode
      app:set_mode('scale')
      
      -- Handle grid event in scale mode
      local result = app:handle_grid_event({ x = 3, y = 4, pressed = true })
      
      assert.is_not_nil(result)
    end)
  end)
end) 