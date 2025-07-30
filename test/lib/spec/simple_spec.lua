local tf = require('FoobarTests/lib/test_framework')

tf.describe('Simple test', function()
  tf.it('should pass', function()
    tf.assert.is_true(true)
  end)
  
  tf.it('should do basic math', function()
    tf.assert.are.equal(4, 2 + 2)
  end)
  
  tf.it('should handle strings', function()
    tf.assert.are.equal('hello', 'hello')
  end)
end) 