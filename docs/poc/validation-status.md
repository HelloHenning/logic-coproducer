# POC Validation Status and Strategy

_Status: active — 2026-09-04_

This document records the current interoperability evidence, testing strategy, and current handoff state for the Logic Co-Producer proof of concept.

## Current handoff — 2026-09-04

Active branch: `poc/logic-interoperability-lab`

Draft PR: #5

Phase-A gate state:

- A0 — sufficient
- A1 — PASS / complete
- A2 — PASS / complete
- A3 — PASS / complete
- A4 — PASS / complete
- A5 — pending; **do not run another target-Mac A5 attempt yet**
- A6 — pending
- A7 — pending
- A8 — pending
- A9 — pending

### Immediate next action

Before another A5 runner is sent to the target Mac, perform a focused terminology/UI-structure research pass for Logic Pro 12.0.1. The recent A5 failures were setup-harness failures caused by incorrect assumptions about Logic's exposed plug-in-slot semantics, not failures of the actual parameter round-trip.

Research should establish and document, using Apple documentation first and corroborating sources only where useful:

- Track vs channel strip terminology and identity.
- Mixer channel strip vs Inspector channel strip and how both expose the same software instrument.
- Software-instrument slot / instrument plug-in slot terminology versus Audio FX insert slots and MIDI FX slots.
- Plug-in window terminology, including Editor vs Controls view and the View/zoom control.
- Known Logic key commands or menu commands for opening the focused track's instrument plug-in, without silently altering the user's key-command assignments.
- The relationship between visible slot labels (for the controlled fixture the slot is visibly labelled `Piano`) and Accessibility structure.
- Existing AX evidence showing a hosted instrument represented as a plug-in-specific group with child controls such as `bypass`, `open`, and `list`.

After that research, redesign A5 setup automation from the actual Logic structure rather than guessed strings. The controlled fixture visibly exposes the same green `Piano` instrument slot both in the Studio Grand Mixer strip and in the Inspector channel strip. The latest failed A5 matcher searched for `Studio Piano`, `software instrument`, or `instrument slot`, returned zero candidates, and aborted before any plug-in parameter mutation. That matcher is therefore not authoritative evidence about whether the Mixer route exists.

No raw screenshot or private UI snapshot should be added to the public repository. Summarized structural findings only.

### A5 run history relevant to the handoff

The actual A5 semantic parameter read/write/readback/restore operation has **not yet been reached** in the failed runs below. No Studio Piano parameter was changed in those setup failures.

1. Initial manual setup runner used a timeout. The user could miss the setup window while doing other work.
2. Timeout was removed and replaced with explicit Return confirmation, but the detector falsely rejected a visually correct Studio Piano window because it depended on an unreliable selected-descendant condition.
3. A5 was changed to automatic AX setup. The automation correctly resolved `Studio Grand`, but tried to infer the instrument slot using guessed semantics.
4. Latest target-Mac failure after commit `b73f6eaaad027ef7efb5f255ad2bcbfb9abb345a` reported:
   `RESULT=FAIL reason=studio-piano-instrument-slot-not-resolved actions=Studio-Grand-already-selected,instrument-slot-candidates-studio=0-generic=0`
   The user's screenshot then confirmed that the instrument slot is plainly present in both Mixer and Inspector and is visibly labelled `Piano`.

The correct lesson is not "the Mixer branch is wrong." The lesson is that the current AX matcher is looking for the wrong semantic labels / structure.

### Workflow after A5

Once A5 is qualified, do not return to one-short-test-at-a-time handoffs. Prepare A6-A9 as one unattended Phase-A completion session wherever safety permits: one setup, one command, one evidence ZIP, independent gate results, automatic restoration, and continuation past ordinary independent failures. Stop the batch only when protected Logic state cannot be proven restored or another genuine safety condition exists.

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

If a runner requires human input or a Logic/macOS setup action, it must **wait indefinitely for explicit Terminal confirmation** (normally pressing Return) rather than timing out. The user should be free to leave the computer and come back later without losing the run. Automatic polling with a bounded timeout is reserved for machine-only/background-safe steps that do not require human attention.

Prefer automating Logic setup itself when it can be done deterministically and safely. Do not delegate repetitive UI preparation to the user merely because it is convenient for the harness.

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

**Status: PASS / complete for the POC architectural decision.**

A direct Logic edit not derived from the observer's prior state was detected by a fresh authoritative reread; repeated refresh was deterministic; the region restored exactly. This is sufficient to establish the architectural requirement that fresh Logic state supersedes stale controller/AI intent.

The later unattended external-actor matrix is not required to complete A3. In that run, position and length actor writes safely skipped. A velocity `AXIncrement` unexpectedly changed one note's displayed velocity from 72 to 80 rather than the actor's assumed +1 step; the actor then classified the case as SKIP and its stale-element fallback failed to restore that changed value. The safety wrapper correctly detected the single-event mismatch and stopped all further mutation. This is a harness-safety bug, not evidence that authoritative refresh failed.

The affected event was row 9 of the qualified channel-1 fixture: Note E2 at position `1 3 1 2`, velocity 72 -> 80. No other canonical row or field differed in the recovery snapshot. An early targeted recovery attempt did not complete cleanly and left that same event at displayed velocity 79. From that point, automated mutation was disabled for any unrecognized state. The event was manually restored to velocity 72, and a final full read-only 267-event comparison returned:

`RESULT=RECOVERY_PASS full_region_matches_protected_baseline already_restored=true exact_raw_match=true`

The controlled fixture is therefore confirmed back at the exact protected baseline.

**Decision:** tick A3 off. Broader add/delete/move/resize/velocity matrices are deferred to later regression/product hardening.

### Mixer AX pre-qualification

**Status: useful partial evidence; not the final mixer control plane.**

Five visible channel strips were semantically associated with track/channel-strip labels. Direct Accessibility writes produced clean independent round-trips for Volume and Pan across the tested strips, with exact restoration and no peer-control collateral.

Accessibility `AXPress` for Mute and Solo returned success but independent rereads did not change state. Therefore direct AX Mute/Solo is **not qualified**.

**Decision:** retain AX for semantic/context/readback support where useful; virtual MCU/CoreMIDI is the stronger qualified mixer-control plane.

### A4 — Virtual MCU/CoreMIDI mixer

**Status: PASS / complete for the POC architectural decision.**

The target-Mac run proved a stable representative binding to the visible `Audio 1` strip and bidirectional operation for Volume, Pan, Mute and Solo through the virtual MCU/CoreMIDI bridge. Logic-to-controller feedback was observed and independent Logic AX readback verified the intended state.

During the Solo case, Logic also placed other strips into its solo-induced mute state. A generic single-control-diff checker initially printed a scary `FAIL changed=[...]` line, but this was expected Logic solo semantics rather than wrong-target mutation: pressing Solo again restored the affected Solo/Mute states exactly.

Final full mixer verification matched the starting 20-control state exactly.

**Decision:** virtual MCU/CoreMIDI is qualified as the primary representative mixer control plane for the POC. A4 is ticked off; issue #6 is closed.

### A5 — Plug-in inventory and parameter control

**Status: pending; setup harness under redesign.**

Lean POC target remains unchanged: one controlled native Logic instrument/effect chain, deterministic instance identity, one representative parameter read/write/readback/restore. Third-party AU variability is measured later rather than exhaustively tested now.

The controlled reference is the `Studio Grand` track with the native Studio Piano instrument. The user's latest screenshot confirms that the same green `Piano` instrument slot is reachable from both the Mixer channel strip and the Inspector channel strip.

The latest automatic setup runner correctly recognized that Studio Grand was already selected, then failed before opening the plug-in because its candidate matcher searched for semantics such as `Studio Piano`, `software instrument`, or `instrument slot` and found zero matches. Earlier AX evidence from another native instrument shows a hosted instrument represented as a plug-in-specific group with child controls including `bypass`, `open`, and `list`. That evidence should guide the redesign.

**Important:** no failed A5 target-Mac run to date has reached the actual parameter mutation stage. Do not interpret these setup failures as evidence against native plug-in parameter control.

**Next decision gate:** first complete focused Logic terminology/UI-structure research, then implement one deterministic opener based on the actual channel-strip / instrument-slot structure, with Mixer and Inspector routes treated as equivalent surfaces for the same hosted instrument where appropriate. Do not send another speculative A5 runner to the user before this is done.

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

## Unattended-run provenance note

During the unattended deep-validation run on 2026-09-03, the user briefly used Chrome for roughly ten seconds before remembering that the run contained foreground-sensitive Logic keyboard/menu automation.

The actual abort occurred earlier in a direct Accessibility velocity-value step, before the foreground-sensitive Delete/Undo/menu stages. The evidence shows a single deterministic velocity change (72 -> 80) consistent with Logic's `AXIncrement` step behavior and the actor's own stale fallback logic. Chrome is therefore not the leading explanation for this failure.

If future evidence shows an anomaly specifically around foreground activation, Delete/Undo, menu discovery or similar keyboard-sensitive steps, treat those results as potentially contaminated by foreground focus. Do **not** invalidate unrelated background-safe observations and do **not** rerun an entire suite; rerun only the affected architectural gate if necessary.

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

Raw Accessibility snapshots, screenshots and ZIP evidence may contain unrelated Logic UI/history information and should remain local unless sanitized. Public GitHub should contain code, synthetic fixtures, summarized results and sanitized evidence only.
