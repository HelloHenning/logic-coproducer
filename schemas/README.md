# Schemas

This directory will hold versioned machine-readable contracts used by the Co-Producer.

No schema is finalized yet; Research 4 is still running. The current expected families are:

```text
schemas/
  project-state/      authoritative scoped Logic-state interchange
  music-state/        measurements, events, hypotheses and interpretations
  coproducer-plan/    provider-neutral semantic edit plans
  handoff/            manual provider manifest/request packages
```

## Design rules

- JSON / JSON Schema is the current leading external interchange format.
- Factual Logic state and inferred analysis must remain distinguishable.
- Unknown fields should not silently pass executable validation.
- Every executable action must resolve to a known operation-specific schema.
- Stable target IDs and stale-state preconditions belong in the plan contract.
- AI output never directly encodes arbitrary shell/UI automation commands.

The first concrete schema should be created only after Research 4 finalizes the state/transaction model and the initial Logic POCs establish what can actually be represented and verified.
