describe('Simple test', function()
  it('should pass', function()
    assert.is_true(true)
  end)
  
  it('should do basic math', function()
    assert.are.equal(4, 2 + 2)
  end)
  
  it('should handle strings', function()
    assert.are.equal('hello', 'hello')
  end)
end) 