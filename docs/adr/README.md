# Architecture Decision Records

ADRs capture durable project decisions separately from exploratory research. A decision marked **Accepted** is part of the current architecture. A decision marked **Proposed / POC-gated** depends on an empirical qualification test before its implementation can be treated as trustworthy.

## Current ADRs

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-logic-is-source-of-truth.md) | Logic Pro is the source of factual project truth | Accepted |
| [0002](0002-separate-factual-state-and-creative-memory.md) | Factual Logic state and creative memory are separate layers | Accepted |
| [0003](0003-provider-independent-reasoning.md) | Reasoning/provider choice is independent of the Logic/control architecture | Accepted |
| [0004](0004-preview-apply-verify-undo.md) | Mutations use Preview → Apply → independent Verify → Undo/restore | Accepted |
| [0005](0005-event-list-midi-adapter.md) | Event List is preferred for live exact MIDI only if qualification passes | **Proposed / POC-gated** |
| [0006](0006-event-assisted-refresh-before-action.md) | Use event-assisted, refresh-before-action synchronization | Accepted |
| [0007](0007-semantic-plans-and-local-safety-compiler.md) | AI returns provider-neutral semantic plans validated by a local safety compiler | Accepted |

## ADR policy

Use an ADR when changing a decision would materially alter:

- the authority model;
- data/state boundaries;
- Logic integration strategy;
- safety/transaction semantics;
- provider independence;
- distribution/runtime architecture.

Do not use ADRs to freeze replaceable model names, API prices, free-tier quotas or other volatile implementation data.

## POC-gated decisions

A POC-gated ADR should state:

- the empirical question;
- pass/fail criteria;
- fallback architecture;
- which product capability is lost or downgraded on failure.

Passing one informal demo is not enough to change a POC-gated decision to Accepted. The relevant qualification suite must prove completeness, correct targeting and independent readback on the target Logic/macOS build.
