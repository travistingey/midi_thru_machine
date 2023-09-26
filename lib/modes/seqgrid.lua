local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')

local SeqGrid = ModeComponent:new()
SeqGrid.__base = ModeComponent
SeqGrid.name = 'Mode Name'

function SeqGrid:set(o)
	self.__base.set(self, o) -- call the base set method first   
    
    o.component = 'seq'
    o.page = 1
    o.register = {'on_load'}

    o.grid = Grid:new({
        name = 'Sequence ' .. o.track,
        grid_start = {x=1,y=128},
        grid_end = {x=8,y=1},
        display_start = o.display_start or {x=1,y=41},
        display_end = o.display_end or {x=8,y=48},
        offset = o.offset or {x=0,y=0},
        midi = App.midi_grid
    })

end

function SeqGrid:transport_event(seq,data)
    self:set_grid(seq)
end

function SeqGrid:grid_event (seq,data)
    local grid = self.grid
	local wrap = 8
	local page_count = math.ceil( math.ceil(seq.length/seq.div) / wrap)
	
	if data.state and data.type == 'right' and self.page < page_count then
		
		 if App.alt then
	        seq.follow = not seq.follow
	        App.alt_pad:reset()
	    else
		    self.page = self.page + 1
		    print('page: ' .. self.page)
		 end
	    
	end

	if data.state and data.type == 'left' and self.page > 1 then
		  if App.alt then
	        self.page = 1
	        App.alt_pad:reset()
	    else
		    self.page = self.page - 1
		  end
		  	print('page: ' .. self.page)
	end

	
	

	if data.state and data.type == 'down' then
		 if App.alt then
	        if seq.div > 3 then
	        	seq.div = seq.div / 2
	        elseif seq.div > 2 then
           		seq.div = seq.div - 1
	        end
			page_count = math.ceil( math.ceil(seq.length/seq.div) / wrap)
			if self.page > page_count then self.page = page_count end

	    elseif grid.display_end.y > grid.grid_end.y and grid.display_start.y > 1 and grid.display_start.y > seq.track.note_range_lower + 1  then
    		
				grid.display_start.y = grid.display_start.y - 1
    			grid.display_end.y = grid.display_end.y - 1
		  end
	end

	if data.state and data.type == 'up' then
		if App.alt then
	        if seq.div < 24 and seq.div > 2 then
	          seq.div = seq.div * 2
	        elseif seq.div > 1  and seq.div < 24 then
            seq.div = seq.div + 1
	        end
			page_count = math.ceil( math.ceil(seq.length/seq.div) / wrap)
			if self.page > page_count then self.page = page_count end
		elseif grid.display_start.y < grid.grid_start.y and grid.display_end.y < seq.track.note_range_upper + 1 then	
			grid.display_start.y = grid.display_start.y + 1
			grid.display_end.y = grid.display_end.y + 1
		end
	end

	if data.state and data.type == 'pad' then
		
		local s = data.x + (self.page - 1) * wrap
		local note = data.y - 1
		
		local on_tick = (s - 1) * seq.div + 1
		local off_tick = on_tick + math.floor(seq.div/2)
		local on_swing = seq:calculate_swing(on_tick)
		local off_swing = seq:calculate_swing(off_tick)
		
		local step = seq:get_step(s, seq.div)
		local empty_step = true
		local step_on = false
		local step_off = false

		for i,v in pairs(step) do
			if v.note == note then
				v.enabled = not v.enabled
				if v.type == 'note_on' then
					empty_step = false
					step_on = true
				elseif v.type == 'note_off' then
					empty_step = false
					step_off = true
				end
			end
		end
		
		if empty_step then
			local on = {
				type = 'note_on',
				note = note,
				tick = on_swing.tick,
				vel = 100,
				offset = on_swing.offset,
				ch = seq.track.midi_in,
				enabled = true
			}

			local off = {
				type = 'note_off',
				note = note,
				tick = off_swing.tick,
				vel = 100,
				offset = off_swing.offset,
				ch = seq.track.midi_in,
				enabled = true
			}
			
			if seq.value == nil then
				seq.value = {}
			end

			if seq.value[on.tick]  == nil then
				seq.value[on.tick] = {}
			end

			if seq.value[on.tick][on.note] == nil then
				seq.value[on.tick][on.note] = {}
			end
			
			seq.value[on.tick][on.note][on.type] = on
			
			if seq.value[off.tick]  == nil then
				seq.value[off.tick] = {}
			end

			if seq.value[off.tick][off.note] == nil then
				seq.value[off.tick][off.note] = {}
			end

			seq.value[off.tick][off.note][off.type] = off

			if not seq.recording then
				seq:save_bank(seq.current_bank, true)
			end
			
		end
	end
	
	self:set_grid(seq)
end

function SeqGrid:set_grid(seq)

	local grid = self.grid
	local wrap = 8
	local current_step = (math.ceil(seq.tick/seq.div) - 1) % math.ceil(seq.length/seq.div) + 1
	local page_count = math.ceil( math.ceil(seq.length/seq.div) / wrap)

	    
    -- Follow playhead
      	if seq.follow then
        	local pos = math.ceil( (seq.tick % seq.length) / seq.div)
    		  local page = math.ceil(pos / wrap)
          
        	--wait until playhead is one step past the display and change the page
        	if pos % wrap == 1 then
            	self.page = page
		    end
      	end
	
	
		-- Set arrow pads
		if self.page  == 1 then
			App.arrow_pads.led[3][9] = 0 
		else
			App.arrow_pads.led[3][9] = 1
		end
		
		if self.page  == page_count then
			App.arrow_pads.led[4][9] = 0 
		else
			App.arrow_pads.led[4][9] = 1
		end

		if grid.display_end.y == grid.grid_end.y then
			App.arrow_pads.led[2][9] = 0 
		else
			App.arrow_pads.led[2][9] = 1
		end
		
		if grid.display_start.y == grid.grid_start.y then
			App.arrow_pads.led[1][9] = 0 
		else
			App.arrow_pads.led[1][9] = 1
		end

		App.arrow_pads:refresh('sequencer grid') -- reminder that arrow pads are a shared grid and need to be refreshed separately
		
		for  s = (self.page - 1) * wrap + 1, self.page * wrap do
		  
			local x = (s-1) % wrap + 1
			
			-- draw playhead
			for y = grid.display_start.y, grid.display_end.y do
				if s == current_step then
					grid.led[x][y] = {5,5,5}
				else
					grid.led[x][y] = 0
				end
			end
			
			local step = seq:get_step(s,seq.div)
		
			for i,v in ipairs(step) do
				if v.type == 'note_on' then
					local page = math.ceil( math.ceil(v.tick/seq.div) / wrap)
					local x = math.ceil(v.tick / seq.div) - (page - 1) * wrap
					local y = v.note + 1
					local is_current = current_step == math.ceil(v.tick/seq.div)

					if  is_current and v.enabled then
						grid.led[x][y] = Grid.rainbow_on[v.note % 16 + 1]
					elseif v.enabled then
						grid.led[x][y] = Grid.rainbow_off[v.note % 16 + 1]
					elseif is_current then
						grid.led[x][y] = {5,5,5}
					else
						grid.led[x][y] = 0
					end
					
				end
			end
		end

		grid:refresh('set grid')
	

end

-- Component specific
function SeqGrid:on_load(seq)
    self.page = 1
end


function SeqGrid:set_display (seq) end
function SeqGrid:handle_button (seq, e,d) end
function SeqGrid:handle_enc (seq, e,d) end

return SeqGrid