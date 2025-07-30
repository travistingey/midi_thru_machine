require('norns')
local Mode = require('lib/components/app/mode')
local TrackComponent = require('lib/components/track/trackcomponent')

App = {default={screen=function() end}, midi_grid={send=function() end}, screen_dirty=false}

local dummy_component = {
  grid = {process=function() end, subgrids={}, enable=function() end, disable=function() end},
  enable=function() end,
  disable=function() end
}

describe('Mode component', function()
  it('enables and disables', function()
    local m = Mode:new{id=1, components={dummy_component}}
    m:enable()
    assert.is_true(m.enabled)
    m:disable()
    assert.is_false(m.enabled)
  end)
end)
