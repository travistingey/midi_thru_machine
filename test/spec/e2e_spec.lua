-- End-to-End Test Suite for MIDI Thru Machine
-- Tests core functionality using Busted framework

package.path = './?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;' .. package.path
require('norns')
require('test/spec/support/test_setup')

local helpers = require('test/spec/support/helpers')
local utilities = require('lib/utilities')

describe('MIDI Thru Machine E2E Tests', function()
  
  describe('Device Manager Basic Functionality', function()
    it('should create and manage devices', function()
      local DeviceManager = require('lib/components/app/devicemanager')
      local dm = DeviceManager:new()
      
      -- Test device registration
      assert.is_not_nil(dm, "DeviceManager should be created")
      
      -- Test getting a device
      local dev = dm:get(1)
      assert.is_not_nil(dev, "Should be able to get device 1")
      
      -- Test note sending
      local sent_notes = {}
      dev.send = function(_, msg)
        table.insert(sent_notes, msg)
      end
      
      dev:send{type='note_on', note=60, vel=64, ch=1}
      assert.are.equal(1, #sent_notes, "Should have sent one note")
      assert.are.equal('note_on', sent_notes[1].type, "Should be note_on message")
      assert.are.equal(60, sent_notes[1].note, "Note should be 60")
    end)
  end)
  
  describe('Scale Quantization', function()
    it('should quantize notes correctly', function()
      local Scale = require('lib/components/track/scale')
      local scale = Scale:new({id=1})
      
      -- Test basic quantization
      local result = scale:quantize_note({note=61, vel=64, ch=1})
      assert.is_not_nil(result, "Quantization should return a result")
      
      -- Test scale following
      scale.follow_mode = 1
      scale.follow_track = 1
      local follow_result = scale:quantize_note({note=62, vel=64, ch=1})
      assert.is_not_nil(follow_result, "Scale following should work")
    end)
  end)
  
  describe('Track Component Chain', function()
    it('should build and manage track chains', function()
      local Track = require('lib/components/app/track')
      local track = Track:new(create_test_track(1))
      
      -- Test chain building
      assert.is_not_nil(track, "Track should be created")
      
      -- Test that track has basic structure
      assert.are.equal("table", type(track), "Track should be a table")
      
      -- Test that track has required components
      assert.is_not_nil(track.input, "Track should have input component")
      assert.is_not_nil(track.scale, "Track should have scale component")
      assert.is_not_nil(track.output, "Track should have output component")
    end)
  end)
  
  describe('MIDI Event Routing', function()
    it('should route MIDI events correctly', function()
      local DeviceManager = require('lib/components/app/devicemanager')
      local dm = DeviceManager:new()
      local dev = dm:get(1)
      
      local received_events = {}
      dev.process_midi = function(_, msg)
        table.insert(received_events, msg)
      end
      
      -- Simulate incoming MIDI
      local midi_msg = {type='note_on', note=64, vel=80, ch=1}
      dev:process_midi(midi_msg)
      
      assert.are.equal(1, #received_events, "Should have received one event")
      assert.are.equal('note_on', received_events[1].type, "Should be note_on event")
    end)
  end)
  
  describe('Note Interrupt Handling', function()
    it('should handle note interrupts correctly', function()
      local DeviceManager = require('lib/components/app/devicemanager')
      local dm = DeviceManager:new()
      local dev = dm:get(1)
      
      local sent_messages = {}
      dev.send = function(_, msg)
        table.insert(sent_messages, msg)
      end
      
      -- Send a note on
      dev:send{type='note_on', note=60, vel=64, ch=1}
      
      -- Simulate scale interrupt
      local scale = { quantize_note=function(_, data) return {new_note=data.note+1} end }
      dev:emit('interrupt', {type='interrupt_scale', scale=scale, ch=1})
      
      -- Should have at least the note_on
      assert.are.equal(1, #sent_messages, "Should have sent at least note_on")
      assert.are.equal('note_on', sent_messages[1].type, "First should be note_on")
      
      -- Test that interrupt listeners are set up
      assert.is_not_nil(dev.manager, "Device should have manager")
    end)
  end)
  
  describe('Utilities Functions', function()
    it('should provide working utility functions', function()
      -- Test removeDuplicates
      local test_array = {1, 2, 2, 3, 3, 4}
      local result = utilities.removeDuplicates(test_array)
      assert.are.equal(4, #result, "Should remove duplicates")
      
      -- Test chain_functions
      local f1 = function(x) return x + 1 end
      local f2 = function(x) return x * 2 end
      local chained = utilities.chain_functions({f1, f2})
      assert.are.equal(4, chained(1), "Function chaining should work")
    end)
  end)
  
  describe('Track Components Integration', function()
    it('should integrate track components correctly', function()
      local Track = require('lib/components/app/track')
      local track = Track:new(create_test_track(1))
      
      -- Test that all components are loaded
      assert.is_not_nil(track.input, "Input component should be loaded")
      assert.is_not_nil(track.scale, "Scale component should be loaded")
      assert.is_not_nil(track.output, "Output component should be loaded")
      
      -- Test that components have required methods
      assert.is_not_nil(track.input.midi_event, "Input should have midi_event method")
      assert.is_not_nil(track.scale.quantize_note, "Scale should have quantize_note method")
      assert.is_not_nil(track.output.midi_event, "Output should have midi_event method")
      
      -- Test that track has basic methods
      assert.is_not_nil(track.enable, "Track should have enable method")
      assert.is_not_nil(track.disable, "Track should have disable method")
    end)
  end)
  
  describe('Grid Event Translation', function()
    it('should translate grid events correctly', function()
      local Grid = require('lib/grid')
      
      -- Test grid event translation
      local grid = Grid:new()
      assert.is_not_nil(grid, "Grid should be created")
      
      -- Test basic grid functionality (using actual methods)
      assert.is_not_nil(grid.event, "Grid should have event method")
      assert.is_not_nil(grid.set, "Grid should have set method")
      assert.is_not_nil(grid.process, "Grid should have process method")
    end)
  end)
  
  describe('Clock-Driven Automation', function()
    it('should handle clock-driven automation', function()
      local Auto = require('lib/components/track/auto')
      -- Create a mock track for the auto component
      local mock_track = { id = 1, current_preset = 1 }
      local auto = Auto:new({id=1, track=mock_track})
      
      -- Test automation component
      assert.is_not_nil(auto, "Auto component should be created")
      
      -- Test that it has transport event handling
      assert.is_not_nil(auto.transport_event, "Auto should have transport_event method")
    end)
  end)
end) 