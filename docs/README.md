# Documentation

Broad research is complete and the repository is now in the **architecture → empirical POC transition**.

## Start here

- [Vision](vision.md)
- [Design principles](principles.md)
- [Final architecture overview](architecture/overview.md)
- [Architecture decision table](architecture/decision-table.md)
- [Research 4 final synthesis](research/research-4-final-synthesis.md)
- [POC validation status and strategy](poc/validation-status.md)
- [Architectural kill tests](poc/architectural-kill-tests.md)
- [Ordered proof-of-concept plan](poc/test-plan.md)
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

The first decisive sequence is:

1. complete Event List MIDI read;
2. one-event granular mutation;
3. manual/external MIDI edit detection.

A1 and A2 have passed the POC decision threshold. A3 has proven the core fresh-read/source-of-truth mechanism and is being completed with lean representative external-edit cases.

The current testing rule is **decision-oriented rather than exhaustive**: prove each distinct architectural connection or failure mode with a representative case, then move on. Broader matrices and compatibility sweeps belong to later product hardening.

See:

- [Current POC validation status and strategy](poc/validation-status.md)
- [Ordered POC plan](poc/test-plan.md)
- [Final kill-test matrix](poc/architectural-kill-tests.md)
- [Superseded preliminary kill-test page](poc/preliminary-kill-tests.md)

## Architecture decisions

The ADR directory separates accepted design constraints from POC-gated hypotheses. Event List MIDI is now qualified for the POC's exact-read and representative granular-write path; other domains remain capability-gated until their own representative read/write/readback connection is proven.

## Schemas

See [`../schemas/`](../schemas/) for the evolving machine-readable state/plan contracts. The schema architecture is established; concrete operation/state schemas will be added as the corresponding Logic POCs prove what can be observed and verified.

## Experiments

See [`../experiments/`](../experiments/) for reproducible experiment guidance and eventual POC results.

## Current build principle

Do not begin with AI cosmetics.

The project should first prove:

> **Logic state can be observed authoritatively, a minimal change can be made and independently verified, manual user changes can be re-read, and stale AI/controller history cannot override what is currently in Logic.**
