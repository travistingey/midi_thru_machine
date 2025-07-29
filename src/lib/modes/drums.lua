local Mode = require('Foobar/lib/components/app/mode')
local SeqGrid = require('Foobar/lib/components/mode/seqgrid')

local DrumsMode = Mode:new({
    id = 2,
    components = {SeqGrid:new({track=1})}
})

return DrumsMode