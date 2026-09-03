# ADR 0005 — Event List as the Preferred Live MIDI Adapter, Conditional on POC

**Status:** Proposed / POC-gated  
**Decision owner:** project architecture  
**Last updated:** 2026-09-03

## Context

The Co-Producer needs exact current MIDI from Logic and ideally granular stored-event mutation. There is no documented external Logic region-note CRUD API that can simply be treated as a production interface.

Logic's Event List is the strongest live candidate because it exposes exact event-level data in a structured numeric editor and supports event editing inside Logic itself. The unresolved question is whether the relevant Accessibility hierarchy can be used **completely, deterministically and safely** on the target Logic/macOS build.

This is distinct from symbolic MIDI understanding. Once exact events are available, analysis is straightforward; obtaining and mutating the authoritative current events inside Logic is the POC problem.

## Decision

If the Event List POC passes, Event List Accessibility becomes the preferred live exact-MIDI adapter for selected/scoped regions.

It must not be treated as solved before qualification.

## Required pass conditions

The adapter must prove all of the following on synthetic golden fixtures:

1. every relevant event can be enumerated deterministically;
2. completeness can be proven rather than assumed;
3. events outside the initially visible viewport are included without duplicates/omissions;
4. qualified event fields are read accurately (position, type/status, channel, values, length and other required fields);
5. one event/property can be changed without collateral edits;
6. event create/delete can be qualified before those operations are enabled;
7. complete state can be re-read after manual user edits;
8. post-write readback proves the exact intended diff;
9. unrelated events remain unchanged;
10. filtering/selection/editor state cannot silently produce an incomplete snapshot.

## Initial test sequence

1. complete Event List MIDI census;
2. one-event mutation;
3. manual MIDI edit detection.

See [`../poc/test-plan.md`](../poc/test-plan.md).

## If complete read passes but granular write fails

Keep Event List as the authoritative live readback adapter.

Mutation falls back to controlled Standard MIDI File transformation/import or broader region replacement where unavoidable.

This preserves source-of-truth awareness but reduces surgical note-level transaction capability.

## If complete Event List read fails

Use a fallback exact-read path built around controlled MIDI export plus saved-state corroboration where useful.

The product may still provide:

- musical analysis;
- composition suggestions;
- region-level MIDI replacement;
- mixer/plug-in/routing features;
- reference analysis;
- local/ChatGPT reasoning.

It must not claim universally granular live MIDI editing.

## Consequences

### Positive

- Potentially exposes Logic's actual stored event representation without requiring a full region export on every refresh.
- Provides an independent readback path after manual user edits.
- If mutation passes, supports minimal semantic note-level transactions.

### Negative / risk

- Accessibility is not a stable public Logic object API contract.
- Virtualized rows/filter state may make completeness difficult.
- Logic updates/localization/editor state may require version qualification.
- Event identity across ambiguous edits cannot be assumed permanent.

## Safety rule

A successful UI action or AX value set is not verification. Every enabled mutation must be followed by authoritative re-read and exact expected-vs-observed diff.

## Product impact if this ADR's POC fails

Failure **does not kill the overall Co-Producer**. It downgrades the strongest MIDI-editing experience and may force broader region-level mutations until a better live adapter exists.

The defining product principle—Logic is authoritative—still remains viable through exact fallback readback, provided the product is honest about capability boundaries.
