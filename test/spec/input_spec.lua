require('norns')
local Input = require('lib/components/track/input')
local TrackComponent = require('lib/components/track/trackcomponent')

local stub_track = {id=1, step=0, midi_in=1, trigger=60, note_range_lower=60, note_range_upper=72, step_count=0, reset_step=0}
setmetatable(stub_track, {__index=TrackComponent})

function stub_track:send_input(msg) self.last=msg end

App = {ppqn=24, tick=0, scale={}, crow={query=function() end, input={{},{}}}}

local input = Input:new{track=stub_track, id=1}

describe('Input component', function()
  it('handles midi_trigger note_on/off', function()
    input:midi_trigger{type='note_on', ch=1, note=60, vel=100}
    assert.is_table(stub_track.last)
    input:midi_trigger{type='note_off', ch=1, note=60, vel=100}
    assert.is_equal('note_off', stub_track.last.type)
  end)
end)
