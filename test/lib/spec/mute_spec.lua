local tf = require('FoobarTests/lib/test_framework')
local Mute = require('Foobar/lib/components/track/mute')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

local stub_track = {id=1, triggered=false}
setmetatable(stub_track, {__index=TrackComponent})

local mute = Mute:new{track=stub_track,id=1}

App = {ppqn=24}

mute.grid = { } -- dummy

tf.describe('Mute component', function()
  tf.it('passes through unmuted notes', function()
    local msg = mute:midi_event{type='note_on', note=60}
    tf.assert.are.same('note_on', msg.type)
  end)

  tf.it('blocks muted notes', function()
    mute.state[60] = true
    local msg = mute:midi_event{type='note_on', note=60}
    tf.assert.is_nil(msg)
  end)
end)
