require('norns')
local Grid = require('lib/grid')

local sent = {}
local stub_midi = { send = function(_, msg) table.insert(sent, msg) end }

describe('Grid component', function()
  it('initializes and sets LEDs', function()
    local g = Grid:new{midi=stub_midi}
    g:set_raw(1,1,1,true)
    assert.is_number(sent[1][1])
  end)

  it('updates bounds and refresh', function()
    local g = Grid:new{midi=stub_midi}
    g:update_bounds()
    g.led[1][1] = 15
    g:refresh()
    assert.is_table(sent[1])
  end)
end)
