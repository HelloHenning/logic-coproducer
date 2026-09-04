# Logic Co-Producer Scope Audit — 2026-09-04

## Purpose

This audit reconciles the original product vision, final architecture, current proof-of-concept plan, and the live-verified Logic evidence. It exists because the current A0–A9 interoperability checklist became narrower than the product capabilities already present in the architecture and original scope.

## Product definition

The Logic Co-Producer is a local macOS companion intended to behave like a knowledgeable songwriting/production collaborator sitting beside the user while Logic Pro remains the authoritative factual source of truth.

It must be able to:

- understand the current Logic session rather than stale AI history;
- preserve separate creative memory and current factual DAW state;
- inspect and develop MIDI, harmony, arrangement and regions;
- reason about and control mixer, plug-ins, routing, sidechains and automation where those operations can be independently verified;
- analyze project and reference audio locally where practical;
- infer measurable/likely production characteristics without pretending rendered audio uniquely reveals hidden production history;
- recreate or approach described/reference sounds by selecting sources/instruments, building processing chains, setting parameters, listening/analyzing the result, comparing against the target, and iterating;
- propose small semantic operations rather than raw UI actions;
- preview, validate, apply, independently verify, restore and undo Co-Producer transactions safely;
- use local reasoning normally, manual ChatGPT as a first-class provider, and optional cloud providers without requiring paid APIs for core function.

## Original semantic operation scope

The architecture already includes semantic verbs such as:

- MIDI: add/remove/move/resize notes, velocity changes;
- regions: create/move/duplicate;
- mixer: level/pan and related qualified controls;
- plug-ins: insert plug-in, set plug-in parameter, set sidechain;
- routing: create send, change send level;
- automation: create automation points;
- arrangement: create marker;
- suggestion-only actions where execution is not qualified.

Therefore plug-in insertion/chain construction was never a new feature request; it was already part of the intended action boundary.

## Live-verified Logic evidence to date

- A0 harness: sufficient.
- A1 complete Event List MIDI read: PASS for the qualified stored-event subset.
- A2 granular MIDI mutation: PASS with independent full-region readback and exact restoration.
- A3 independent/manual MIDI edit refresh: PASS; current Logic state supersedes stale observer history.
- A4 virtual MCU mixer round-trip: PASS for representative Volume/Pan/Mute/Solo with Logic feedback and restoration.
- A5 native plug-in parameter control: PASS on Studio Piano; known instance identity plus MCU parameter name/value feedback and one reversible parameter transaction.

## Pending current A6–A9 gates

- A6 automation point control.
- A7 routing/send/sidechain.
- A8 saved `.logicx` reconciliation.
- A9 audio-region/source mapping.

The current combined A6–A9 runner should not be treated as the final Phase-A completion runner yet because the audit identified missing foundational control cases.

## Gaps found in the current Phase-A checklist

### 1. Stock plug-in insertion and chain management — missing and essential

A5 proves parameter control on an already-existing native instrument. It does **not** yet prove the product can construct the processing chain required for normal production or sound recreation.

Required representative qualification:

- insert a native Logic effect on the intended channel strip;
- identify the exact inserted instance/slot;
- enumerate/use its semantic parameter surface;
- set and read back meaningful parameters;
- bypass/enable where needed;
- remove the temporary effect and prove the original chain is restored;
- prove enough representative native effect classes to support the product's core production workflow, without turning this into an exhaustive stock-plug-in matrix.

Representative classes should include at least EQ, dynamics/compression, time-based processing (reverb/delay), and distortion/saturation. Parameter optimization quality itself belongs to the later analysis/reasoning stages; Phase A only proves reliable control.

### 2. Sidechain relationship — current batch is insufficient

A sidechain source is a materially different routing relationship from a normal output/send edge. The existing A7 combined runner currently exercises only an output-route change, so it does not yet satisfy the intended routing/sidechain scope.

### 3. Core track/region/instrument construction operations — missing representative qualification

The product scope includes composition/arrangement and semantic operations such as region create/move/duplicate. The user may also ask for a different instrument/source while recreating a sound. The current A0–A9 checklist does not explicitly qualify representative creation/identity/restoration for these operations.

A lean representative qualification should cover:

- create/select a controlled track or safely use a disposable one;
- create/duplicate/move/resize at least one region through the chosen control path;
- assign or insert one stock software instrument/patch where needed;
- independently verify identity/state;
- restore/remove the disposable fixture.

This should remain decision-oriented rather than becoming a full track/region editing matrix.

### 4. The broader safety/product phases remain largely unimplemented

Even after Logic interoperability is qualified, the actual product still needs:

- Authoritative State Kernel: normalized entities, provenance/completeness, dirty domains, stable local IDs, revisions, hashes, dependency closure and refresh logic;
- stale-response rejection tests;
- provider-neutral Co-Producer Plan schema and operation registry;
- Safety Compiler;
- Transaction Engine with pre-state capture, independent verification, rollback and Co-Producer undo;
- local music/audio analysis pipeline and artifact/cache graph;
- reference-song analysis and sound/mix comparison workflows;
- local reasoning integration and coexistence testing;
- manual ChatGPT handoff round-trip;
- optional provider routing;
- user-facing app/UX, history, preview, progress and verification surfaces;
- later compatibility hardening, performance, licensing and distribution work.

## Revised empirical order

1. Do not run the existing A6–A9 completion batch unchanged.
2. Revise the final Logic-interoperability batch so one unattended session covers:
   - automation point transaction;
   - normal routing plus one sidechain case;
   - saved `.logicx` reconciliation;
   - audio-region/source mapping;
   - stock Logic effect insertion/identity/parameter/control/removal across representative effect classes;
   - representative track/region/instrument construction operations.
3. Stop only on restoration/safety failure; ordinary independent failures should continue and be recorded.
4. After this revised Logic qualification, move immediately into the Authoritative State Kernel and Transaction Engine rather than accumulating more UI micro-tests.
5. Then build local music/audio analysis, reference/sound-matching workflow, local reasoning, ChatGPT handoff, provider routing and UX in that order.

## Progress interpretation

Do not use one vague percentage for “Logic support.” Report separately:

- research/architecture completion;
- empirical Logic-interoperability qualification;
- actual product implementation;
- user-dependent validation remaining.

The project is much further along in architecture/research than in product implementation. Passing Phase A does not mean the Co-Producer application itself is close to finished; it means the critical Logic control architecture is sufficiently understood to build the product safely.
