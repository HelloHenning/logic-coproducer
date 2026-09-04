# POC Validation Status and Strategy

_Status: active — 2026-09-03_

This document records the current interoperability evidence and the testing strategy for the Logic Co-Producer proof of concept.

## Decision-oriented POC rule

The POC is not a product-certification or exhaustive regression program.

The default rule is:

> **Test a distinct architectural connection or failure mode, make the decision it unlocks, then tick it off.**

Do not repeat every micro-variation after a mechanism is clearly proven. Broaden a test only when:

- the result is ambiguous;
- a representative case fails;
- a materially different failure mode exists;
- the architecture depends on a boundary condition that has not yet been exercised.

Examples:

- one or a few representative exact MIDI mutations are enough to qualify the basic write/readback path; dozens of pitch locations are not required for the POC;
- one representative external/manual edit is enough to prove that a fresh Logic read can supersede stale controller state, with additional edit classes used only where they exercise a genuinely different operation;
- one representative native plug-in parameter round-trip can qualify the first plug-in-control connection; broad per-plug-in matrices belong later in product hardening;
- one representative routing/send case and one representative automation case are sufficient to make the initial architecture decision if they are unambiguous and independently verified.

Exhaustive matrices, stress tests, compatibility sweeps and regression coverage are deferred until there is an application worth hardening.

## User-effort rule

Human time is reserved for decisions and unavoidable platform setup.

Preferred test shape:

1. one short setup block;
2. one command;
3. unattended execution;
4. one evidence ZIP;
5. automated restoration and verification.

Independent tests should continue after ordinary failures. Only a safety-critical condition, especially an inability to restore protected Logic state, should stop a batch.

No filler tests, no artificial minimum runtime, and no repeated copy/paste loops merely to gather more examples of an already-qualified mechanism.

Foreground keyboard/menu automation should be isolated into the smallest possible block. Future runners should explicitly distinguish:

- **foreground-sensitive** work, during which the Mac should not be actively used;
- **background-safe** work, during which the user may use other applications normally.

## Current evidence

### A0 — Harness and synthetic fixture

**Status: sufficient for POC continuation.**

The lab builds repeatable synthetic evidence, captures canonical Logic observations and performs independent comparisons/restoration checks.

### A1 — Complete Event List MIDI read

**Status: PASS / complete.**

The qualified Event List observer can reconstruct the 267-event channel fixture exactly after hydration, including events outside the initially visible viewport. Repeat reads match the golden fixture.

Qualified MVP MIDI fields include stored-event position, event type, channel, note/event number, displayed value and duration for the event classes exercised by the synthetic fixture. Release-velocity and full SysEx minutiae are not claimed.

### A2 — Granular MIDI mutation

**Status: PASS / complete for the POC architectural decision.**

A stored MIDI pitch property was changed granularly, independently reread as the exact intended change with no collateral canonical changes, and restored exactly. Representative visible/offscreen cases also passed, but further location-by-location matrices are not required for the POC.

**Decision:** granular Event List mutation remains a viable semantic transaction path for qualified stored MIDI fields.

### A3 — External/manual change detection

**Status: core hypothesis proven; formal issue still open pending lean representative completion.**

A direct Logic edit not derived from the observer's prior state was detected by a fresh authoritative reread; repeated refresh was deterministic; the region restored exactly.

The remaining work should target only distinct edit-operation failure modes, not every possible micro-variation. The unattended external-actor runner is intended to eliminate human repetition while preserving a blind observer/readback test.

### Mixer AX pre-qualification

**Status: useful partial evidence; not the final mixer control plane.**

Five visible channel strips were semantically associated with track/channel-strip labels. Direct Accessibility writes produced clean independent round-trips for Volume and Pan across the tested strips, with exact restoration and no peer-control collateral.

Accessibility `AXPress` for Mute and Solo returned success but independent rereads did not change state. Therefore direct AX Mute/Solo is **not qualified**.

**Decision:** retain AX for semantic/context/readback support where useful; test virtual MCU/CoreMIDI as the stronger mixer-control candidate.

### A4 — Virtual MCU/CoreMIDI mixer

**Status: pending.**

Lean POC target: prove one representative stable track binding with bidirectional volume/pan/mute/solo and independent Logic readback, then add only one banking/reorder case if needed to establish mapping stability.

### A5 — Plug-in inventory and parameter control

**Status: pending.**

Lean POC target: one controlled native Logic instrument/effect chain, deterministic instance identity, one representative parameter read/write/readback/restore. Third-party AU variability is measured later rather than exhaustively tested now.

### A6 — Automation

**Status: pending.**

Lean POC target: one representative automation lane with exact point identity and one reversible point-level operation. Broaden only if the first mechanism is ambiguous.

### A7 — Routing / sends / sidechain

**Status: pending.**

Lean POC target: one controlled routing graph, one representative send/routing mutation, independent readback and exact restoration. Sidechain is a second case only because it is a materially different routing edge.

### A8 — Saved `.logicx` reconciliation

**Status: pending.**

Lean POC target: determine whether a small set of useful saved-project fields can be reconciled reliably with live observations. The saved package remains read-only and supplemental.

### A9 — Audio region to source mapping

**Status: pending.**

Lean POC target: prove the strongest mapping level actually available for one controlled audio fixture, clearly separating source-file association, source sample range and transformed playback claims.

## Current unattended-run provenance note

During the current unattended deep-validation run on 2026-09-03, the user briefly used Chrome for roughly ten seconds before remembering that the run contained foreground-sensitive Logic keyboard/menu automation.

If that evidence shows an otherwise unexplained anomaly specifically around foreground activation, Delete/Undo, menu discovery or similar keyboard-sensitive steps, treat those results as potentially contaminated by foreground focus. Do **not** invalidate unrelated background-safe observations and do **not** rerun the entire suite; rerun only the affected architectural gate if necessary.

## POC stop condition

Phase-A testing should stop once there is enough evidence to choose a viable architecture for each major connection required by the initial Co-Producer:

- authoritative current MIDI state;
- verified MIDI mutation;
- refresh after external/manual edits;
- mixer control;
- representative plug-in control;
- representative automation control;
- representative routing control;
- useful saved-state supplementation;
- useful audio-region/source mapping.

At that point, move into the Authoritative State Kernel and Transaction Engine rather than continuing to accumulate micro-test coverage.

## Evidence policy

Raw Accessibility snapshots and ZIP evidence may contain unrelated Logic UI/history information and should remain local unless sanitized. Public GitHub should contain code, synthetic fixtures, summarized results and sanitized evidence only.
