# Authoritative Logic State and Synchronization

_Status: architecture decision established; adapter coverage is POC-qualified per domain._

## Authority rule

Logic Pro is the sole source of truth for current factual DAW state.

The Co-Producer may cache normalized snapshots, but a cached value is authoritative only within its declared provenance/freshness/completeness boundary. AI conversation history and previously generated MIDI are never authoritative project state.

Creative memory is stored separately and may persist.

## State layers

Do not collapse these:

1. **Raw Logic facts**
2. **Derived measurements/events**
3. **Musical hypotheses**
4. **Interpretation**
5. **Creative intent**
6. **Proposed actions**

Only the first layer represents factual Logic state. Derived/inferred values must retain source, analyzer/model/version, time span, confidence semantics and alternatives where relevant.

## Field-level provenance

A normalized factual field should carry at least:

```json
{
  "value": -8.4,
  "unit": "dB",
  "sources": ["mcu_feedback", "ax_corroboration"],
  "observed_at": "...",
  "authority": "live",
  "completeness": "complete",
  "entity_revision": 782,
  "dirty": false
}
```

A saved-only value must explicitly say so. A hypothesis must never be represented using the same authority class as a Logic fact.

## Domains

The state kernel should track dirty/freshness state independently for domains such as:

- transport;
- selection/context;
- tracks;
- regions;
- MIDI;
- mixer;
- plug-ins;
- routing;
- automation;
- markers;
- chord/signature state;
- audio mapping.

This allows one domain to be refreshed without pretending the rest of the project was re-observed.

## Synchronization rule

> **Events tell us what may have become stale; refresh tells us what is true.**

Change notifications are primarily invalidation hints unless the event source itself provides an authoritative new value.

Examples:

- AX notification may mark selection/tracks/context dirty.
- MCU/CoreMIDI feedback can directly update qualified mixer values or mark them dirty.
- filesystem/save events allow a new saved `.logicx` snapshot.
- optional AU/Scripter telemetry may update narrow audio/timing/MIDI-flow domains but is not a project database.

Before reasoning or mutation, the application refreshes the minimum dependency closure required by the request.

## Refresh levels

### Fast refresh

Designed for interactive context:

- Logic presence/version;
- transport/playhead/cycle where available;
- current selection;
- current channel;
- cheap mixer/control-surface values;
- dirty flags.

### Targeted refresh

Normal pre-reasoning and pre-transaction safety path.

Examples:

- exact selected MIDI region;
- one automation lane;
- relevant chorus harmony;
- two tracks plus routing for sidechain creation;
- one plug-in's qualified parameters.

### Full/deep refresh

Used for:

- first project attach;
- settled save reconciliation;
- major topology changes;
- identity ambiguity;
- diagnostics/regression qualification;
- user-requested deep refresh.

A large project should not require a complete deep crawl before every operation.

## Project revisions

Maintain a monotonic local `project_revision` whenever the normalized authoritative state recognizes a factual project mutation.

The project revision is primarily:

- an audit sequence;
- an indication that something changed;
- a request/base revision marker.

It is **not** by itself a reason to reject every pending plan.

## Entity revisions

Every tracked entity has an `entity_revision` that changes when state relevant to that entity changes.

A pan change on Track A should not automatically version an unrelated MIDI region as though its note data changed.

## Hash design

Use several levels:

- `full_state_sha256` — audit/debug snapshot fingerprint;
- `scope_state_sha256` — fingerprint of the complete current context used by one reasoning request;
- per-target/precondition hashes — state required for one action;
- dependency hashes — state an action semantically depends upon.

### Example

A plan is exported at project revision 1842. The user then renames an unrelated verse track and the current revision becomes 1850.

If the chorus target region and all dependencies are unchanged, its action may remain eligible after warning/revalidation.

If the chorus harmony, target region, required plug-in or sidechain source changed, only affected actions and their dependent actions become invalid.

This gives selective validity rather than an overly conservative global-hash lock.

## Co-Producer entity IDs

The application assigns local opaque IDs for:

- projects;
- tracks;
- regions;
- MIDI events;
- plug-in instances;
- plug-in parameters;
- buses;
- sends;
- automation lanes;
- audio assets;
- analysis artifacts.

Display names are metadata, never primary identity.

## Reconciliation rules

Logic does not expose guaranteed public permanent IDs for every object, so identity may be reconstructed from multiple independent observations.

### Tracks

Use the strongest available identity evidence, potentially including saved-state identity, type/channel characteristics, region membership, plug-in-chain fingerprint and surrounding topology.

Rename/reorder should preserve the Co-Producer ID when reconciliation is unambiguous.

### Regions

Use available saved identity plus track membership, content/source fingerprint, temporal properties and neighboring context.

Move/rename should preserve identity. Duplication produces a new Co-Producer ID unless Logic exposes a separate unambiguous object identifier.

### MIDI events

Treat note/event identity conservatively. Use region-scoped local IDs tied to an observed revision and reconcile across edits only when unambiguous.

Overlapping identical events can make identity ambiguous. In those cases, re-resolve by current state rather than pretending an old event identity is permanent.

### Plug-in instances

Combine track identity, AU/component identity, slot/order, readable state fingerprint and neighboring plug-ins.

If identical instances become indistinguishable after reorder, mark identity ambiguous and fail closed for targeted mutation until refreshed/requalified.

### Assets/artifacts

Use strong content hashes where possible.

## Identity confidence

Every reconciled entity can carry:

```text
identity_confidence = high | medium | low | ambiguous
```

Mutation requires an operation-specific minimum confidence plus immediate pre-write revalidation.

`ambiguous` means no mutation.

## Stable-target transaction rule

Immediately before any write:

1. refresh required target/dependency state;
2. resolve the stable local entity;
3. validate precondition hashes;
4. ensure capability is still qualified;
5. serialize the short write/verification window;
6. apply;
7. independently re-read.

This minimizes race conditions caused by user selection changes or project edits during the operation.

## Conditional exact MIDI state

Event List is the preferred live exact-MIDI source only after the interoperability POC proves completeness and reliable readback.

Until then its status is **promising / POC-gated**.

If complete Event List read fails, exact MIDI state falls back to controlled SMF export and saved-state corroboration where useful.

See [the ordered POC plan](../poc/test-plan.md).

## Saved `.logicx` role

A `.logicx` parser is always a **read-only saved-state observer**.

Parser output must carry:

- saved revision/time;
- saved-only authority;
- parser/version provenance;
- identity/reconciliation confidence.

Never modify the open Logic project package behind Logic.

## Qualification principle

A field/operation becomes product-supported only when the complete chain is qualified:

```text
observe → resolve → mutate (if applicable) → independently re-read → verify
```

The project should report capability coverage per domain/operation instead of claiming a vague percentage of "Logic support."
