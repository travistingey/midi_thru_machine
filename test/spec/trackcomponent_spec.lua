require('norns')
local TrackComponent = require('lib/components/track/trackcomponent')

describe('TrackComponent base', function()
  it('emits and listens to events', function()
    local t = TrackComponent:new{}
    local count = 0
    t:on('ping', function() count = count + 1 end)
    t:emit('ping')
    assert.are.equal(1, count)
    t:emit('ping')
    assert.are.equal(2, count)
  end)
end)
