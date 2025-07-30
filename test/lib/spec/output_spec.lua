local tf = require('FoobarTests/lib/test_framework')
local Output = require('Foobar/lib/components/track/output')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

local sent
local stub_dev = {send = function(_, m) sent = m end}
local stub_track = {id=1, midi_out=1, output_device=stub_dev}
setmetatable(stub_track,{__index=TrackComponent})

local output = Output:new{track=stub_track, id=1, type='midi'}

tf.describe('Output component', function()
  tf.it('forwards midi events to device', function()
    output.types['midi'].midi_event(output, {type='note_on',note=60}, stub_track)
    tf.assert.are.equal(60, sent.note)
  end)
end)
