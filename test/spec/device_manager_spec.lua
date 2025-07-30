require('norns')
local DeviceManager = require('lib/components/app/devicemanager')

describe('DeviceManager basics', function()
  before_each(function()
    midi.vports = {{name='stub', send=function() end}}
    midi.connect = function() return {name='stub', send=function() end} end
  end)

  it('adds virtual device', function()
    local dm = DeviceManager:new()
    assert.is_table(dm.virtual)
  end)

  it('registers midi device', function()
    local dm = DeviceManager:new()
    assert.is_true(#dm.midi >= 1)
  end)
end)
