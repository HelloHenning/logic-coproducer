# Logic State and Synchronization — Preliminary

Research 1 is the basis for this document. It focuses on the DAW boundary only; exact behavior still needs proof on the target Logic/macOS environment.

## Access model

No single interface currently appears sufficient. The working design is a capability-qualified hybrid.

| Surface | Intended role | Current status |
|---|---|---|
| Accessibility / AXObserver | live context, selection, track/editor/UI state; some control | useful but UI/version sensitive |
| Event List | exact stored MIDI-event read/write | **critical POC candidate; not proven externally** |
| Automation Event List | automation point read/write | **high-priority POC candidate** |
| Virtual Mackie Control / CoreMIDI | transport, fader/pan/mute/solo, sends and host-exposed controls | comparatively strong |
| `.logicx` parser | deep read-only saved snapshot and reconciliation | useful saved-state plane; never current unsaved truth |
| Project Audio Browser + saved data | audio asset/region reconciliation | promising; offsets/transforms need POC |
| Scripter | realtime MIDI/timing inside an inserted MIDI FX | narrow telemetry only |
| Optional Audio Unit sensor | per-track audio/host timing telemetry | optional; does not unlock host-wide project state |

## Observation vocabulary

Each adapter should be evaluated independently for:

- **Observe** — read structured current state.
- **Detect change** — know that a previously observed domain changed.
- **Refresh** — reconstruct the authoritative current value.
- **Mutate** — make a targeted change.
- **Verify** — independently read back the actual result.

A write returning “success” is not verification.

## State kernel

Every field should carry metadata such as:

- source adapter;
- observed timestamp;
- live vs saved-only;
- completeness;
- confidence/qualification;
- revision;
- dirty/stale status.

The state kernel is a normalized local graph. It is not a replacement for Logic and must not quietly promote cached data to authoritative status.

## Refresh strategy

Research 1's strongest synchronization recommendation is:

> Events tell us what may have become stale; refresh tells us what is true.

Examples of dirty signals include AX notifications, MCU feedback, save/filesystem changes and optional telemetry. Before a request or transaction, refresh the minimum state domains in that operation's dependency closure.

A full project rescan should not be required for every request.

## Stable targets

Track ordinals and display names are not sufficient identity. The Co-Producer will need its own stable references plus reconciliation against current Logic state. The exact stable-ID design remains part of Research 4 / POC work.

At minimum, target resolution should fail closed if the intended entity cannot be uniquely revalidated before a write.

## MIDI uncertainty

Logic's Event List itself can display/edit precise MIDI data, but Research 1 did not find a documented external API for arbitrary region note CRUD. The key experiment is whether Accessibility can exhaustively enumerate and manipulate the Event List, including non-visible rows, while proving completeness.

A pass must include exact re-read after manual edits; AI memory is irrelevant.

## Saved `.logicx` role

Saved project parsing can be deep and valuable, but it is save-driven and undocumented. Use it to corroborate/reconcile saved state and extract otherwise difficult metadata. Do not mutate an open project by editing `.logicx` behind Logic.

## Capability registry

Especially for plug-ins, represent support per operation/instance rather than claiming generic “Logic support.” Example:

```text
Plugin instance X
  inventory read              supported
  parameter enumeration       supported
  semantic parameter mapping  partial
  parameter write             supported
  independent readback        supported
  GUI-specific controls       unsupported
```

The reasoning layer should only be allowed to propose executable operations that the current capability registry says can be safely resolved and verified.
