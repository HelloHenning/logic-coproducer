# Ordered Proof-of-Concept Plan

_Status: active development plan after Research 4._

The POC order is intentionally designed to answer the fundamental Logic state/control questions **before** AI UI polish, cloud integrations or large audio-analysis work.

## Guiding principle

The first useful product proof is not "AI can generate MIDI." It is:

> **The Co-Producer can observe what is actually in Logic now, make a small reversible change, notice subsequent manual user changes, and reason from the updated authoritative state.**

The validation program is decision-oriented rather than exhaustive. Prove a distinct architectural connection/failure mode, make the decision it unlocks, then move on. Detailed compatibility and regression matrices are deferred until there is a product to harden.

## Phase A — Logic Interoperability Laboratory

### A0 — Build the test harness and golden fixtures

Build a small native macOS harness called **`LogicInteroperabilityLab`**.

Initial responsibilities:

- identify the foreground Logic instance/version;
- obtain current selection/context where possible;
- inspect Accessibility trees and raw attributes without destructive actions;
- record canonical machine-readable observations;
- compare observations with known golden fixtures;
- log Logic/macOS version and test result.

Create synthetic Logic fixtures rather than using private/unpublished music.

**Success criterion:** the lab can run repeatable, non-destructive observations and compare results to golden expected state.

---

### A1 — Complete Event List MIDI read

**Status: PASS for the qualified stored-event subset.**

**Question:** Can the selected Logic MIDI region be reconstructed exactly from Event List Accessibility?

The qualified observer must enumerate the complete controlled fixture, including rows beyond the initial viewport, and match the golden state exactly/repeatably.

**Decision unlocked:** Event List can serve as the preferred live exact-MIDI observer for the qualified stored-event fields.

---

### A2 — Granular MIDI mutation

**Status: PASS for the POC architectural decision.**

Prove one representative stored-event property mutation with full prestate, exact independent readback/diff, no collateral canonical changes, and exact restoration. Additional examples are used only if a materially different targeting or representation failure mode is unresolved.

**Decision unlocked:** granular Event List mutation can proceed into the semantic transaction-engine POC for qualified fields.

---

### A3 — External/manual MIDI edit detection

**Status: PASS for the POC architectural decision.**

Establish a baseline, change Logic independently of the observer's prior intent, refresh through the qualified read path, and prove that the fresh state supersedes stale controller/AI state.

A representative direct Logic pitch edit has already passed: the fresh authoritative reread detected the exact change, a second refresh was deterministic, and restoration returned to baseline. This is sufficient for the core source-of-truth architectural decision.

Additional add/delete/move/resize/velocity matrices are deferred to regression hardening unless a new implementation path raises a distinct failure mode.

**Decision unlocked:** Logic remains the authoritative MIDI source after independent/manual edits.

---

### A4 — Virtual MCU mixer round-trip

Test virtual Mackie Control/CoreMIDI only far enough to establish a robust mixer-control plane.

Lean target:

- one representative stable semantic track/channel-strip binding;
- controller → Logic and Logic → controller state for volume, pan, mute and solo;
- independent Logic readback;
- one banking/reorder stability case only if required to prove mapping stability;
- exact restoration.

**Pass:** required mixer controls operate bidirectionally on the intended semantic target with no wrong-target changes.

---

### A5 — Plug-in inventory and parameter qualification

Use one controlled native Logic instrument/effect chain.

Lean target:

- deterministic instance/slot identity;
- stable semantic parameter surface;
- current value/range read;
- one representative reversible parameter write;
- independent readback and restoration.

Broad native/third-party compatibility matrices are deferred. Third-party AUs remain capability-gated rather than assumed uniform.

---

### A6 — Automation control

Use one controlled automation lane.

Lean target:

- lane/parameter identity;
- complete point read for the fixture;
- one representative reversible point mutation;
- independent readback/diff;
- exact restoration.

Test additional CRUD verbs only if the first operation leaves a distinct architectural question unresolved.

---

### A7 — Routing / send / sidechain

Use one small controlled routing graph.

Lean target:

- one representative send/routing edge with semantic source/destination identity;
- one reversible change;
- independent readback;
- no collateral graph change;
- exact restoration.

Sidechain gets a second representative case only because it is a materially different routing relationship.

---

### A8 — Saved `.logicx` reconciliation

Read only. Never modify the open project package.

Lean target: qualify a useful saved-state subset with explicit saved-only provenance and one representative rename/reorder/move/save reconciliation case.

Unqualified fields remain diagnostic/optional.

---

### A9 — Audio region → source mapping

Use a small synthetic audio fixture to determine the strongest safe mapping claim:

1. associated source file;
2. exact source sample range;
3. exact samples Logic will play after transformations.

Start with a normal trimmed/duplicated region. Add looping/transformation only if needed to determine where the claim stops being exact.

---

## Phase A stop condition

Stop interoperability validation when there is enough representative evidence to choose a viable architecture for each required connection:

- authoritative current MIDI state;
- verified MIDI mutation;
- refresh after independent/manual edits;
- mixer control;
- representative plug-in control;
- representative automation control;
- representative routing control;
- useful saved-state supplementation;
- useful audio-region/source mapping.

Do not continue Phase A merely to accumulate micro-test coverage. Move into the Authoritative State Kernel and Transaction Engine once those architectural gates are answered.

## Phase B — Authoritative state kernel

Once the Phase-A architecture is chosen, implement the domain kernel.

### B1 — Entity model

Initial entity classes:

- Project;
- Track;
- Region;
- MIDI event;
- Plug-in instance;
- Plug-in parameter;
- Bus;
- Send;
- Automation lane;
- Audio asset;
- Analysis artifact.

### B2 — Provenance/completeness

Every factual field stores source, observed time, live/saved status, completeness and confidence/identity confidence where applicable.

### B3 — Dirty domains and refresh levels

Implement fast, targeted and full/deep refresh semantics.

### B4 — Revisions

Implement monotonic project revision and per-entity revisions.

### B5 — Hashes and dependency closure

Implement full-state/audit hashes, request-scope hashes, target/dependency hashes and dependency closure.

### B6 — Stale-response tests

Required semantic cases include unrelated changes that may only warn versus target/dependency changes that must reject stale actions.

---

## Phase C — Transaction engine

Start with a tiny semantic operation registry and implement prestate, capability/precondition validation, semantic preview, immediate revalidation, apply, independent readback, exact verification, transaction record and rollback/restore.

**Success criterion:** a transaction is not marked verified unless current Logic state proves the expected semantic diff exists and unrelated protected state remains unchanged.

---

## Phase D — Local music intelligence

Build only the analysis components needed by actual product decisions, beginning with exact symbolic MIDI/harmony and deterministic local DSP before broader model integrations.

---

## Phase E — Local reasoning

Add a provider-independent local reasoning interface only after state/actions are structured. Measure latency, memory pressure, Logic responsiveness and schema/plan quality rather than committing prematurely to one model family.

---

## Phase F — Manual ChatGPT provider

Create a real handoff from current authoritative state using machine-readable state/analysis/context files. Invalid response data must execute nothing.

---

## Phase G — Optional cloud routing

Only after the same provider-neutral plan path works locally/manual. Paid APIs remain opt-in.

---

# MVP — Authoritative MIDI Collaboration

The first useful MVP should attach to the current Logic project, read exact current MIDI, analyze current musical context, generate a semantic diff, preview/apply/verify it, notice subsequent manual Logic changes, reason from the updated state, and safely undo the last Co-Producer transaction.

## MVP success statement

The MVP passes only if we can truthfully say:

> **Logic remained authoritative after both Co-Producer and manual user edits.**

## No Research 5 prerequisite

There is no broad research phase scheduled before this plan begins. Narrow factual or licensing lookups should be performed only when a concrete implementation decision needs them.
