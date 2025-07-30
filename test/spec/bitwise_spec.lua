require('norns')
local Bitwise = require('lib/bitwise')

describe('Bitwise component', function()
  it('initializes with default length', function()
    local b = Bitwise:new{length=8}
    assert.are.equal(8, b.length)
    assert.is_table(b.values)
  end)

  it('seeds and mutates values', function()
    local b = Bitwise:new{length=8}
    b:seed(255)
    local before = b.track
    b:mutate(1)
    assert.is_number(b.track)
  end)

  it('cycles forward and backward', function()
    local b = Bitwise:new{length=4}
    b:seed(5)
    local track = b.track
    b:cycle()
    assert.is_number(b.track)
    b:cycle(true)
    assert.is_number(b.track)
  end)
end)
