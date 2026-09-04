# Logic Co-Producer feasibility checkpoint — 2026-09-04

_Status: paused at the user's request after the plug-in-slot census v4 run._

This checkpoint exists to prevent the proof-of-concept from drifting into endless UI probing. It records what is actually proven, what remains unproven, what today's final test changed, and the decision criteria for the next session.

## What is genuinely proven

The project has already crossed several non-trivial interoperability boundaries on Logic Pro 12.0.1 / macOS 26.4.1:

- **A1 — authoritative MIDI read:** complete hydrated Event List state can be reconstructed deterministically from Logic.
- **A2 — verified MIDI mutation:** representative note edits can be written, independently reread, checked for collateral changes, and restored exactly.
- **A3 — manual/external edit detection:** a fresh Logic reread supersedes stale controller intent and detects direct user edits.
- **A4 — mixer control:** a virtual Mackie Control/CoreMIDI bridge drives and receives feedback for Volume, Pan, Mute and Solo with verified restoration.
- **A5 — existing native plug-in parameter control:** Logic's own Mackie Control plug-in edit surface exposes semantic native Studio Piano parameters; a representative parameter write/readback/restore is qualified.

These are real architectural wins. They prove that Logic can remain the source of truth while a companion application observes and performs some verified edits.

## What is not yet proven

The broader Co-Producer vision still depends on essential production operations that remain unqualified:

- **A6 — automation creation/editing**
- **A7 — routing, sends and a true sidechain relationship**
- **A8 — useful saved `.logicx` reconciliation**
- **A9 — audio-region to source-file mapping**
- **A10 — stock Logic effect insertion and processing-chain construction**
- **A11 — representative track/region/instrument construction**

The project must not be described as having a complete production-control foundation until these gaps are resolved or explicitly removed from scope.

## Final test before the pause: plug-in-slot census v4

Evidence ZIP: `coproducer-plugin-slot-census-v4.zip` from the target Mac.

Result:

`RESULT=FAIL reason=mixer-track-strip-not-unique count=0`

Important observations from the evidence:

- the probe now resolves the **real main Mixer container**, not the Tracks-area header lookalike;
- the chosen Mixer is `AXLayoutArea description="Mixer"` and contains **8 direct channel-strip layout items**;
- the separate Inspector-like Mixer candidate contains only 2 strips, so the main Mixer selection itself is no longer ambiguous;
- the Tracks-area `Audio 1` header is correctly recognized only as a lookalike and is no longer mistaken for the Mixer strip;
- however, none of the eight direct Mixer strip elements exposes enough direct label text for the v4 probe's `Audio 1` name matcher, therefore exact strip identity still failed before any mutation.

### Interpretation

This is **narrowing progress, not a new product capability**.

The failure is no longer "we cannot find Logic's Mixer." The remaining problem is the identity mapping from a semantic track such as `Audio 1` to the corresponding direct Mixer strip when the strip's identifying label lives deeper in its AX subtree or must be correlated by another stable property.

No project mutation was attempted by this census.

## Important external prior art discovered

Before doing more blind target-Mac probing, inspect and reuse proven public implementation ideas where possible.

The MIT-licensed public repository `MongLong0214/logic-pro-mcp` is especially relevant. Its current codebase contains:

- Logic 12.x-specific Mixer-container selection logic;
- enumeration of Audio FX insert slots from mixer strips;
- a `plugin.get_inventory` path;
- a fail-closed `plugin.insert_verified` flow that drives the target insert slot's popup and only declares success after a fresh post-insert inventory readback observes the requested plug-in in the requested slot;
- track commands including `create_audio`, `create_instrument`, `duplicate`, `set_automation`, `set_instrument`, and an SMF import path with region readback.

This materially improves the feasibility outlook. It shows that several operations we have been trying to qualify are not merely hypothetical and that reusable implementation patterns exist. We should study/adapt those patterns before asking for more manual target-Mac tests.

It does **not** automatically prove compatibility with our exact Logic 12.0.1 fixture or every required operation, so the final evidence still needs short local qualification.

## Reality check

### Narrow authoritative collaboration MVP

**Feasibility: high based on current evidence.**

A useful companion that can read current MIDI, detect manual edits, perform verified MIDI changes, control the mixer, and adjust parameters on already-present compatible plug-ins is already supported by qualified mechanisms.

### Full intended Co-Producer production-control vision

**Feasibility: still plausible, but not yet proven. Risk is currently medium/high.**

The decisive missing evidence is not AI reasoning; it is reliable construction of Logic state: inserting processors, creating/altering tracks and regions, automation, and routing/sidechains. Those operations depend heavily on undocumented Accessibility/control-surface behavior, so they may require version-specific adapters and fail-closed capability gating.

### Conclusion at this checkpoint

The project is **not at the point where abandoning it is justified**, because multiple difficult control paths already work and strong prior art now exists for some of the remaining ones. But continuing indefinitely with bespoke exploratory AX probes would also be a mistake.

The next session should be a bounded feasibility sprint with explicit go/no-go criteria.

## Resume plan — bounded decision sprint

Do not resume with a large A6–A11 unattended batch.

First spend development time reading/adapting the relevant `logic-pro-mcp` source and reduce each remaining uncertainty to a short target-Mac test. Human testing should be limited to interactions that cannot be established from code/research.

Priority order:

1. **A10: insert one stock effect on the exact `Audio 1` strip, independently verify its identity, then remove it and prove exact restoration.** This is the single most important production-control kill test.
2. **A11: create one disposable software-instrument track/region (or import a deterministic MIDI fixture), independently verify it, then remove it exactly.**
3. **A7: prove one ordinary routing edge and one true sidechain relationship** using the now-qualified/disposable processing context.
4. Only then spend time on A6/A8/A9 unless one of them becomes necessary to support the above mechanisms.

### Time box / pivot rule

Use roughly one focused weekend session, not an open-ended sequence of probes.

- If A10 and at least one of A11/A7 become reliably qualified, continue toward the full production-control foundation.
- If, after applying known prior-art implementations, we still cannot reliably execute and independently verify even a single stock-effect insertion plus one representative construction/routing operation, pivot the product scope.

The fallback scope would retain the already-proven strengths: authoritative MIDI collaboration, mixer control, manual-edit synchronization, and parameter adjustment on existing compatible plug-ins, while unsupported production operations become recommendations/instructions rather than automatic execution.

## Process rule going forward

No more broad test runners containing unproven UI interactions. For any unresolved Logic UI mechanism:

1. research / inspect existing implementation first;
2. write one small fail-closed diagnostic or transaction;
3. target 1–5 minutes of user testing;
4. qualify or reject that exact mechanism;
5. only after it passes, fold it into unattended integration coverage.

This is the active restart point for the next session.
