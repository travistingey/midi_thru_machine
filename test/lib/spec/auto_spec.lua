local tf = require('FoobarTests/lib/test_framework')
local Auto = require('Foobar/lib/components/track/auto')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

-- stub track with midi_out send
local stub_track = {id=1, midi_out=1, output_device={send=function() end}}
setmetatable(stub_track, {__index=TrackComponent})

tf.describe('Auto component', function()
  tf.it('stores and toggles actions', function()
    local a = Auto:new{track=stub_track, id=1}
    a:set_action(1,'track', {type='track', value=2})
    tf.assert.is_table(a:get_action(1,'track'))
    local last = a:toggle_action(1,{type='track', value=2})
    tf.assert.is_table(last)
  end)
end)
