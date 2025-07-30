local tf = require('FoobarTests/lib/test_framework')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

tf.describe('TrackComponent base', function()
  tf.it('emits and listens to events', function()
    local t = TrackComponent:new()
    local count = 0
    t:on('ping', function() count = count + 1 end)
    t:emit('ping')
    tf.assert.are.equal(1, count)
    t:emit('ping')
    tf.assert.are.equal(2, count)
  end)
end)
