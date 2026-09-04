# POC Validation Status and Strategy

_Status: active — 2026-09-04_

This document records the current interoperability evidence, testing strategy, and handoff state for the Logic Co-Producer proof of concept.

## Current handoff

Active branch: `poc/logic-interoperability-lab`

Draft PR: #5

Phase-A gates:

- A0 — sufficient
- A1 — PASS / complete
- A2 — PASS / complete
- A3 — PASS / complete
- A4 — PASS / complete
- A5 — PASS / complete
- A6 — pending target-Mac batch validation
- A7 — pending target-Mac batch validation
- A8 — pending target-Mac batch validation
- A9 — pending target-Mac batch validation

### Immediate next action

Run the single unattended `Scripts/phase-a-completion-session.sh` target-Mac session. It attempts A6–A9 independently, produces one evidence ZIP, continues after ordinary pre-mutation failures, and stops only when protected Logic state cannot be proven restored.

The batch implementation is governed by `docs/research/research-7-phase-a-a6-a9-interface-contracts.md` and passed GitHub Actions CI #128 for Swift build, shell syntax, and the CoreMIDI bridge smoke test.

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

**PASS / complete.**

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

## Pending Phase-A completion gates

### A6 — Automation

**Target:** one Automation Event List point with deterministic semantic identity, one numeric write/readback/restore, and an exact final row snapshot.

The batch first reads any existing Automation Event List data. If the selected `Studio Grand` track has no automation, it may create a disposable two-point fixture at selected-region borders using Logic's documented automation command, but only from a proven empty baseline. Temporary points must be removed and the empty baseline reproven.

A customized/missing default key command or an unresolvable table is an ordinary pre-mutation failure, not a reason to alter the user's key-command configuration.

### A7 — Routing / sends / sidechain

**Target:** one representative normal output edge before testing sidechain as a distinct case.

The batch attempts exact `Studio Grand` routing `Stereo Out -> No Output -> Stereo Out`, only after proving a unique actionable Output slot and both menu destinations. It requires changed-state readback and an exact routing fingerprint restoration. Sidechain remains deferred unless this normal-routing result leaves a separate architectural question.

### A8 — saved `.logicx` reconciliation

**Target:** a narrow, explicitly empirical saved-project signal without claiming a public `.logicx` schema.

The batch uses Logic's `Save a Copy As` to create a baseline copy, temporarily renames non-default instrument track `Studio Grand` to a unique marker, saves a changed copy, restores the live track name, and inspects both copies read-only. A8 passes only if the marker is deterministically present in the changed saved copy but not the baseline and hashes prove the parser modified neither copy.

Qualified claim if successful: **empirical saved track-name reconciliation only**.

### A9 — audio region/source mapping

**Target:** demonstrate the strongest independently checkable mapping level without overclaiming.

The batch generates a disposable synthetic WAV, imports it on exact track `Audio 1`, opens the selected region in Logic's Audio File Editor, and looks for the unique source filename in that editor context. It then undoes the import and verifies that the generated source no longer appears in the main Tracks window.

If successful, the initial qualified claim is intentionally limited to:

**mapping level 1 — associated source file only.**

Exact source sample range and exact samples played after transformations remain unproven unless later evidence directly demonstrates them.

## Phase-A completion runner

`experiments/logic-interoperability-lab/Scripts/phase-a-completion-session.sh`

Expected evidence archive:

`~/Desktop/logic-coproducer-tests/coproducer-phase-a-completion.zip`

The runner reports each gate separately (`A6`, `A7`, `A8`, `A9`) plus a final safety/restoration summary. A partial gate result does not invalidate independent passes.

## POC stop condition

Phase-A stops once a viable architecture has been chosen for:

- authoritative current MIDI state;
- verified MIDI mutation;
- refresh after external/manual edits;
- mixer control;
- representative plug-in control;
- representative automation control;
- representative routing control;
- useful saved-state supplementation;
- useful audio-region/source mapping.

At that point, move into the Authoritative State Kernel and Transaction Engine rather than continuing to accumulate proof-of-concept micro-tests.
