# LogicInteroperabilityLab

This is the first empirical proof-of-concept harness for the Logic Co-Producer.

Its initial job is **not** to provide AI features. It is to determine exactly what Logic exposes through macOS Accessibility on the target Mac and to build evidence for POC A1: complete Event List MIDI read.

The first revision is intentionally **read-only**. No command mutates Logic project data.

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

## Automated A1 golden-fixture test

The preferred current A1 workflow is a one-command local runner rather than repeated manual exports.

Prerequisites in Logic:

1. import the corrected synthetic golden fixture;
2. select the fixture region/track to test;
3. keep Event List visible.

Then run from this directory:

```bash
bash Scripts/a1-test.sh
```

By default the script uses:

- expected manifest: `~/Desktop/logic-a1-golden-v2.expected.json`
- evidence directory: `~/Desktop/logic-a1-test`

The runner automatically performs two independent Event List captures. Each capture scrolls the Event List from top to bottom to hydrate virtualized Accessibility cells, restores the original scroll position, and saves the full observed JSON. It then runs `logic-a1-compare`, which:

- detects the active MIDI channel(s);
- reconstructs the deterministic expected Event List semantics for those channel(s);
- compares position, status, channel and qualified MIDI fields exactly;
- checks note lengths exactly;
- checks full hydration coverage;
- compares the two captures for repeatability;
- writes a machine-readable `report.json` and prints `RESULT=PASS` or `RESULT=FAIL`.

The script also saves both capture logs and rejects a capture if the hydration sweep reports a status-order mismatch, warning, or unverified scrollbar restore.

To use a different manifest or evidence folder:

```bash
bash Scripts/a1-test.sh /path/to/fixture.expected.json /path/to/evidence-folder
```

This automation changes only temporary Event List UI scroll position and restores it. It does not edit MIDI or other Logic project data.

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

The Event List path passes only when the evidence proves that, for a known golden fixture:

- every relevant event is enumerated;
- events beyond the initially visible viewport are included;
- no events are duplicated;
- every qualified field is correct;
- filter/editor context cannot silently hide state;
- repeated reads are deterministic;
- completeness is demonstrated rather than assumed.

The automated runner now covers exact golden comparison, off-screen hydration, scroll restoration and repeatability for the active Event List context. Filter/context-state proof remains a separate qualification item until explicitly closed with evidence.

See GitHub issues #1 and #2 and `docs/adr/0005-event-list-midi-adapter.md`.

## Why writes are disabled initially

POC A2 (one-event mutation) explicitly depends on a trustworthy readback path. We do not want to confuse “the UI accepted a write” with “Logic contains exactly the intended result.” Mutation code should only be enabled after POC A1 gives us an independent complete observer.
