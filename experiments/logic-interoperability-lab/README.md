# LogicInteroperabilityLab

This is the first empirical proof-of-concept harness for the Logic Co-Producer.

Its initial job is **not** to provide AI features. It is to determine exactly what Logic exposes through macOS Accessibility on the target Mac and to build evidence for POC A1: complete Event List MIDI read.

The first revision is intentionally **read-only**. No command mutates Logic.

## Requirements

- macOS
- Logic Pro running
- Swift 6 toolchain / Xcode command-line tools
- Accessibility permission for the built `logic-lab` executable / Terminal host as required by macOS

Use only synthetic or otherwise shareable Logic fixtures while collecting diagnostics for the public repository.

## Build

```bash
cd experiments/logic-interoperability-lab
swift build
```

Or run commands directly with `swift run logic-lab ...`.

## Step 1 — environment / Accessibility check

Open Logic Pro, then run:

```bash
swift run logic-lab doctor --prompt-accessibility
```

If macOS opens Privacy & Security → Accessibility, grant the requested access. Depending on how Swift is launched, macOS may list Terminal (or your terminal app) rather than `logic-lab` itself.

Run again without the prompt:

```bash
swift run logic-lab doctor
```

We want to record:

- exact macOS version;
- exact Logic version;
- Logic bundle identifier/path;
- whether Accessibility is trusted;
- focused Logic window summary.

## Step 2 — inspect Logic windows

```bash
swift run logic-lab windows
```

This helps establish whether Logic's Event List is a separate AX window/panel or embedded elsewhere on the target configuration.

## Step 3 — inspect the focused Event List context

In Logic:

1. use a synthetic MIDI region;
2. open the Event List for that region;
3. click an Event List row/cell so the editor has focus.

Then run:

```bash
swift run logic-lab focused
```

This prints the focused AX element followed by its parent chain. It is often the fastest way to discover how Logic exposes the editor semantically.

## Step 4 — semantic searches

Try:

```bash
swift run logic-lab find "Event List"
swift run logic-lab find "Position"
swift run logic-lab find "Status"
swift run logic-lab find "Channel"
swift run logic-lab find "Value"
swift run logic-lab find "Length"
```

If needed, increase traversal limits:

```bash
swift run logic-lab find "Position" --depth 18 --max-nodes 50000
```

The goal is to identify the AX table/outline/row/cell structure, not merely find visible text.

## Step 5 — bounded AX snapshot

For a shareable synthetic fixture only:

```bash
swift run logic-lab snapshot \
  --out /tmp/logic-event-list-ax.json \
  --depth 16 \
  --max-nodes 50000
```

The snapshot intentionally stores only a small semantic subset per AX element: role, subrole, title, identifier, description, simple scalar value, enabled/focused state, and children.

Review the output before sharing it. Logic UI strings can include project, track, region, plugin or other user-provided names.

## POC A1 pass condition

This scaffold does **not** claim POC A1 is solved.

The Event List path passes only when later code can prove that, for a known golden fixture:

- every relevant event is enumerated;
- events beyond the initially visible viewport are included;
- no events are duplicated;
- every qualified field is correct;
- filter/editor context cannot silently hide state;
- repeated reads are deterministic;
- completeness is demonstrated rather than assumed.

See GitHub issues #1 and #2 and `docs/adr/0005-event-list-midi-adapter.md`.

## Why writes are disabled initially

POC A2 (one-event mutation) explicitly depends on a trustworthy readback path. We do not want to confuse “the UI accepted a write” with “Logic contains exactly the intended result.” Mutation code should only be enabled after POC A1 gives us an independent complete observer.
