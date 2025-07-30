# Testing Roadmap

This document outlines the phased approach for improving test coverage while relying on the real Norns environment. It complements `docs/testing.md`, which describes the custom on-device framework.

## High-Level Goals
- Avoid stubbing core Norns libraries when possible.
- Achieve full coverage of modular components such as MIDI input and output.
- Progress from isolated component tests to full application integration.
- Use virtual MIDI devices for repeatable scenarios.

## Current Testing State and Gaps
- The test runner lists spec files manually rather than discovering them dynamically【F:test/FoobarTests.lua†L10-L24】.
- MIDI input tests inject events directly into component methods instead of using the Norns `midi` API【F:test/lib/spec/input_spec.lua†L35-L39】.
- Existing specs cover individual modules but omit track-level and end‑to‑end scenarios【F:docs/lib_component_tests.md†L10-L24】.

## Sprint Stories

### Story 1: Dynamic Test Runner and Spec Organization (Phase 1)
**Assumptions**
- `test/FoobarTests.lua` is the entry script for the test suite.
- Specs reside under `test/lib/spec/`.

**Code Changes**
- Replace the hard‑coded spec list with a directory scan using `util.scandir`.
- Optionally move spec files into `test/spec/` while keeping existing naming conventions.

**Spec**
- No new spec required; the runner should load all existing specs automatically.

**Testing**
- Run `make test`.
- Expected output: each spec file is listed and the summary totals all loaded specs.

### Story 2: Virtual MIDI Device Parity (Phase 2)
**Assumptions**
- `DeviceManager:register_virtual_device()` creates a placeholder device【F:src/lib/components/app/devicemanager.lua†L615-L627】.
- A future `VirtualMidi` module will mimic `midi.Device` behaviour.

**Code Changes**
- Implement full `note_on`, `note_off`, `cc`, and related functions in the virtual device.
- Allow loading MIDI event tables for batch playback.

**Spec**
- Update `test/lib/spec/device_manager_spec.lua` to assert that virtual devices send and receive MIDI messages via the new API.

**Testing**
- Run `make test`.
- Expected output: device manager specs show passing tests verifying virtual device behaviour.

### Story 3: Input Component Coverage (Phase 2)
**Assumptions**
- `Input` component exists at `src/lib/components/track/input.lua`.
- Virtual MIDI device from Story 2 is available.

**Code Changes**
- Modify `Input` to accept events from the virtual device.
- Consolidate reusable MIDI event tables in `test/lib/midi_events.lua`.

**Spec**
- Expand `test/lib/spec/input_spec.lua` to replay MIDI event tables through the virtual device and assert resulting track events.

**Testing**
- Run `make test`.
- Expected output: input specs report passing cases for `note_on`, `note_off`, and `cc` events.

### Story 4: Track Initialization and Chain Verification (Phase 3)
**Assumptions**
- Track constructor loads component modules sequentially【F:src/lib/components/app/track.lua†L17-L35】.

**Code Changes**
- Add `test/lib/spec/track_spec.lua` verifying parameter defaults, component loading order, and event chain execution.

**Spec**
- New spec asserts that track instances wire components correctly and emit events through the chain.

**Testing**
- Run `make test`.
- Expected output: track specs pass and appear in the summary totals.

### Story 5: Mode Grid State Validation (Phase 4)
**Assumptions**
- Mode system and grid helper live under `src/lib/components/app/mode.lua` and `src/lib/grid.lua`.

**Code Changes**
- Expose grid LED states from mode components as testable tables.

**Spec**
- Extend `test/lib/spec/mode_spec.lua` to simulate knob and key events and compare expected LED states.

**Testing**
- Run `make test`.
- Expected output: mode specs confirm LED state transitions and interaction handling.

### Story 6: MIDI Roundtrip Integration (Phase 5)
**Assumptions**
- Virtual MIDI device and track tests from prior stories are in place.

**Code Changes**
- Create `test/lib/spec/app_roundtrip_spec.lua` that wires a virtual input through `App`, `Track`, and `Output` components.

**Spec**
- Spec verifies that a MIDI event injected at the input emerges unchanged from the output.

**Testing**
- Run `make test`.
- Expected output: roundtrip spec shows passing results with the full stack initialized.

### Story 7: Test Automation and Coverage Reporting (Phase 6)
**Assumptions**
- Makefile currently supports `make test` and `make lint`.

**Code Changes**
- Add a `watch` target that invokes tests on file changes.
- Implement simple coverage tracking within the test framework.

**Spec**
- No new spec; coverage reports are generated as part of the test run.

**Testing**
- Run `make watch` in one terminal and edit a spec file.
- Expected output: tests rerun automatically and display coverage statistics.

## Recap
- Begin with the test runner and virtual MIDI device.
- Add input and track coverage, then mode and integration tests.
- Finish with automation and coverage reporting.

Following these stories will gradually build a robust suite that runs directly on Norns hardware while maintaining realistic behaviour.
