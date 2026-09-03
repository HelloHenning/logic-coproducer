# Research Status

_Last updated: 2026-09-03_

## Completed

### Research 1 — Logic integration and authoritative state

Completed. Main result: pursue a hybrid Logic adapter and test exact stored-MIDI/automation access empirically before assuming granular live CRUD.

### Research 2 — Local audio/music intelligence

Completed. Main result: most measurable audio/music analysis can plausibly remain local; use staged evidence pipelines, explicit uncertainty and content-addressed artifacts.

### Research 3 — Reasoning/provider routing

Completed. Main result: use a provider-independent router with local reasoning and manual ChatGPT collaboration as normal routes; cloud services remain optional and privacy-gated.

### Research 4 — Final synthesis and build plan

**Completed.** Research 4 reconciled the first three investigations into one recommended architecture and an ordered proof-of-concept program.

Key conclusions:

- Logic remains the sole source of factual project truth.
- Creative memory is separate and may persist; factual Logic state must be refreshed and verified.
- The Logic integration remains hybrid: AX/AXObserver, virtual Mackie Control/CoreMIDI, Event Lists where proven, read-only saved `.logicx`, and optional narrow telemetry.
- Event List MIDI and Automation Event List CRUD remain POC-gated rather than treated as solved.
- The authoritative state kernel uses local stable IDs, provenance, completeness, dirty domains, project/entity revisions, scoped hashes and dependency preconditions.
- External/local AI returns provider-neutral semantic Co-Producer Plans; natural-language output never directly drives Logic.
- Preview → Apply → independent readback → Verify → Undo is a core transaction protocol.
- Local audio/music analysis remains evidence-first and staged rather than monolithic.
- Local reasoning and manual ChatGPT are normal reasoning routes; cloud APIs remain optional.
- No further broad Deep Research phase is required before coding.

## Current phase

**Research → empirical POC transition.**

The immediate next step is to build `LogicInteroperabilityLab` and test the decisive MIDI sequence:

1. complete Event List read;
2. one-event granular mutation;
3. manual MIDI edit detection.

The first MVP is **Authoritative MIDI Collaboration**. Its purpose is to prove that subsequent AI requests use the current Logic state after the user manually edits the project—not merely to prove that AI can generate MIDI.

See:

- [Research 4 final synthesis](research-4-final-synthesis.md)
- [Architectural kill tests](../poc/architectural-kill-tests.md)
- [Ordered POC plan](../poc/test-plan.md)

## Publication policy

This repository publishes curated summaries rather than raw research transcripts. The summaries distinguish documented/strongly supported conclusions from POC-dependent hypotheses and dated provider information.
