# Documentation

Broad research is complete and the repository is now in the **architecture → empirical POC transition**.

## Start here

- [Vision](vision.md)
- [Design principles](principles.md)
- [Final architecture overview](architecture/overview.md)
- [Architecture decision table](architecture/decision-table.md)
- [Research 4 final synthesis](research/research-4-final-synthesis.md)
- [Architectural kill tests](poc/architectural-kill-tests.md)
- [Ordered proof-of-concept plan](poc/test-plan.md)
- [Current POC validation status](poc/validation-status.md)
- [Architecture Decision Records](adr/README.md)

## Research

- [Research index](research/README.md)
- [Research 1 — Logic integration](research/research-1-logic-integration.md)
- [Research 2 — Local music intelligence](research/research-2-local-music-intelligence.md)
- [Research 3 — AI routing](research/research-3-ai-routing.md)
- [Research 4 — Final architecture synthesis](research/research-4-final-synthesis.md)
- [Current status](research/research-status.md)

The repository publishes curated summaries rather than raw research transcripts.

## Architecture

- [Overview](architecture/overview.md)
- [Decision table](architecture/decision-table.md)
- [Authoritative Logic state and synchronization](architecture/logic-state.md)
- [Music/audio analysis](architecture/music-analysis.md)
- [Reasoning and provider routing](architecture/reasoning-routing.md)
- [Transactions and safety](architecture/transactions-safety.md)

## Proof of concept

The immediate implementation is **`LogicInteroperabilityLab`**.

The first decisive sequence is now qualified for the POC:

1. complete Event List MIDI read — **PASS**;
2. granular MIDI mutation — **PASS**;
3. authoritative refresh after an independent/manual MIDI edit — **PASS**.

This establishes the core premise for the distinctive MVP: **Authoritative MIDI Collaboration**. The remaining Phase-A work is intentionally lean and decision-oriented: prove the mixer/control-surface connection, representative plug-in/automation/routing connections, saved-state supplementation, and audio-region/source mapping without expanding into exhaustive compatibility matrices.

See:

- [Current POC validation status](poc/validation-status.md)
- [Ordered POC plan](poc/test-plan.md)
- [Final kill-test matrix](poc/architectural-kill-tests.md)
- [Superseded preliminary kill-test page](poc/preliminary-kill-tests.md)

## Architecture decisions

The ADR directory separates accepted design constraints from POC-gated hypotheses. Event List MIDI has now passed the core read/write/refresh architectural gates for the qualified stored-event subset; broader edge-case and compatibility coverage remains deferred to product hardening.

## Schemas

See [`../schemas/`](../schemas/) for the evolving machine-readable state/plan contracts. The schema architecture is established; concrete operation/state schemas will be added as the corresponding Logic POCs prove what can be observed and verified.

## Experiments

See [`../experiments/`](../experiments/) for reproducible experiment guidance and eventual POC results.

## Current build principle

Do not begin with AI cosmetics.

The project should first prove the remaining distinct Logic control/state connections, then move into the Authoritative State Kernel and Transaction Engine rather than accumulating micro-test coverage.
