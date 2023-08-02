--Extends musicutil to include additional helpers for this App
local function deepCopy(orig)
    local origType = type(orig)
    local copy
    if origType == 'table' then
        copy = {}
        for origKey, origValue in next, orig, nil do
            copy[deepCopy(origKey)] = deepCopy(origValue)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local musicutil = require('musicutil')
local u = deepCopy(musicutil)



-- Returns bits from an array of intervals
function u.intervals_to_bits(t,d)
	local bits = 0

	for i=1, #t do
		if t[i] == 12 then
			bits = bits | 1
		else
			bits = bits | (1 << math.fmod(t[i],12) )
		end
	end

	return bits
end

-- Returns an array of intervals from bits
function u.bits_to_intervals(b,d)
	local intervals = {}
	for i=1, 12 do
		if (b & (1 << i - 1) > 0) then
			intervals[#intervals + 1] = i - 1
		end
	end

	return intervals
end

-- New Chords
u.CHORDS[#u.CHORDS + 1] = { name = 'Fifth', intervals = {0,7} }


-- Lookup table that uses bits as keys
-- returns matching musicutil SCALE or CHORD
u.interval_lookup = {}

for i=1, #u.SCALES do
	local bits = u.intervals_to_bits(u.SCALES[i].intervals)
	u.interval_lookup[bits] = u.SCALES[i]
end

for i=1, #u.CHORDS do
	local chord = u.CHORDS[i].intervals

	for i=1, #chord do
		chord[i] = math.fmod(chord[i],12)
	end
	local bits = u.intervals_to_bits(chord)

	if(u.interval_lookup[bits] == nil )then
		u.interval_lookup[bits] = u.CHORDS[i]
	end	
end


-- Shifts bits to another scale degree
-- Intervals remain the same, but the mode changes of the scale
function u.shift_scale(s,degree)
	degree = math.fmod(degree,12) or 0
	local scale = s

	if degree > 0 then
		scale = ((s >> degree) | (s << 12 - degree) ) & 4095
	else
		scale = ((s << math.abs(degree)) | (s >> 12 - math.abs(degree)) ) & 4095
	end

	return scale
end

-- Then return the combined table
return u