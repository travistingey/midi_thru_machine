package.path = './?.lua;./lib/?.lua;test/.test/stubs/?.lua;' .. package.path
require('norns')

describe('utilities', function()
  local u = require('lib/utilities')

  it('removes duplicate entries', function()
    assert.are.same({1,2,3}, u.removeDuplicates({1,2,2,3}))
  end)

  it('chains functions left-to-right', function()
    local f = u.chain_functions({function(x) return x + 1 end, function(x) return x * 2 end})
    assert.are.equal(4, f(1))
  end)
end)
