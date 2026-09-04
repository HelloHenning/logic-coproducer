# POC Validation Status and Strategy

_Status: active — 2026-09-04_

This document records the current interoperability evidence, testing strategy, and handoff state for the Logic Co-Producer proof of concept.

## Current handoff

Active branch: `poc/logic-interoperability-lab`

Draft PR: #5

Phase-A / foundational Logic gates:

- A0 — sufficient
- A1 — PASS / complete
- A2 — PASS / complete
- A3 — PASS / complete
- A4 — PASS / complete
- A5 — PASS / complete
- A6 — pending target-Mac validation
- A7 — pending target-Mac validation; must include a true sidechain relationship, not only normal output routing
- A8 — pending target-Mac validation
- A9 — pending target-Mac validation
- A10 — pending: stock Logic plug-in insertion and chain control (#12)
- A11 — pending: representative track/region/stock-instrument construction (#13)

### Immediate next action

**Do not run the existing `Scripts/phase-a-completion-session.sh` as the final completion batch.**

The 2026-09-04 full-scope audit found that the A0–A9 checklist had become narrower than the original product architecture. In particular:

- A5 proves parameter control on an already-existing native Studio Piano instance but does not prove `insert_plugin` or stock processing-chain construction;
- the current A7 runner exercises a normal output edge but not the materially distinct sidechain relationship;
- the product action boundary includes region create/move/duplicate and instrument/source changes, but no representative construction gate was present.

See `docs/poc/scope-audit-2026-09-04.md`.

The next user-facing test should therefore be a **revised single unattended A6–A11 completion batch** that preserves the same safety model: independent gate results, automatic restoration, continuation after ordinary independent failures, and immediate stop only when protected Logic state cannot be proven restored.

The existing A6–A9 runner and `docs/research/research-7-phase-a-a6-a9-interface-contracts.md` remain useful implementation/evidence foundations, but the runner must be extended/reviewed before target-Mac execution.

## Decision-oriented POC rule

The POC is not an exhaustive product-certification program.

> **Test a distinct architectural connection or failure mode, make the decision it unlocks, then tick it off.**

Broaden a test only when a representative result is ambiguous, fails, or leaves a materially different architectural boundary untested. Do not accumulate compatibility matrices or repeated micro-variations after the mechanism is qualified.

Human time is reserved for decisions and unavoidable Logic/macOS setup. Preferred test shape:

1. one short setup block;
2. one command;
3. unattended execution;
4. one evidence ZIP;
5. automatic restoration and verification.

No filler waits or artificial minimum runtimes.

## Safety rules

- Use the synthetic fixture, never unpublished/private songs.
- Never treat an AX/UI action return value as verification.
- No mutation is allowed until its target identity and a readable baseline are independently established.
- Every reversible test restores its baseline and independently verifies restoration.
- Ordinary failures before mutation may continue to the next independent gate.
- Any state-changing test whose restoration cannot be proven becomes a safety failure and stops later mutation.
- Raw screenshots, AX snapshots and evidence ZIPs stay local unless sanitized.

## Qualified evidence

### A1 — complete Event List MIDI read

**PASS / complete.**

The hydrated Event List observer reconstructs the complete 267-event synthetic channel fixture, including rows outside the initial viewport, and repeated reads match the golden fixture. Qualified stored-event fields include position, event type, channel, note/event number, displayed value and duration for the exercised classes.

**Decision:** the Event List is a viable authoritative live-state adapter for the qualified stored-MIDI subset.

### A2 — granular MIDI mutation

**PASS / complete.**

Representative pitch writes were independently reread as exactly the intended semantic change, with no collateral canonical changes and exact restoration.

**Decision:** granular Event List mutation is viable for the qualified fields; broader matrices are deferred to product hardening.

### A3 — external/manual edit detection

**PASS / complete.**

A direct Logic edit independent of observer intent was detected by a fresh authoritative reread, repeated deterministically, and restored exactly. A later over-broad external-actor velocity experiment exposed a rollback bug in the test actor, not a source-of-truth failure; the safety wrapper detected the exact mismatch and the fixture was subsequently recovered and reverified.

**Decision:** fresh Logic state supersedes stale controller/AI intent.

### Mixer AX pre-qualification

Direct AX Volume and Pan round-trips worked on visible mixer strips, while AX Mute/Solo actions reported success without an independently observed state change.

**Decision:** AX remains useful for semantic context and readback, but not as the primary mixer transaction plane.

### A4 — virtual MCU/CoreMIDI mixer

**PASS / complete.**

The virtual Mackie Control bridge produced bidirectional controller↔Logic operation for Volume, Pan, Mute and Solo on representative strip `Audio 1`, with independent Logic readback and exact final restoration.

**Decision:** virtual MCU/CoreMIDI is the qualified representative mixer-control plane.

### A5 — native plug-in parameter control

**PASS / complete for the parameter-transaction mechanism.**

The target-Mac A5 evidence proves:

- exact context: track `Studio Grand`, native Studio Piano;
- AX resolves track/instrument context only;
- virtual Mackie Control enters Instrument Mixer/Edit and receives Logic's own parameter names and values;
- Studio Piano page exposed `Inst`, `MaiVol`, `PedNoi`, `KeyNoi`, `RelSam`, `SymRes`;
- representative parameter `Key Noise` baseline = 35%;
- one MCU V-Pot step produced fresh Logic feedback = 36%;
- mandatory reverse step plus fresh Name/Value rerender returned 35%;
- final `Studio Grand` identity check passed.

Final result:

`RESULT=A5_PASS track=Studio_Grand plugin=Studio_Piano control_plane=virtual_MCU parameter=Key_Noise before=35 changed=36 restored=35 instance_identity=verified read_write_readback=verified restoration=verified`

The earlier Controls-view AX failures remain useful negative evidence: Logic's custom plug-in accessibility hierarchy did not provide a sufficiently deterministic parameter transaction contract. They no longer block A5 because the parameter path is MCU.

**Decision:** qualify a hybrid architecture: AX for semantic context, virtual MCU for representative native plug-in parameter transactions.

**Important boundary:** A5 does not prove native effect insertion, processing-chain construction, bypass/removal, or representative effect-class control. Those are now explicit in A10.

## Pending foundational Logic gates

### A6 — Automation

**Target:** one Automation Event List point with deterministic semantic identity, one numeric write/readback/restore, and an exact final row snapshot.

If a disposable automation fixture is required, it may only be created from a proven safe baseline and must be removed/reverified exactly.

### A7 — Routing / sends / sidechain

**Target:** qualify both a representative normal routing edge and one true sidechain relationship because those are materially different graph operations.

Normal output/send success alone is not enough to mark the original routing/sidechain requirement complete.

### A8 — saved `.logicx` reconciliation

**Target:** a narrow, explicitly empirical saved-project signal without claiming a public `.logicx` schema.

Use read-only saved copies, preserve saved-only provenance and prove the parser does not modify the copies.

### A9 — audio region/source mapping

**Target:** demonstrate the strongest independently checkable mapping level without overclaiming:

1. associated source file;
2. exact source sample range;
3. exact samples played after transformations.

The initial acceptable result may be only mapping level 1 if that is all the evidence supports.

### A10 — stock Logic plug-in insertion and chain control

Issue: #12

**Target:** prove the product can construct and manipulate the native processing chain required by ordinary production and sound recreation, not merely adjust an existing instance.

Representative qualification should cover:

- exact target channel strip;
- native effect insertion and exact slot/instance identity;
- meaningful parameter access/readback;
- bypass/enable where useful;
- removal of disposable instances and exact chain restoration;
- representative effect classes: EQ, dynamics/compression, time-based processing, distortion/saturation.

This remains decision-oriented: prove the distinct control mechanisms, not every stock plug-in and parameter.

The later analysis/reasoning stages—not Phase A—test whether the Co-Producer can choose musically appropriate settings and iteratively optimize them against a description or reference.

### A11 — core track/region/stock-instrument construction

Issue: #13

**Target:** prove representative construction/identity/restoration operations required by composition, arrangement and source/instrument selection:

- create/select a controlled/disposable track where required;
- create one region;
- duplicate or move/resize one region as a structural edit;
- assign/insert one stock software instrument or patch where required;
- independently verify each material change;
- remove/restore the disposable fixture exactly.

## Revised Phase-A stop condition

Foundational Logic interoperability stops once there is enough representative evidence to choose a viable architecture for:

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

At that point, move into the Authoritative State Kernel and Transaction Engine rather than accumulating more proof-of-concept UI micro-tests.

## What remains after foundational Logic validation

Passing these gates does **not** mean the Co-Producer application is nearly finished. Major planned work remains:

- Authoritative State Kernel and synchronization/revision/hash architecture;
- stale-response rejection;
- semantic Co-Producer Plan schema and capability registry;
- Safety Compiler;
- Transaction Engine, verified rollback and Co-Producer undo;
- local symbolic/audio analysis and artifact/cache graph;
- reference-song and described-sound analysis/comparison workflows;
- local reasoning and coexistence testing;
- manual ChatGPT handoff round-trip;
- optional provider routing;
- user-facing app/UX, preview, progress, verification and history;
- later hardening, performance, licensing and distribution work.
