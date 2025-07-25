package.path = './?.lua;./lib/?.lua;.test/stubs/?.lua;' .. package.path
require('norns')

local DeviceManager = require('lib/components/app/devicemanager')

describe('DeviceManager note handling', function()
  local stub_device, dm

  before_each(function()
    stub_device = {name='Stub', sent={}, event=nil}
    stub_device.send = function(_, msg)
      table.insert(stub_device.sent, msg)
    end
    -- override midi subsystem to return stub
    midi.vports = {stub_device}
    midi.connect = function(port) return stub_device end
    dm = DeviceManager:new()
  end)

  it('sends note_off when scale interrupt changes pitch', function()
    local dev = dm:get(1)
    dev:send{type='note_on', note=60, vel=64, ch=1}

    local scale = { quantize_note=function(_, data) return {new_note=data.note+1} end }
    dev:emit('interrupt', {type='interrupt_scale', scale=scale, ch=1})

    assert.are.equal(2, #stub_device.sent)
    assert.are.equal('note_on', stub_device.sent[1].type)
    assert.are.equal('note_off', stub_device.sent[2].type)
    assert.are.equal(60, stub_device.sent[2].note)
  end)

  it('ends previous note_on when same note_on arrives', function()
    local dev = dm:get(1)
    dev:send{type='note_on', note=62, vel=80, ch=1}
    dev:send{type='note_on', note=62, vel=90, ch=1}

    assert.are.equal(3, #stub_device.sent)
    assert.are.equal('note_on', stub_device.sent[1].type)
    assert.are.equal('note_off', stub_device.sent[2].type)
    assert.are.equal(62, stub_device.sent[2].note)
    assert.are.equal('note_on', stub_device.sent[3].type)
  end)
end)
