# Research 7 — Phase-A A6–A9 Logic interface contracts

_Status: focused implementation research — 2026-09-04_

This note records only the external Logic contracts used to design the A6–A9 completion session. It deliberately avoids inferring private UI or project-file structures that Apple does not document.

## A6 — Automation Event List

Apple documents a dedicated **Automation Event List** floating window that contains recorded track-automation data only. The default U.S. key command for **Track Automation Event List** is `Control-Command-E`; Apple notes that users may customize or remove key assignments, so the runner must verify the resulting window/table rather than trusting the keystroke.

Apple also documents editing individual automation events in this list, including position, length and value. For creating a temporary controlled fixture, Logic supports **Create 2 Automation Points at Region Borders** (`Control-Shift-Command-2` in the U.S. default preset) while track automation is shown. The runner may use this only when a selected region and empty pre-existing automation baseline are independently established; otherwise it must fail closed rather than delete unknown automation.

Primary sources:
- https://support.apple.com/guide/logicpro/edit-automation-in-the-automation-event-list-lgcpb1a60a85/10.7/mac/11.0
- https://support.apple.com/guide/logicpro/add-and-adjust-automation-points-lgcpb1a3327b/10.7/mac/11.0
- https://support.apple.com/en-mide/guide/logicpro/lgcpb99be9c5/10.7/mac/11.0

**Implementation contract:** verify a real Automation Event List table, snapshot every row before mutation, mutate one uniquely resolved numeric Value cell, independently rescan, restore the exact baseline, and require a byte-for-byte semantic row snapshot match. If a temporary fixture had to be created from an empty baseline, remove it and prove the list is empty again before A6 is considered safe.

## A7 — Routing

Apple documents channel-strip **Output** slots as destination selectors and **Send** slots as routes to auxiliary destinations. Side-chain source selection is separately documented in the common plug-in window header and is a materially different relationship.

Primary sources:
- https://support.apple.com/guide/logicpro/channel-strip-controls-lgcpbc219210/mac
- https://support.apple.com/guide/logicpro/work-in-the-plug-in-window-lgcpbc21a1fd/mac

**Implementation contract:** qualify one normal routing edge first. The batch uses the exact `Studio Grand` strip and only mutates an Output control if its current `Stereo Out` identity and a unique actionable slot are proven structurally. It may temporarily select `No Output`, independently verify the changed display, then restore `Stereo Out` and compare a routing fingerprint. Side-chain testing is deferred unless normal routing leaves a distinct architectural question unresolved.

## A8 — Saved `.logicx` reconciliation

Apple documents **Save a Copy As** as creating a project copy, including the assets saved with the project. Apple also documents that project state such as software-instrument MIDI and channel-strip/plug-in settings is saved as part of the project, but Apple does **not** document the internal binary schema of a `.logicx` package.

Primary source:
- https://support.apple.com/en-ie/guide/logicpro/lgcpce128e82/mac

Apple documents **Rename Track** and its default U.S. key command `Shift-Return`. A non-default software-instrument track name is used so the test does not trigger the special audio-file/region rename behavior Apple documents for default audio-track names.

Primary sources:
- https://support.apple.com/en-ca/guide/logicpro/lgcp591273b9/mac
- https://support.apple.com/en-mide/guide/logicpro/lgcpb99be9c5/10.7/mac/11.0

**Implementation contract:** create a baseline copy, temporarily rename `Studio Grand` to a unique marker, create a changed copy, restore the live track name, then inspect both copies strictly read-only. A8 passes only if the marker can be found deterministically in the changed saved copy but not in the baseline, the original live name is independently restored, and file hashes prove the parser changed neither copy. This qualifies only an empirical saved-name reconciliation signal, not a stable public `.logicx` schema.

## A9 — Audio region to source mapping

Apple documents that importing an audio file creates a region encompassing the file length. `Shift-Command-I` is the default U.S. **Import Audio File** key command. Apple also documents that the Audio File Editor displays the selected audio region/file and can be opened in a separate window with `Command-6`.

Primary sources:
- https://support.apple.com/en-ca/guide/logicpro/lgcp1bb0ad7d/mac
- https://support.apple.com/en-mide/guide/logicpro/lgcpe8314fe2/mac
- https://support.apple.com/guide/logicpro/audio-file-editor-overview-lgcp21587d1c/mac

**Implementation contract:** generate a disposable synthetic WAV outside the project, import it on exact track `Audio 1`, open the Audio File Editor for the selected imported region, and require the unique source filename to be observable in that selected-region/editor context. Then undo/remove the imported region and prove the marker disappears from project UI. If only the file association is independently demonstrated, A9 passes at **mapping level 1: associated source file only**. Exact source sample range and exact post-transformation playback samples remain explicitly unproven unless additional evidence appears.

## Batch safety rule

A6–A9 run as one session. Ordinary pre-mutation inability to resolve a gate is recorded as `FAIL`/`SKIP` and the next independent gate may continue. Once a gate mutates Logic state, inability to prove restoration is a Phase-A safety failure and stops all later mutation. The evidence ZIP is produced on both normal completion and failure where possible.
