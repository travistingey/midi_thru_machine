require('norns')
local Output = require('lib/components/track/output')
local TrackComponent = require('lib/components/track/trackcomponent')

local sent
local stub_dev = {send = function(_, m) sent = m end}
local stub_track = {id=1, midi_out=1, output_device=stub_dev}
setmetatable(stub_track,{__index=TrackComponent})

local output = Output:new{track=stub_track, id=1, type='midi'}

describe('Output component', function()
  it('forwards midi events to device', function()
    output.types['midi'].midi_event(output, {type='note_on',note=60}, stub_track)
    assert.are.equal(60, sent.note)
  end)
end)
