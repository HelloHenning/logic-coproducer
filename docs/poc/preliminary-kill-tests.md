# Preliminary Kill Tests

> **Status:** pre-Research-4. Research 4 is expected to finalize ordering, pass/fail criteria and architectural consequences. These tests are collected now so the project can move immediately into empirical work afterward.

The first experiments should be **Logic-first, not AI-first**.

| # | Test | Core question | Preliminary pass condition | Why it matters |
|---:|---|---|---|---|
| 1 | Event List MIDI census | Can we read every stored event in a selected region? | Exact canonical event set, including non-visible rows and mixed event types | Determines viability of live exact MIDI awareness |
| 2 | One-note mutation | Can we change one stored note granularly? | Pitch/start/duration/velocity change; exact re-read; unrelated events unchanged | Determines granular MIDI editing viability |
| 3 | Manual MIDI edit detection | Does a user edit supersede AI/cache state? | Add/move/delete/edit notes manually; fresh refresh yields exact current diff | Proves source-of-truth principle |
| 4 | Automation Event List CRUD | Can automation points be read and edited completely? | Census + add/change/remove one point + exact readback | Determines point-level automation path |
| 5 | Virtual MCU mixer round-trip | Is mixer state reliably bidirectional at scale? | Stable track mapping; manual/programmatic fader/pan/mute/solo changes reflected correctly | Establishes robust mixer plane |
| 6 | Plug-in inventory/parameter matrix | What can be read/written/verified for native and third-party AUs? | Inventory plus one qualified parameter write/readback per representative class | Defines honest plug-in capability boundary |
| 7 | Routing/send/sidechain | Can production routing be changed and verified? | Send destination/level/pre-post, bus/aux and representative sidechain operations round-trip | Enables real production edits |
| 8 | Audio region → source mapping | Can analysis connect Logic regions to exact source material/ranges? | Trimmed/duplicated/looped regions mapped accurately; characterize takes/Flex limits | Connects Logic state to local audio analysis |
| 9 | `.logicx` reconciliation | How useful is saved-state parsing? | Saved parser and live observers reconcile known fixtures; discrepancies explicit | Defines saved-state role and ID reconciliation |
| 10 | State-sync torture test | Can manual changes across domains invalidate only relevant state? | Dirty domains detected; refresh reconstructs truth; no stale action slips through | Tests state kernel architecture |
| 11 | Source separation with Logic open | Is local ML practical beside the DAW? | Detailed mode finishes within acceptable time without damaging Logic responsiveness/audio | Tests local-analysis feasibility on target Mac |
| 12 | Chorus-energy explanation | Does local evidence produce useful production insight? | Blind reviewers identify explanation as capturing major musical changes and citing real observations | Tests distinctive reference-analysis value |
| 13 | Local LLM coexistence | How large a local model is safe beside representative Logic projects? | Measure latency, memory pressure, thermals, dropouts and DAW responsiveness | Sets local reasoning policy |
| 14 | Manual ChatGPT round trip | Is the first-class handoff practical? | Export → upload → plan → import → validate → preview with acceptable human friction and failure rate | Tests no-paid-API collaboration path |
| 15 | Stale-response rejection | Can delayed AI plans be safely accepted/rejected by scope? | Unrelated edits warn but remain eligible; changed target/dependency invalidates affected action | Tests scoped revision/hash model |
| 16 | Transaction rollback | Can failed/undesired Co-Producer edits be reversed safely? | Verified restore of pre-state without blindly undoing unrelated state | Tests trustworthiness of mutation layer |

## Suggested first fixture for MIDI tests

Use a deterministic synthetic region containing:

- overlapping same-pitch notes;
- multiple MIDI channels;
- CC events;
- pitch bend;
- pressure/aftertouch if available;
- articulation-related events;
- enough events to exceed the visible Event List viewport;
- looped/cropped variants;
- at least one large region (order of 1,000 notes/events) for completeness/performance testing.

Record raw observer output and keep the Logic project fixture versioned so future Logic releases can be regression-tested.

## Test record template

Each experiment should eventually record:

```text
Question
Environment (macOS / Logic / hardware)
Fixture hash/version
Adapter/build version
Procedure
Expected state
Observed raw data
Pass condition
Result: PASS / FAIL / PARTIAL
Known caveats
Architectural consequence
Fallback
Does failure kill product or only feature?
```

## Priority principle

Do not spend early effort polishing chat UI or comparing dozens of AI models before the DAW boundary can demonstrate current-state observation, stable targeting and verification.
