local tf = require('FoobarTests/lib/test_framework')
local DeviceManager = require('Foobar/lib/components/app/devicemanager')

tf.describe('DeviceManager note handling', function()
  local stub_device, dm, original_midi_vports, original_midi_connect

  tf.before_each(function()
    stub_device = {name='Stub', sent={}, event=nil}
    stub_device.send = function(_, msg)
      table.insert(stub_device.sent, msg)
    end
    
    -- Store original MIDI functions safely
    original_midi_vports = midi.vports
    original_midi_connect = midi.connect
    
    -- Create a safe stub that doesn't break the global system
    local stub_midi = {
      vports = {stub_device},
      connect = function(port) return stub_device end
    }
    
    -- Temporarily replace midi functions for this test only
    midi.vports = stub_midi.vports
    midi.connect = stub_midi.connect
    
    dm = DeviceManager:new()
  end)

  tf.after_each(function()
    -- Restore original MIDI functions safely
    if original_midi_vports then
      midi.vports = original_midi_vports
    end
    if original_midi_connect then
      midi.connect = original_midi_connect
    end
  end)

  tf.it('sends note_off when scale interrupt changes pitch', function()
    local dev = dm:get(1)
    dev:send{type='note_on', note=60, vel=64, ch=1}

    local scale = { quantize_note=function(_, data) return {new_note=data.note+1} end }
    dev:emit('interrupt', {type='interrupt_scale', scale=scale, ch=1})

    tf.assert.are.equal(2, #stub_device.sent)
    tf.assert.are.equal('note_on', stub_device.sent[1].type)
    tf.assert.are.equal('note_off', stub_device.sent[2].type)
    tf.assert.are.equal(60, stub_device.sent[2].note)
  end)

  tf.it('ignores scale interrupt when pitch class is unchanged', function()
    local dev = dm:get(1)
    dev:send{type='note_on', note=60, vel=64, ch=1}

    local scale = { quantize_note=function(_, data) return {new_note=data.note+12} end }
    dev:emit('interrupt', {type='interrupt_scale', scale=scale, ch=1})

    tf.assert.are.equal(1, #stub_device.sent)
    tf.assert.are.equal('note_on', stub_device.sent[1].type)
  end)

  tf.it('ends previous note_on when same note_on arrives', function()
    local dev = dm:get(1)
    dev:send{type='note_on', note=62, vel=80, ch=1}
    dev:send{type='note_on', note=62, vel=90, ch=1}

    tf.assert.are.equal(3, #stub_device.sent)
    tf.assert.are.equal('note_on', stub_device.sent[1].type)
    tf.assert.are.equal('note_off', stub_device.sent[2].type)
    tf.assert.are.equal(62, stub_device.sent[2].note)
    tf.assert.are.equal('note_on', stub_device.sent[3].type)
  end)
end)
