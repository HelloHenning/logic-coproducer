# ADR 0005 — Evaluate Event List as the preferred live MIDI adapter

**Status:** Proposed / POC-gated

## Proposal

Use Logic's Event List as the preferred live stored-MIDI observation/editing surface **only if** Accessibility experiments prove exhaustive deterministic enumeration, granular mutation and independent re-read.

## Why this is not accepted yet

Logic's Event List itself exposes precise numeric MIDI events, but Research 1 did not find a documented external note-level CRUD API for arbitrary stored regions. Accessibility may bridge that gap, but completeness and robustness are not yet proven.

## Required pass conditions

A POC should demonstrate at least:

- all events in a known region can be enumerated, including rows outside the visible viewport;
- note/CC/pitch-bend/articulation data can be reconstructed exactly;
- one selected note can have pitch/start/duration/velocity changed without changing unrelated events;
- events can be created/deleted where required;
- manual user edits made after the baseline are visible on the next refresh;
- re-read proves the actual stored result.

Use stress fixtures with overlapping notes, multiple channels/event types and large event counts.

## If it passes

Event List becomes the strongest candidate for live exact MIDI read/write, with the state kernel and transaction engine remaining independent of that implementation detail.

## If it fails

Fallbacks may include controlled Standard MIDI File export/import, virtual MIDI recording, saved `.logicx` readback and region-level replacement where unavoidable. These would reduce granularity and may downgrade some features from verified editing to advisory/composition assistance.

Research 4 is expected to decide whether failure would kill the product or only advanced granular MIDI capability.
