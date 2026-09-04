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
- A5 — ready for one controlled target-Mac validation through MCU Instrument Edit; no Studio Piano parameter mutation has yet occurred
- A6 — pending
- A7 — pending
- A8 — pending
- A9 — pending

### Immediate next action

Two focused research passes now govern A5:

- `docs/research/research-5-logic-pro-12-a5-ui-terminology.md` established the correct track/channel-strip/instrument-slot/Controls terminology and fixed the structural Studio Piano opener.
- `docs/research/research-6-a5-ax-voiceover-vs-mcu-control-plane.md` investigated why Controls view continued to fail semantically and compared AX/VoiceOver with the already-qualified virtual Mackie Control path.

The latest target-Mac attempt materially advanced A5: the redesigned opener correctly resolved the `Studio Grand` channel strip, structurally identified the occupied `Piano` instrument slot, opened the verified Studio Piano plug-in window, and visibly reached **Controls** view with the expected parameters (`Main Volume`, `Pedal Noise`, `Key Noise`, `Release Samples`, `Sympathetic Resonances`) and sliders. The run still stopped before mutation because the external AX verifier could not prove a deterministic semantic label-to-slider binding.

Deep research changed the architectural decision rather than adding another AX matcher. Apple documents Controls view as a VoiceOver-accessible presentation, but the macOS AX API is for accessibility clients generally and Apple does not document VoiceOver as a prerequisite for another trusted AX client to query the hierarchy. There is therefore no strong evidence that enabling VoiceOver would solve the missing AX relationship. By contrast, Apple explicitly documents Mackie Control **Instrument Edit** as a parameter-editing mode for all automatable instruments, with Logic itself supplying the channel/instrument name, parameter page, parameter names and parameter values to the controller display, and V-Pots editing the corresponding parameters.

A5 is now redesigned as a hybrid control plane:

- **AX** establishes semantic context only: exact `Studio Grand` channel strip and verified Studio Piano instance.
- **virtual MCU/CoreMIDI** owns the parameter transaction: Instrument Mixer/Edit entry, parameter name/value/page feedback, one relative V-Pot step, fresh Logic readback, exact restoration, and an independent fresh Name/Value rerender to prove the restored baseline.

The existing A4 virtual MCU binding is reused; no new control-surface setup is expected on the target Mac. The MCU bridge now captures Logic's 2 × 56-character Mackie LCD buffer and exposes generic Instrument/Plug-in/NAME-VALUE/cursor/V-Pot commands. The public A5 command remains unchanged; `a5-plugin-validation-session.sh` now routes to `a5-mcu-plugin-validation-session.sh`.

The intentional mutation remains isolated in a signal-protected critical section. No parameter mutation occurs until Studio Grand context, persisted MCU binding, Studio Piano Instrument Edit identity, a known safe percentage-style parameter and a readable numeric baseline are all proven. After mutation starts, inability to prove the exact baseline is `A5_SAFETY_FAIL`; an ordinary A5 failure is allowed only before mutation or after verified restoration.

GitHub Actions run #120 (`33888225327`) is green for the MCU redesign code path: Swift build, shell syntax and the retained CoreMIDI bridge smoke test all pass at commit `686c98e09c14634ec40e03a9a13d41724c5bf2b4`.

No raw screenshot or private UI snapshot should be added to the public repository. Summarized structural findings only.

### A5 run history relevant to the handoff

The actual A5 semantic parameter read/write/readback/restore operation has **not yet been reached** in the target-Mac failures below. No Studio Piano parameter was changed in those setup/identity failures.

1. Initial manual setup runner used a timeout. The user could miss the setup window while doing other work.
2. Timeout was removed and replaced with explicit Return confirmation, but the detector falsely rejected a visually correct Studio Piano window because it depended on an unreliable selected-descendant condition.
3. A5 was changed to automatic AX setup. The automation correctly resolved `Studio Grand`, but tried to infer the instrument slot using guessed semantics.
4. A later target-Mac failure reported `studio-piano-instrument-slot-not-resolved`; the user's screenshot confirmed that the slot is plainly present in both Mixer and Inspector and visibly labelled `Piano`. This led to the structural `bypass` / `open` / `list` slot matcher.
5. The next target-Mac attempt proved that redesign: the runner reported `resolved-instrument-slot-structurally-score=135` and opened Studio Piano. The plug-in was visibly in Controls view, but the Controls verifier still failed because the writable parameter relationship could not be proven through the external AX hierarchy. The run stopped before parameter mutation and protected state remained unchanged.
6. Focused AX/VoiceOver-versus-MCU research concluded that another AX/VoiceOver experiment was lower-value than reusing the already-qualified virtual MCU transport. Apple directly documents Mackie Instrument Edit as exposing automatable instrument parameters, names, values and pages. A5 was therefore pivoted to MCU for the parameter transaction while retaining AX for semantic context.

The correct lesson from the repeated failures is not that Studio Piano parameters are inaccessible. The correct plug-in and Controls view were visibly reached. The unstable part was our attempt to infer a private/custom AX representation as though it were a conventional self-labelled AppKit control hierarchy.

### A5 redesign and safety hardening

The structural AX opener remains useful and qualified for context. It treats Mixer and Inspector channel strips as equivalent UI surfaces for the same underlying hosted instrument, finds the exact `Studio Grand` fixture channel strip, recognizes an occupied instrument slot by its direct `bypass` / `open` / `list` structural signature and surrounding `audio plug-in` / `MIDI plug-in` context, and uses the visible short name `Piano` only as fixture confidence rather than canonical plug-in identity. It does not reject an occupied slot merely because AX reports its group as disabled.

The parameter-control part no longer depends on the AX Controls tree. The A5 runner starts the previously-qualified virtual Mackie Control, verifies Logic traffic, uses the AX opener only to bind the exact Studio Grand / Studio Piano context, then sends Mackie Instrument assignment messages. Logic's own MCU display is parsed as eight 7-character columns over a 2 × 56-character backing buffer. The runner locates the Studio Piano instrument column, enters Instrument Edit, pages through parameter assignments, and selects one known safe percentage-style native parameter such as Pedal Noise, Key Noise, Release Samples or Sympathetic Resonance.

In Value display mode the runner captures Logic's own numeric parameter feedback, performs one relative V-Pot step, verifies that the value changed, and numerically homes the parameter back to the exact baseline using fresh Logic feedback rather than assuming `+1` / `-1` symmetry. It then forces a new Name display and a new Value display and requires the same semantic parameter/slot plus the original numeric baseline before restoration is considered proven.

This keeps the strongest safety properties of the previous A5 harness while moving the transaction onto a Logic-supported control-surface mechanism. Any loss of the MCU command/readback path after mutation, any unresolved parameter identity, or any inability to prove the exact baseline becomes `A5_SAFETY_FAIL`.

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

**Status: ready for one controlled target-Mac MCU validation; no semantic Studio Piano parameter mutation has yet been attempted on the target Mac.**

Lean POC target remains unchanged: one controlled native Logic instrument/effect chain, deterministic instance identity, one representative parameter read/write/readback/restore. Third-party AU variability is measured later rather than exhaustively tested now.

The controlled reference is the `Studio Grand` track with the native Studio Piano instrument. The structural AX opener now reliably resolves this context and opens the hosted `Piano` slot, but the repeated Controls-view failures showed that AX is a poor transaction surface for this particular custom plug-in parameter hierarchy.

Research 6 establishes the revised architectural split. Apple explicitly documents Mackie Control Instrument Edit as supporting all automatable software instruments, with instrument names, parameter pages, parameter names and values exposed on the controller display and V-Pots editing those parameters. This is a direct match for A5 and reuses the control plane already proven in A4.

The new A5 runner therefore verifies Studio Grand / Studio Piano context with AX, then performs parameter discovery, baseline read, one change, fresh readback and exact restoration through virtual MCU feedback. It refuses mutation unless a known safe Studio Piano percentage-style parameter is identified and readable. After mutation, exact restoration plus a fresh semantic Name/Value rerender is mandatory.

**Next decision gate:** run the single controlled MCU-based A5 target-Mac validation. If it produces `A5_PASS`, tick A5 off and move directly to the one-session A6-A9 unattended batch. If it produces an ordinary `A5_FAIL` before mutation or with restoration explicitly verified, diagnose only the MCU Instrument Edit mechanism. If it produces `A5_SAFETY_FAIL`, stop mutation work until the protected parameter baseline is proven restored.

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
