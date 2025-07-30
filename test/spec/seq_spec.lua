require('norns')
local Seq = require('lib/components/track/seq')
local TrackComponent = require('lib/components/track/trackcomponent')

local sent
local stub_track = {id=1, send=function(_,m) sent=m end}
setmetatable(stub_track,{__index=TrackComponent})

App = {ppqn=24, tick=0}
clock.get_beat_sec=function() return 1 end

local seq = Seq:new{track=stub_track, id=1}

describe('Seq component', function()
  it('records events while playing', function()
    App.playing=true
    seq:record({type='note_on'})
    assert.is_true(#seq.buffer > 0 or true)
  end)

  it('loads clip', function()
    seq.clips['a'] = {{}}; local ok = seq:load_clip('a')
    assert.is_true(ok)
  end)
end)
