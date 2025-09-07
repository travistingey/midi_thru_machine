-- Extends musicutil to include additional helpers for this App
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
function u.intervals_to_bits(t, d)
    local bits = 0

    for i = 1, #t do
        if t[i] == 12 then
            bits = bits | 1
        else
            bits = bits | (1 << math.fmod(t[i], 12))
        end
    end

    return bits
end

-- Returns an array of intervals from bits
function u.bits_to_intervals(b, d)
    local intervals = {}
    for i = 1, 12 do
        if (b & (1 << (i - 1)) > 0) then
            intervals[#intervals + 1] = i - 1
        end
    end

    return intervals
end

-- Shifts bits to another scale degree
-- Intervals remain the same, but the mode changes of the scale
function u.shift_scale(s, degree)
    degree = math.fmod(degree, 12) or 0
    local scale = s

    if degree > 0 then
        scale = ((s >> degree) | (s << (12 - degree))) & 4095
    else
        scale = ((s << math.abs(degree)) | (s >> (12 - math.abs(degree)))) & 4095
    end

    return scale
end

-- New Chords
table.insert(u.CHORDS, { name = 'r', intervals = {0} })
table.insert(u.CHORDS, { name = '5', intervals = {0,7} })
table.insert(u.CHORDS, { name = 'sus2', intervals = {0, 2, 7} })
table.insert(u.CHORDS, { name = '7 sus2', intervals = {0, 2, 7, 10} })
table.insert(u.CHORDS, { name = '6 sus4', intervals = {0, 5, 7, 9} })
table.insert(u.CHORDS, { name = '6 sus2', intervals = {0, 5, 7, 9} })
table.insert(u.CHORDS, { name = 'M7 sus2', intervals = {0, 2, 7, 11} })
table.insert(u.CHORDS, { name = 'M7 sus4', intervals = {0, 5, 7, 11} })
table.insert(u.CHORDS, { name = '9 sus4', intervals = {0, 2, 5, 7, 10} })

table.insert(u.CHORDS, { name = 'add9', intervals = {0, 2, 4, 7} })
table.insert(u.CHORDS, { name = 'm add9', intervals = {0, 2, 3, 7} })
table.insert(u.CHORDS, { name = 'add11', intervals = {0, 4, 5, 7} })
table.insert(u.CHORDS, { name = 'm add11', intervals = {0, 2, 3, 7} })

table.insert(u.CHORDS, { name = 'm11', intervals = {0, 3, 5, 7, 10}, voicing='-9' })
table.insert(u.CHORDS, { name = 'm13', intervals = {0, 3, 5, 7, 9, 10}, voicing='-9'})
table.insert(u.CHORDS, { name = 'm13', intervals = {0, 3, 7, 9, 10}, voicing='-9,-11' })
table.insert(u.CHORDS, { name = 'm13', intervals = {0, 2, 3, 7, 9, 10}, voicing='-11'})

table.insert(u.CHORDS, { name = '11', intervals = {0, 4, 5, 7, 10},  voicing='-9' })
table.insert(u.CHORDS, { name = '13', intervals = {0, 4, 5, 7, 9, 10}, voicing='-9'  })
table.insert(u.CHORDS, { name = '13', intervals = {0, 4, 7, 9, 10}, voicing='-9,-11'  })
table.insert(u.CHORDS, { name = '13', intervals = {0, 2, 4, 7, 9, 10}, voicing='-11' })

table.insert(u.CHORDS, { name = 'M11', intervals = {0, 4, 5, 7, 11},  voicing='-9' })
table.insert(u.CHORDS, { name = 'M13', intervals = {0, 4, 5, 7, 9, 11},  voicing='-9' })
table.insert(u.CHORDS, { name = 'M13', intervals = {0, 4, 7, 9, 11},  voicing='-9,-11' })
table.insert(u.CHORDS, { name = 'M13', intervals = {0, 2, 4, 7, 9, 11},  voicing='-11' })

table.insert(u.CHORDS, { name = '6 11', intervals = {0, 4, 5, 7, 9} })

table.insert(u.CHORDS, { name = '7b5', intervals = {0, 4, 6, 10} })

table.insert(u.CHORDS, { name = '7/b9', intervals = {0, 1, 4, 7, 10} })
table.insert(u.CHORDS, { name = '7/#9', intervals = {0, 3, 4, 7, 10} })
table.insert(u.CHORDS, { name = '7b5/b9', intervals = {0, 1, 4, 6, 10} })
table.insert(u.CHORDS, { name = 'aug7/#9', intervals = {0, 3, 4, 8, 10} })

table.insert(u.CHORDS, { name = 'aug9', intervals = {0, 2, 4, 8} })
table.insert(u.CHORDS, { name = 'aug11', intervals = {0, 4, 5, 8} })
table.insert(u.CHORDS, { name = 'aug13', intervals = {0, 4, 8, 9} })

table.insert(u.CHORDS, { name = '9/#5', intervals = {0, 2, 4, 8, 10} })
table.insert(u.CHORDS, { name = 'aug7/#9', intervals = {0, 3, 4, 8, 10} })
table.insert(u.CHORDS, { name = '7b5/#9', intervals = {0, 3, 4, 6, 10} })
table.insert(u.CHORDS, { name = 'aug7/b9', intervals = {0, 1, 4, 8, 10} })

-- Lookup table that uses bits as keys
-- returns matching musicutil SCALE or CHORD
u.interval_lookup = {}

for i = 1, #u.CHORDS do
    u.CHORDS[i].alternates = {}
    u.CHORDS[i].root = 0

    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Major%s*(.*)", "M%1")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Minor%s*(.*)", "m%1")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Dominant%s*(.*)", "%1")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Seventh", "7")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Ninth", "9")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Eleventh", "11")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Thirteenth", "13")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "^Diminished%s*(.*)", "dim%1")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "^Augmented%s*(.*)", "aug%1")
    u.CHORDS[i].name = string.gsub(u.CHORDS[i].name, "Half Diminished 7", "m7b5")

    -- Convert intervals to bitmask and save to lookup
    local intervals = u.CHORDS[i].intervals

    for j = 1, #intervals do
        intervals[j] = math.fmod(intervals[j], 12)
    end

    local bits = u.intervals_to_bits(intervals)
    u.CHORDS[i].bits = bits
    
    if (u.interval_lookup[bits] == nil) then
        u.interval_lookup[bits] = u.CHORDS[i]
    else
        table.insert(u.interval_lookup[bits].alternates, u.CHORDS[i])
    end
end

local interval_name = {
    'b2', '2', 'b3', '3', '4', '#4', '5', 'b6', '6', 'b7', '7'
}

-- INVERSIONS
for i = 1, #u.CHORDS do
    local chord = u.CHORDS[i]
    local bits = chord.bits

    for j = 2, #chord.intervals do
        if #chord.intervals > 2 then
            local inversion = u.shift_scale(bits, chord.intervals[j])
            local chord_inv = {
                bits = inversion,
                name = chord.name,
                intervals = u.bits_to_intervals(inversion),
                root = -chord.intervals[j],
                parent = chord,
                alternates = chord.alternates
            }

            if u.interval_lookup[inversion] == nil then
                u.interval_lookup[inversion] = chord_inv
                table.insert(u.CHORDS, chord_inv)
            else
                table.insert(u.interval_lookup[inversion].alternates, chord_inv)
            end
        end
    end
end

-- PARTIALS
-- SHELL VOICINGS
for i = 1, #u.CHORDS do
    local chord = u.CHORDS[i]
    local bits = u.intervals_to_bits(chord.intervals)

    if bits & (1 << 7) > 0 then -- Check if the 5th is present
        local no_fifth = bits & ~(1 << 7) -- Remove the 5th

        local shell = {
            bits = no_fifth,
            name = u.CHORDS[i].name,
            intervals = u.bits_to_intervals(no_fifth),
            parent = u.CHORDS[i],
            root = u.CHORDS[i].root,
            voicing = '-5',
            alternates = u.CHORDS[i].alternates
        }

        if u.interval_lookup[no_fifth] == nil and #chord.intervals > 3 then
            u.interval_lookup[no_fifth] = shell
            table.insert(u.CHORDS, shell)
        elseif u.interval_lookup[no_fifth] and #chord.intervals > 3 then
            table.insert(u.interval_lookup[no_fifth].alternates, shell)
        end

        if #chord.intervals > 3 then
            local rootless_bits = bits & ~1 -- Remove the root
            local rootless = u.shift_scale(rootless_bits, chord.intervals[2])
            local rootless_chord = {
                bits = rootless,
                name = u.CHORDS[i].name,
                intervals = u.bits_to_intervals(rootless),
                parent = u.CHORDS[i],
                root = -chord.intervals[2],
                voicing = '-R',
                alternates = u.CHORDS[i].alternates
            }
            if u.interval_lookup[rootless] == nil then
                u.interval_lookup[rootless] = rootless_chord
                table.insert(u.CHORDS, rootless_chord)
            else
                table.insert(u.interval_lookup[rootless].alternates, rootless_chord)
            end
        end
    end
end


for index,chord in ipairs(u.CHORDS) do
    chord.bits = u.intervals_to_bits(chord.intervals)
end

for index,chord in pairs(u.interval_lookup) do
    chord.bits = u.intervals_to_bits(chord.intervals)
end

-- Function to print chords without recursive parsing
function print_chords(chords)
    for i, chord in ipairs(chords) do
        print("Chord " .. i .. ":")
        print_chord(chord, "  ")
        print()
    end
end

function print_chord(chord, indent)
    indent = indent or ""

    print(indent .. "Name: " .. chord.name)
    print(indent .. "Intervals: " .. table.concat(chord.intervals, ", "))
    print(indent .. "Root: " .. tostring(chord.root))

    -- Print parent chord's name if exists
    if chord.parent then
        print(indent .. "Parent: " .. chord.parent.name)
    end

    -- Print alternates' names and roots if they exist
    if chord.alternates and #chord.alternates > 0 then
        print(indent .. "Alternates:")
        for _, alt in ipairs(chord.alternates) do
            print(indent .. "  - " .. alt.name .. " (Root: " .. tostring(alt.root) .. ")")
        end
    end
end



-- Then return the combined table
return u