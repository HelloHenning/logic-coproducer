# Logic Co-Producer

Research and development of a session-aware AI co-producer for Logic Pro.

The project is currently validating a hybrid Logic integration architecture before building higher-level AI workflows.

## Current POC status

The core authoritative MIDI sequence has passed for the qualified stored-event subset:

- complete Event List MIDI read — PASS;
- granular MIDI mutation with independent readback/restoration — PASS;
- refresh after an independent/manual Logic MIDI edit — PASS.

The remaining Phase-A work is intentionally decision-oriented rather than exhaustive: establish a viable mixer-control plane, then qualify one representative plug-in, automation, routing, saved-project and audio-region/source connection. Broad compatibility and micro-variation matrices are deferred until product hardening.

See [`docs/poc/validation-status.md`](docs/poc/validation-status.md) for current evidence and stop conditions.

## Core design principles

- Logic is the source of truth.
- Events/signals may indicate what became stale; authoritative refresh determines what is true.
- AI/provider history never overrides current Logic state.
- Actions use Preview → Apply → independent Verify → Undo/rollback.
- Unknown or incomplete state is explicit rather than guessed.
- Provider reasoning is separated from local safety/capability enforcement.
- Paid cloud APIs remain optional rather than architectural prerequisites.

## Repository structure

- `docs/` — vision, architecture, research synthesis, ADRs and POC status
- `experiments/` — empirical Logic interoperability work
- `schemas/` — evolving machine-readable state and semantic-plan contracts

## Privacy / evidence

Synthetic fixtures are used for public POC work. Raw Logic Accessibility snapshots, evidence ZIPs, unpublished music and private recent-file/history data should not be committed publicly unless sanitized.

## Development branch

Current empirical work is on `poc/logic-interoperability-lab` and is tracked through draft PR #5 and the POC gate issues.
