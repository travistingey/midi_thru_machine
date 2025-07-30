require('norns')
local Mute = require('lib/components/track/mute')
local TrackComponent = require('lib/components/track/trackcomponent')

local stub_track = {id=1, triggered=false}
setmetatable(stub_track, {__index=TrackComponent})

local mute = Mute:new{track=stub_track,id=1}

App = {ppqn=24}

mute.grid = { } -- dummy

describe('Mute component', function()
  it('passes through unmuted notes', function()
    local msg = mute:midi_event{type='note_on', note=60}
    assert.are.same('note_on', msg.type)
  end)

  it('blocks muted notes', function()
    mute.state[60] = true
    local msg = mute:midi_event{type='note_on', note=60}
    assert.is_nil(msg)
  end)
end)
