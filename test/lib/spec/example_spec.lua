local tf = require('FoobarTests/lib/test_framework')

tf.describe('utilities', function() 
  local u = require('../Foobar/lib/utilities')

  tf.it('removes duplicate entries', function()
    tf.assert.are.same({1,2,3}, u.removeDuplicates({1,2,2,3}))
  end)

  tf.it('chains functions left-to-right', function()
    local f = u.chain_functions({function(x) return x + 1 end, function(x) return x * 2 end})
    tf.assert.are.equal(4, f(1))
  end)
end)
