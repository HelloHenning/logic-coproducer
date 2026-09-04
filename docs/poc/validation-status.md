# POC Validation Status and Strategy

_Status: paused at user-requested checkpoint — 2026-09-04_

This document is the current handoff for the Logic Co-Producer interoperability proof of concept.

Active branch: `poc/logic-interoperability-lab`

Draft PR: #5

Detailed pause / feasibility memo: `docs/poc/feasibility-checkpoint-2026-09-04.md`

## Current gate status

- A0 — sufficient
- A1 — PASS / complete: authoritative complete Event List MIDI read
- A2 — PASS / complete: verified granular MIDI mutation + restoration
- A3 — PASS / complete: manual/external edit detection and refresh
- A4 — PASS / complete: virtual Mackie Control/CoreMIDI mixer control
- A5 — PASS / complete for existing native plug-in parameter transactions
- A6 — pending: automation control
- A7 — pending: routing / sends / true sidechain
- A8 — pending: saved `.logicx` reconciliation
- A9 — pending: audio-region/source mapping
- A10 — pending: stock Logic effect insertion and chain construction (#12)
- A11 — pending: representative track/region/stock-instrument construction (#13)

## Latest target-Mac evidence

### Plug-in-slot census v4 — FAIL before mutation, but useful narrowing

Target environment remained:

- macOS 26.4.1 (25E253)
- Logic Pro 12.0.1
- Accessibility trusted
- synthetic project `Project`

Result:

`RESULT=FAIL reason=mixer-track-strip-not-unique count=0`

The important evidence is structural:

- v4 correctly found the real main Mixer as `AXLayoutArea description="Mixer"` with **8 direct channel-strip layout items**;
- it also found the smaller 2-strip Inspector-like Mixer candidate and did not choose it;
- it separately recognized the Tracks-area `Track 1 “Audio 1”` header as a lookalike, so the v3 mistake is fixed;
- however, none of the eight direct Mixer strip elements exposes enough direct semantic text for the current `Audio 1` name matcher, therefore exact Mixer-strip identity could not yet be proven;
- no mutation was attempted.

**Decision:** Mixer discovery itself is no longer the unknown. The remaining A10 blocker at this exact point is semantic track-to-strip identity / insert-slot enumeration.

This is progress in narrowing the interface, but it is **not** a new qualified product capability.

## Qualified architecture so far

### Authoritative MIDI state

The hydrated Event List observer reconstructs the complete 267-event synthetic fixture, including off-screen rows, and repeated reads match the expected semantic state.

**Decision:** Logic's Event List can act as an authoritative live-state adapter for the qualified stored-MIDI subset.

### Verified MIDI mutation

Representative note changes were independently reread as exactly the intended semantic change, collateral state was checked, and the original state was restored exactly.

**Decision:** granular Event List mutation is viable for the qualified fields.

### Manual edit refresh

A direct user edit in Logic was detected by a fresh authoritative reread independent of prior mutation intent and restored exactly.

**Decision:** fresh Logic state supersedes stale controller/AI intent.

### Mixer control

Direct AX Volume/Pan round-trips were useful pre-evidence, but AX Mute/Solo actions were not independently reliable. A virtual Mackie Control/CoreMIDI bridge then qualified Volume, Pan, Mute and Solo with Logic-to-controller feedback and exact restoration.

**Decision:** virtual MCU/CoreMIDI is the primary qualified mixer transaction plane; AX is retained for context/readback.

### Existing native plug-in parameter control

On `Studio Grand` / Studio Piano, virtual Mackie Control exposed Logic's semantic parameter names and values. Representative `Key Noise` changed 35 → 36 → 35 with fresh Logic feedback and final identity verification.

**Decision:** MCU is qualified for representative native plug-in parameter transactions on an already-existing compatible instance.

**Boundary:** this does not prove insertion, slot identity, chain construction, bypass/removal, or effect-class control. Those remain A10.

## Important prior art discovered before the pause

The public MIT-licensed repository `MongLong0214/logic-pro-mcp` contains directly relevant modern Logic automation code, including:

- Logic 12.x Mixer-container selection;
- mixer-strip Audio FX insert-slot enumeration;
- plug-in inventory;
- a fail-closed verified stock plug-in insertion path with post-insert inventory readback;
- track creation/duplication operations;
- automation-mode control;
- software-instrument assignment;
- deterministic MIDI/SMF import with region readback.

This materially improves the feasibility outlook. Before asking for more target-Mac interaction, the next development session should inspect/adapt these proven patterns rather than continue blind bespoke AX discovery.

## Feasibility assessment at the pause

### Narrow authoritative collaboration MVP

**High feasibility based on qualified evidence.**

A useful companion can already be architected around authoritative MIDI read/write, manual-edit synchronization, mixer control, and parameter adjustment on existing compatible native plug-ins.

### Full intended production-control Co-Producer

**Still plausible, but not yet proven; current risk is medium/high.**

The decisive missing capability is reliable construction of Logic state: effect insertion, track/region creation, routing/sidechains, and automation. These depend on undocumented Logic Accessibility/control-surface behavior and may require version-specific selectors plus fail-closed capability gating.

The project should therefore continue only under a bounded decision process, not an open-ended probing process.

## Restart plan

Do **not** resume with the existing broad A6–A11 unattended completion batch.

For unresolved UI mechanisms, the process is now:

1. inspect existing implementations / research first;
2. reduce the uncertainty to one small fail-closed transaction or diagnostic;
3. target 1–5 minutes of user testing;
4. qualify or reject that exact mechanism;
5. only after success, fold it into unattended integration coverage.

Priority on restart:

1. **A10:** insert one stock effect on exact `Audio 1`, verify instance/slot, remove it, prove exact restoration.
2. **A11:** create/import one disposable instrument track/region, independently verify, remove/restore.
3. **A7:** prove one normal routing edge and one true sidechain using a disposable processing context.
4. Then A6/A8/A9 as needed.

## Pivot rule

Use one focused weekend feasibility sprint, not an indefinite series of probes.

- If A10 and at least one of A11/A7 become reliably qualified, continue toward the full production-control foundation.
- If, after applying known prior-art implementations, we still cannot reliably execute and independently verify even one stock-effect insertion plus one representative construction/routing operation, reduce the product scope.

Fallback scope: keep the already-proven authoritative MIDI collaboration, mixer control, manual-edit synchronization, and existing-plug-in parameter adjustment; unsupported production operations become recommendations/instructions rather than automatic execution.

## Phase-A stop condition

Foundational Logic interoperability is complete only when there is enough representative evidence to choose a viable architecture for:

- authoritative current MIDI state;
- verified MIDI mutation;
- refresh after external/manual edits;
- mixer control;
- plug-in parameter transactions;
- stock native plug-in insertion/chain control;
- representative automation control;
- normal routing and sidechain control;
- useful saved-state supplementation;
- useful audio-region/source mapping;
- representative track/region/instrument construction.

At that point, stop proof-of-concept probing and move into the Authoritative State Kernel and Transaction Engine.
