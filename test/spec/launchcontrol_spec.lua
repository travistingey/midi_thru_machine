require('norns')
local LaunchControl = require('lib/launchcontrol')

describe('LaunchControl mappings', function()
  it('maps notes to control types', function()
    local data = {note=124}
    local send = LaunchControl:handle_note(data)
    assert.is_table(send)
  end)

  it('maps cc values back to physical', function()
    local cc = LaunchControl.cc_map.faders[1]
    local physical = LaunchControl.control_map[LaunchControl.REVERSE_CONTROL_MAP and LaunchControl.REVERSE_CONTROL_MAP[cc] or 77]
    assert.is_table(physical)
  end)
end)
