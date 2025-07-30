local tf = require('FoobarTests/lib/test_framework')
local LaunchControl = require('Foobar/lib/launchcontrol')

tf.describe('LaunchControl mappings', function()
  tf.it('maps notes to control types', function()
    local data = {note=124}
    local send = LaunchControl:handle_note(data)
    tf.assert.is_table(send)
  end)

  tf.it('maps cc values back to physical', function()
    local cc = LaunchControl.cc_map.faders[1]
    local physical = LaunchControl.control_map[LaunchControl.REVERSE_CONTROL_MAP and LaunchControl.REVERSE_CONTROL_MAP[cc] or 77]
    tf.assert.is_table(physical)
  end)
end)
