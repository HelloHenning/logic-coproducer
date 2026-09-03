# Ordered Proof-of-Concept Plan

_Status: active development plan after Research 4._

The POC order is intentionally designed to answer the fundamental Logic state/control questions **before** AI UI polish, cloud integrations or large audio-analysis work.

## Guiding principle

The first useful product proof is not "AI can generate MIDI." It is:

> **The Co-Producer can observe what is actually in Logic now, make a small reversible change, notice subsequent manual user changes, and reason from the updated authoritative state.**

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

The first MIDI fixture should include:

- at least 1,000 notes;
- events beyond the initially visible Event List viewport;
- overlapping same-pitch notes;
- multiple MIDI channels;
- CC events;
- pitch bend;
- channel pressure;
- polyphonic aftertouch where Logic represents it;
- articulation-related events where practical;
- looped/cropped regions;
- intentionally awkward timing/length combinations.

**Success criterion:** the lab can run repeatable, non-destructive observations and compare results to golden expected state.

**Unlocks:** reliable empirical qualification rather than ad-hoc UI scripting.

---

### A1 — Complete Event List MIDI read

**Question:** Can the selected Logic MIDI region be reconstructed exactly from Event List Accessibility?

Build:

- deterministic Event List opener/focus resolver;
- filter-state detector;
- row/cell inspector;
- pagination/scroll strategy for virtualized rows;
- canonical event serializer;
- completeness proof.

The resulting snapshot must capture every relevant event field required to reconstruct the fixture.

**Pass:** canonical observed event collection matches the golden fixture exactly, including events outside the original viewport, with no duplicates or omissions.

**Fail:** any event class/row cannot be deterministically enumerated or completeness cannot be proven.

**Decision unlocked:** whether Event List can become the preferred live exact-MIDI observer.

**If it fails:** implement controlled Standard MIDI File export/readback as the exact-read fallback and continue the overall product architecture with reduced live granularity.

---

### A2 — One-event granular mutation

Only attempt after A1 gives a trustworthy readback surface.

Build the smallest possible safe mutation: change exactly one known MIDI event property, initially preferably velocity or pitch.

Workflow:

1. snapshot authoritative pre-state;
2. resolve one event;
3. make one Event List mutation;
4. re-read the entire relevant region;
5. compute exact diff;
6. confirm the requested event changed and nothing else changed;
7. restore pre-state.

Repeat with start, duration and other event types after the first path works.

**Pass:** exact intended change, no unrelated event changes, independent readback confirms result.

**Fail:** mutation cannot be targeted deterministically, collateral state changes occur, or result cannot be independently verified.

**Decision unlocked:** whether granular stored-event MIDI editing can be a production direction.

**If it fails:** keep Event List as readback if A1 passed, and use controlled SMF/region replacement for mutation.

---

### A3 — Manual MIDI edit detection

Establish a baseline snapshot, then make manual edits directly in Logic without telling the lab what changed:

- add note;
- delete note;
- move note;
- resize note;
- change velocity;
- change another MIDI event.

The lab must refresh the current region and produce the exact new state/diff without reference to its own previous mutation intent.

**Pass:** all manual changes are correctly reflected in the refreshed authoritative snapshot.

**Fail:** stale AI/controller state can survive as if it were current Logic state.

**Decision unlocked:** the core "Logic is source of truth" MIDI hypothesis.

**If it fails:** investigate a stronger refresh/readback path. Write-enabled MIDI collaboration should not proceed until authoritative refresh is reliable.

---

### A4 — Virtual MCU mixer round-trip

Test a virtual Mackie Control/CoreMIDI plane over a deliberately larger track set.

Verify:

- banking/track mapping;
- fader;
- pan;
- mute;
- solo;
- manual changes reflected back to the controller;
- controller changes reflected in Logic;
- stable target binding after reorder/insert where applicable.

**Pass:** no wrong-target operations and reliable bidirectional state.

**Unlocks:** robust mixer plane.

---

### A5 — Plug-in inventory and parameter qualification

Start with native Logic plug-ins, then representative third-party Audio Units.

For each test instance capture capability fields such as:

- inventory read;
- slot/order read;
- parameter enumeration;
- semantic mapping;
- parameter value read;
- parameter write;
- independent readback;
- preset change;
- custom GUI accessibility.

**Pass:** at least the native reference plug-ins support verified semantic parameter operations; third-party variability is measured rather than assumed.

**Unlocks:** capability-registry design and initial plug-in operation set.

---

### A6 — Automation Event List CRUD

Build an automation fixture with volume and a plug-in parameter lane.

Test:

- complete point enumeration;
- parameter/lane identity;
- position/value read;
- add one point;
- modify one point;
- delete one point;
- exact readback/diff.

**Pass:** complete point-level CRUD can be verified without collateral changes.

**If it fails:** qualify broader automation-writing paths; granular point editing stays disabled.

---

### A7 — Routing / send / sidechain

Test:

- send destination;
- send level;
- pre/post where exposed;
- bus/aux resolution/creation as supported;
- compressor sidechain source;
- independent readback.

**Pass:** target and routing graph remain unambiguous and verified.

---

### A8 — Saved `.logicx` reconciliation

Read only. Never modify the open project package.

For controlled saves, compare saved parser output with known live/saved observations across:

- tracks;
- regions;
- MIDI where available;
- plug-ins;
- routing;
- markers/signatures where available;
- benign rename/reorder/move operations;
- save/reopen;
- project alternatives if relevant.

**Pass:** useful saved-state fields can be reconciled with explicit saved-only provenance and stable/qualified identity behavior.

**If it fails:** `.logicx` becomes a diagnostic/optional observer rather than a core state source.

---

### A9 — Audio region → source mapping

Using synthetic audio files and regions, test:

- duplicated regions;
- trimming;
- looping;
- source offsets;
- takes/comps where practical;
- Flex/time/pitch transformations later.

Distinguish:

- "associated source file";
- "exact source sample range";
- "exact samples Logic will play after transformations."

Do not claim the strongest level until it is empirically proven.

---

## Phase B — Authoritative state kernel

Once A1–A3 establish the first viable authoritative MIDI path, implement the domain kernel.

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

Implement:

- full state hash for audit;
- request scope hash;
- target/dependency hashes;
- dependency graph closure.

### B6 — Stale-response tests

Required cases:

- unrelated verse change → warning, action may remain eligible;
- target region changed → target action rejected;
- harmony dependency changed → dependent action rejected;
- plug-in/sidechain dependency changed → affected action rejected.

No stale invalid action may reach mutation code.

---

## Phase C — Transaction engine

Start with a tiny semantic operation registry:

- `add_note`;
- `remove_note`;
- `move_note`;
- `change_velocity`.

Implement:

1. pre-state capture;
2. capability/precondition validation;
3. semantic preview;
4. short revalidation immediately before write;
5. apply;
6. independent readback;
7. exact expected-vs-observed verification;
8. transaction record;
9. inverse/restore operation;
10. rollback test.

**Success criterion:** a transaction is not marked verified unless current Logic state proves the expected semantic diff exists and unrelated protected state remains unchanged.

---

## Phase D — Local music intelligence

Do not begin by integrating every model from Research 2.

Recommended order:

1. exact symbolic MIDI representation and simple harmony layer;
2. deterministic local DSP primitives;
3. beat/downbeat engine;
4. one license-qualified source-separation path;
5. drum/bass targeted analysis;
6. bar-aligned energy/arrangement difference engine;
7. evidence-backed explanation layer.

Quick/Detailed/Maximum should alter the actual analysis graph.

---

## Phase E — Local reasoning

Add a provider-independent local reasoning interface only after state/actions are structured.

Test small, normal and optional deeper model classes while Logic is actually running.

Measure:

- latency;
- unified-memory pressure;
- thermal state;
- Logic responsiveness;
- audio underruns/dropouts;
- schema/plan quality.

The target normal model class is an engineering hypothesis, not a permanent model family.

---

## Phase F — Manual ChatGPT provider

Create a real handoff from current authoritative state:

```text
manifest.json
request.md
current_state.json
harmony.json
midi.json
analysis.json
creative_context.json
optional media
```

Test:

- export;
- manual upload;
- explanation + semantic JSON response;
- paste/drop import;
- schema/precondition validation;
- preview;
- transaction;
- verification.

Invalid JSON must execute nothing.

---

## Phase G — Optional cloud routing

Only after the same provider-neutral plan path works locally/manual.

Initial candidates may change over time, so keep them behind adapters and runtime capability data.

The initial architectural order is:

1. free structured-text provider prototype;
2. privacy-gated multimodal/audio provider;
3. optional paid general-reasoning challenger;
4. additional providers only if the Co-Producer benchmark justifies them.

Paid APIs remain off by default.

---

# MVP — Authoritative MIDI Collaboration

The first useful MVP should:

1. attach to current Logic project;
2. enumerate enough current context to identify the selected MIDI region;
3. read exact current MIDI;
4. analyze current harmony locally;
5. accept a constrained musical-development request;
6. generate a semantic MIDI diff;
7. preview it;
8. apply it granularly where the adapter permits;
9. independently verify the resulting Logic state;
10. let the user manually edit Logic;
11. re-read the manual changes;
12. answer a second request using the updated current state rather than stale AI history;
13. undo the last Co-Producer transaction safely.

Optional after the core flow works: produce/import a manual ChatGPT alternative using the same state and action schema.

## MVP success statement

The MVP passes only if we can truthfully say:

> **Logic remained authoritative after both Co-Producer and manual user edits.**

## No Research 5 prerequisite

There is no broad research phase scheduled before this plan begins. Narrow factual or licensing lookups should be performed only when a concrete implementation decision needs them.
