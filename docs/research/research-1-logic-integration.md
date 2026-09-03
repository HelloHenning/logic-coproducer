# Research 1 — Logic Integration and State Awareness

**Status:** complete research report; implementation claims below still preserve the report's uncertainty.

## Question

Can a companion become meaningfully session-aware in Logic Pro, observe the current project, detect user changes, make targeted edits and independently verify them—while Logic remains the source of truth?

## Executive conclusion

The report judged a useful, trustworthy Co-Producer feasible enough to pursue, but not through one API. It found no documented public project-object API that exposes all live tracks, regions, MIDI events, automation, mixer channels, plug-ins and routing as first-class external objects.

The recommended direction is a **hybrid reuse/build architecture**: borrow mature controller, Accessibility, CoreMIDI/Mackie-Control, target-binding and verification ideas from existing Logic automation projects; evaluate read-only `.logicx` parsers; build the authoritative state graph and transaction layer specifically for this product; and run focused experiments on the remaining weak interfaces.

## Strong findings

### Mixer/control-surface access is comparatively strong

Logic's Mackie Control implementation and CoreMIDI provide a mature bidirectional surface for transport, fader/pan/mute/solo, sends and some host-exposed plug-in operations. This is a better foundation for those domains than relying only on visual UI automation.

### Accessibility is useful, but should not be the whole architecture

Accessibility can expose many live controls, selection/context states and editor data. It is also vulnerable to UI hierarchy changes, localization, hidden/modal state and opaque third-party plug-in interfaces. Treat it as one qualified adapter.

### `.logicx` is valuable as a saved-state observer

Reverse-engineered saved project data can expose deeper structure than many live public interfaces. It is nevertheless save-driven, undocumented and potentially version-sensitive. It should be read-only and must never be confused with unsaved current Logic state.

### Mutation and observation are different problems

Sending MIDI into Logic can be reliable while still failing to prove what events are stored in a particular region. Similarly, a UI command succeeding does not prove the final project state. Independent readback is therefore a first-class requirement.

## Critical unresolved problem: exact stored MIDI

The report did **not** find a documented external API that can request an arbitrary Logic region and receive its complete live note/event collection.

Logic's Event List itself exposes precise numeric MIDI events and supports editing, making a structured Accessibility adapter a promising path. But exhaustive enumeration, non-visible rows, exact granular mutation and manual-edit re-read remain POC questions.

This is the project's leading architectural gate.

## Automation

The Automation Event List is similarly promising for individual automation events, but complete external enumeration and point-level CRUD through Accessibility remain unproven.

## Recommended synchronization model

The report's core state principle is:

> **Events tell us what may have become stale; refresh tells us what is true.**

AX notifications, control-surface feedback, filesystem/save events and optional telemetry can mark domains dirty. Before reasoning or editing, refresh the relevant dependency set from Logic.

## Existing projects worth studying

Research 1 highlighted several projects as implementation references rather than drop-in solutions:

- [MongLong0214/logic-pro-mcp](https://github.com/MongLong0214/logic-pro-mcp) — strongest current reference in the report for state/readback discipline, target binding and fail-closed behavior.
- [rubenknol/logic-pro-mcp](https://github.com/rubenknol/logic-pro-mcp) — Mackie Control + Accessibility + MIDI round-trip concepts.
- [qinnovates/logic-pro-mcp](https://github.com/qinnovates/logic-pro-mcp) — ambitious multi-channel Logic bridge work.
- [nickfox/chatty-channels](https://github.com/nickfox/chatty-channels) — per-channel AU telemetry + companion/control concepts.

Code reuse requires separate license review. The value of these projects is also architectural: MCP itself is optional and should not be the product's internal state model.

## Highest-priority POCs from Research 1

1. **Event List MIDI census** — enumerate a known region containing notes, CC, pitch bend and articulations; prove completeness.
2. **One-note mutation** — change one note's pitch/start/duration/velocity and prove no unrelated events changed.
3. **Manual MIDI edit detection** — manually add/move/delete/edit notes, then derive the exact fresh diff without AI memory.
4. **Virtual MCU round-trip** — large-track-set feedback and programmatic/manual changes with stable target mapping.
5. **Plug-in inventory/parameter matrix** — native Logic plug-ins plus representative third-party AUs; write and independently read back.
6. **Automation Event List census/CRUD**.
7. **Routing/send/sidechain POC**.
8. **Audio region → source mapping**.
9. **Saved `.logicx` reconciliation**.
10. **State synchronization torture test**.

## Product implication

Do not build the AI UI first. Build a Logic-access laboratory that records raw observations and repeatable fixtures. The strongest remaining uncertainties are about the DAW boundary, not language-model capability.
