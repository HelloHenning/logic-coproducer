# Schemas

This directory will hold versioned machine-readable contracts used by the Co-Producer.

Research 4 has finalized the **schema architecture**, but concrete schemas should still evolve alongside the first state/transaction POCs so they reflect what can actually be observed and verified in Logic.

Expected families:

```text
schemas/
  project-state/      authoritative scoped Logic-state interchange
  music-state/        measurements, events, hypotheses and interpretations
  coproducer-plan/    provider-neutral semantic edit plans
  handoff/            manual provider manifest/request packages
```

## External canonical format

Use **JSON + JSON Schema** for provider/manual interchange.

A custom `.coproducer-handoff` container may be used for local archival, but the files inside remain ordinary versioned JSON/Markdown/optional media rather than a proprietary reasoning language.

## Co-Producer Plan envelope

The plan family should carry at least:

```text
schema_version
request_id
base_revision_id
scope_state_sha256
decision
analysis
assumptions
uncertainties
protected_targets
actions
```

Executable actions should include where relevant:

```text
action_id
atomic_group_id
target entity type + stable local ID
time/scope
semantic operation
operation parameters
dependencies
precondition hashes
confidence metadata
rationale
expected musical/audible result
```

The AI does **not** generate undo operations. The local transaction engine generates inverse/restoration data from authoritative pre-state.

## Design rules

- Factual Logic state and inferred analysis remain distinguishable.
- Unknown fields do not silently pass executable validation.
- Every executable operation resolves to a known operation-specific schema.
- The current adapter capability registry is checked separately from syntactic validity.
- Stable target IDs and stale-state target/dependency preconditions belong in the plan contract.
- A global project revision mismatch is a warning/revalidation trigger, not automatic total-plan invalidation.
- Model-reported confidence never bypasses schema/state/safety checks.
- AI output never directly encodes arbitrary shell/UI automation commands.
- Imported project strings/metadata are untrusted data, not privileged instructions.

## First concrete implementation order

Do not try to finalize every possible operation before the interoperability POC.

The first executable plan/transaction schemas should cover only the minimal MIDI MVP operations proven by the adapter, for example:

```text
add_note
remove_note
move_note
change_velocity
```

Only add a semantic operation after the corresponding Logic observation → mutation → readback path has been qualified.

See:

- [`docs/architecture/transactions-safety.md`](../docs/architecture/transactions-safety.md)
- [`docs/architecture/logic-state.md`](../docs/architecture/logic-state.md)
- [`docs/poc/test-plan.md`](../docs/poc/test-plan.md)
