local tf = require('FoobarTests/lib/test_framework')
local Bitwise = require('Foobar/lib/bitwise')

tf.describe('Bitwise component', function()
  tf.it('initializes with default length', function()
    local b = Bitwise:new{length=8}
    tf.assert.are.equal(8, b.length)
    tf.assert.is_table(b.values)
  end)

  tf.it('seeds and mutates values', function()
    local b = Bitwise:new{length=8}
    b:seed(255)
    local before = b.track
    b:mutate(1)
    tf.assert.is_number(b.track)
  end)

  tf.it('cycles forward and backward', function()
    local b = Bitwise:new{length=4}
    b:seed(5)
    local track = b.track
    b:cycle()
    tf.assert.is_number(b.track)
    b:cycle(true)
    tf.assert.is_number(b.track)
  end)
end)
