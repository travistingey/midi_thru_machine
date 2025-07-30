-- Minimal test that should definitely work
local tf = require('FoobarTests/lib/test_framework')

tf.describe('Minimal test', function()
  tf.it('should pass', function()
    tf.assert.is_true(true)
  end)
end) 