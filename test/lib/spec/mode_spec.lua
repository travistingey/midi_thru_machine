local tf = require('FoobarTests/lib/test_framework')
local Mode = require('Foobar/lib/components/app/mode')
local TrackComponent = require('Foobar/lib/components/track/trackcomponent')

App = {default={screen=function() end}, midi_grid={send=function() end}, screen_dirty=false}

local dummy_component = {
  grid = {process=function() end, subgrids={}, enable=function() end, disable=function() end},
  enable=function() end,
  disable=function() end
}

tf.describe('Mode component', function()
  tf.it('enables and disables', function()
    local m = Mode:new{id=1, components={dummy_component}}
    m:enable()
    tf.assert.is_true(m.enabled)
    m:disable()
    tf.assert.is_false(m.enabled)
  end)
end)
