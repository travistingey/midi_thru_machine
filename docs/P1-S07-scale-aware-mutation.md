# User Story: P1-S07 - Scale-Aware Bitwise Mutation

## Story
**As a** musician  
**I want** bitwise mutations to respect the current scale  
**So that** morphing sequences stay in key and sound musical

## Details

### Description
When bitwise values mutate (flip bits), the resulting notes should be quantized to the active scale. This ensures that algorithmic generation stays harmonically coherent, even as patterns evolve.

### Current State
- Bitwise generates values from bit patterns (0.0 - 1.0 normalized)
- Scale quantization exists in `scale.lua` component
- No connection between bitwise generation and scale quantization
- Bitwise mutations can produce "wrong notes" outside the active scale

### Proposed Solution
- When `Bitwise:mutate(i)` flips bits, resulting value gets scale-quantized
- Integration with track's assigned scale (from Scale component)
- Preserve the "shape" of mutations while constraining to scale
- Respect scale changes in real-time (mutations follow scale switches)

### Technical Architecture

#### Current Bitwise Value Generation
```lua
-- In bitwise.lua
function Bitwise:update()
  for i = 1, self.length do
    local value = (track & mask) / mask  -- Generates 0.0-1.0
    v[i] = value
    -- ...
  end
end
```

#### Proposed Scale Integration
```lua
-- In input.lua or new integration layer
function generate_note_with_scale(bitwise_value, scale, root, octave_range)
  -- Convert normalized value (0-1) to MIDI note number
  local raw_note = bitwise_value * (octave_range * 12)
  
  -- Quantize to scale
  local quantized = scale:quantize_note({note = raw_note})
  
  return quantized.new_note
end
```

### Integration Points

1. **Option A**: Modify `input.lua` component
   - When input type is "bitwise", apply scale quantization after value generation
   - Leverages existing scale component integration

2. **Option B**: Extend `Bitwise:get(i)` method
   - Add optional scale parameter
   - Return scale-quantized value when scale provided

3. **Option C**: Create wrapper in track processing chain
   - Bitwise generates raw values
   - Separate "quantize" step applies scale

**Recommendation**: Option A (modify `input.lua`) - keeps bitwise pure, leverages existing architecture

### Acceptance Criteria
- [ ] Mutated notes are quantized to the active scale
- [ ] Mutations preserve the "character" of bit patterns (intervals/leaps)
- [ ] Scale changes immediately affect subsequent mutations
- [ ] No noticeable performance impact (quantization is fast)
- [ ] Works with all follow modes (transpose, scale degree, pentatonic, etc.)
- [ ] Locked steps remain unaffected by scale changes
- [ ] Can be disabled (raw bitwise mode for testing/experimentation)

## Dependencies
- Scale component (`lib/components/track/scale.lua`)
- Bitwise component (`lib/utilities/bitwise.lua`)
- Input component (`lib/components/track/input.lua`)
- Understanding of scale quantization method: `Scale:quantize_note()`

## Blockers
- **Decision needed**: Where should quantization happen in the processing chain?
  - Before or after velocity/CC processing?
  - **Recommendation**: After value generation, before MIDI output
- **Decision needed**: Should there be a "raw mode" parameter?
  - **Recommendation**: Yes, add `scale_aware` boolean parameter (default: true)
- **Investigation needed**: Does `Scale:quantize_note()` handle edge cases?
  - Empty scales (bits = 0)?
  - Single-note scales?
  - Extreme octave ranges?

## Estimated Effort
**Medium** (2-3 days)
- Investigation of scale quantization API: 2-3 hours
- Implementation in input.lua: 3-4 hours
- Testing with various scales: 3-4 hours
- Edge case handling: 2-3 hours
- Performance optimization: 2-3 hours
- Documentation: 1-2 hours

## Priority
**High** - This is what makes bitwise musically useful. Without scale awareness, mutations are random chromatic notes.

## Related Stories
- P1-S06: Buffer → Bitwise (captured notes should maintain scale relationship)
- P1-S03: Encoder control (mutation chance + scale = powerful combo)
- P1-S05: Lock control (locked steps bypass scale mutation)

## Notes

### Musical Implications
- Scale-aware mutation creates "guided randomness"
- Patterns stay recognizable but evolve within harmonic context
- Enables generative music that sounds intentional, not chaotic

### Technical Considerations
- Scale component already handles note-off management during scale changes
- May need to track "original" note vs "quantized" note for note-off
- Consider caching quantized values if scale doesn't change frequently
- Bitwise values (0-1) need sensible mapping to MIDI note range (suggest: C2-C6, 48-96)

### Future Enhancements
- **Scale-weighted mutation**: More likely to mutate to chord tones
- **Melodic constraints**: Limit interval jumps (no more than perfect 5th, etc.)
- **Voice leading**: Prefer smooth motion between mutated notes
- **Tension/release**: Alternate between stable (chord tones) and unstable (passing tones)

### Reference Implementation
Look at how `input.lua` currently handles scale quantization for other input types (arp, random, etc.) and replicate that pattern for bitwise.

## Testing Strategy
1. **Basic**: Generate bitwise sequence, verify all notes in scale
2. **Scale change**: Change scale mid-sequence, verify immediate quantization
3. **Follow modes**: Test with transpose, scale degree, pentatonic modes
4. **Edge cases**: Empty scale (bits=0), single note scale (bits=1)
5. **Performance**: Measure CPU impact of per-step quantization
6. **Musical**: Does it sound good? Get feedback from musicians.
