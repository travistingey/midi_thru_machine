local tf = require('FoobarTests/lib/test_framework')
local DeviceManager = require('Foobar/lib/components/app/devicemanager')

tf.describe('DeviceManager basics', function()
  tf.it('adds virtual device', function()
    local dm = DeviceManager:new()
    tf.assert.is_table(dm.virtual)
  end)

  tf.it('registers midi device', function()
    local dm = DeviceManager:new()
    tf.assert.is_true(#dm.midi >= 1)
  end)
end)
