# Architectural Kill Tests

_Status: finalized after Research 4._

These tests determine whether a proposed capability is trustworthy enough to become executable product behavior. A failed test does not automatically kill the whole product; most failures reduce one capability and activate a fallback architecture.

The two strongest product-level safety gates are **stale-response rejection** and **transaction rollback/restore**. No write-enabled release should bypass them.

| # | Test | Question | Pass condition | Fail condition | Architectural consequence | Fallback | Product impact |
|---|---|---|---|---|---|---|---|
| 1 | Complete Event List MIDI read | Can we reconstruct the authoritative selected-region event collection exactly? | Golden fixture exactly reproduced, including >viewport events and all qualified event types, with completeness proof | Missing/duplicate/ambiguous events or inability to prove completeness | Event List cannot be the authoritative exact live MIDI observer | Controlled SMF export/readback + saved-state corroboration | **Does not kill product; granular live MIDI downgraded** |
| 2 | One-event granular mutation | Can one stored MIDI event be changed without collateral edits? | Exact requested event/property changes; full region re-read proves all unrelated events unchanged | Wrong event, collateral diff or no independent readback | Disable granular Event List writes | Controlled SMF/region replacement; suggestion-only where needed | No |
| 3 | Manual MIDI edit detection | Does a refresh use current Logic state after human edits? | Manual add/delete/move/resize/value edits are reflected exactly without relying on controller intent/history | Stale snapshot can masquerade as current state | MIDI source-of-truth path is not trustworthy yet | Stronger exact refresh path/export before reasoning | **Blocks authoritative MIDI MVP until fixed** |
| 4 | Automation Event List point CRUD | Can complete automation point state be read and changed surgically? | Complete lane/parameter identity and exact point add/change/delete/readback | Incomplete/unstable enumeration or collateral edits | Disable granular point editing | Qualified broader automation writes or suggestion-only | No |
| 5 | Virtual MCU mixer round-trip | Is MCU/CoreMIDI a stable bidirectional mixer plane? | Correct fader/pan/mute/solo mapping and host feedback across banking/manual/programmatic changes; zero wrong targets | Mapping drift, missing feedback or wrong-target write | Reduce MCU scope or revise stable-target binding | AX for narrower qualified operations | Serious but not whole-product kill |
| 6 | Plug-in inventory/parameter read-write | Can qualified plug-in state be semantically read, written and verified? | Native reference plug-ins expose slot/parameter identity, units/ranges where required, write and readback | Parameters opaque, unstable or unverifiable | Capability-gate unsupported plug-ins/parameters | Read-only/suggestion-only or plug-in-specific adapter | No |
| 7 | Third-party plug-in variability | How much generic support survives across arbitrary AUs? | Representative sample establishes useful generic tier with explicit per-instance capability records | Wide opacity/inconsistent semantics | Do not promise universal third-party semantic control | Verified vendor/plugin adapters only | No |
| 8 | Routing/sidechain creation | Can sends/buses/sidechains be manipulated with stable targets and readback? | Destination/level/pre-post/sidechain changes independently verified | UI-only ambiguity, wrong source/destination or no readback | Narrow executable routing set | Partial routing or suggestion-only | No |
| 9 | Audio-region → source mapping | Can a Logic region be related to its source and exact played range? | Synthetic trimmed/duplicated/looped fixtures map correctly at claimed semantic level | Source/range/transform remains ambiguous | Downgrade representation to weaker level (associated file only, source range unknown, etc.) | Analyze rendered/explicit exports instead | No |
| 10 | `.logicx` saved-state reconciliation | Is reverse-engineered saved state useful without confusing stale/historical objects? | Saved snapshot agrees with controlled project state, carries saved-only provenance and reconciles identities at an accepted confidence | Active/historical/alternative state cannot be reliably distinguished | Remove parser from authoritative paths | Live adapters only; parser diagnostics/research | No |
| 11 | Local source separation while Logic is open | Can heavy analysis coexist without destabilizing Logic? | Acceptable runtime with no unacceptable audio disruption and controlled memory/thermal pressure | Dropouts, severe responsiveness loss or resource exhaustion | Defer/heavily gate separation | Pause during critical work, smaller model, external/manual route | No |
| 12 | Reference chorus-energy explanation | Does the evidence pipeline produce musically useful explanations rather than feature dumps? | Blind evaluation identifies important contributors and statements trace to evidence | Unsupported causality, missed salient changes or low usefulness | Improve event/feature fusion before productizing explanation | Simpler measured comparison without causal prose | No |
| 13 | Local LLM coexistence with Logic | What local model class is safe/useful on the target machine? | Selected model achieves useful plan quality with acceptable memory/thermal/Logic responsiveness | Memory pressure, thermal throttling, dropouts or unusable latency | Choose smaller/local-deterministic or non-local route | Manual ChatGPT/approved cloud | No |
| 14 | ChatGPT Plus handoff round-trip | Is manual subscription collaboration practical as a first-class route? | Export → upload → valid plan → import → preview works with acceptable handling time and enough musical context | Repeated schema failures, insufficient context or excessive friction | Keep ChatGPT advisory/manual only or de-prioritize route | Local/automated providers | No |
| 15 | Stale-response rejection | Can unrelated edits remain valid while changed targets/dependencies are blocked? | Unrelated change produces warning but eligible action can survive; target/dependency change rejects exactly affected actions/dependents | Any stale invalid action can reach mutation code, or all changes cause unnecessary global invalidation | State/precondition architecture must be fixed before write-enabled product | Conservatively reject entire plan until selective validity is correct | **Yes for write-enabled release** |
| 16 | Transaction rollback / restore | Can enabled mutation classes recover verified pre-state safely? | Tested transactions restore exact relevant pre-state despite later unrelated manual work where supported | Partial/wrong restore or reliance on global Undo corrupts unrelated user work | Disable affected mutation class until safe inverse/restore exists | Logic checkpoint/global Undo only for explicitly qualified cases | **Yes for that mutation class** |

## Test order

The recommended order is not simply 1–16 numerically. The build sequence is:

1. complete Event List MIDI read;
2. one-event granular mutation;
3. manual MIDI edit detection;
4. state kernel + stale-response rejection;
5. basic transaction engine + rollback;
6. virtual MCU mixer round-trip;
7. plug-in inventory/parameter qualification;
8. Automation Event List CRUD;
9. routing/sidechain;
10. `.logicx` reconciliation;
11. audio-region source mapping;
12. local source separation coexistence;
13. reference energy explanation;
14. local LLM coexistence;
15. manual ChatGPT handoff;
16. broader routing/provider benchmark work.

This order ensures that the authoritative Logic/control foundation and safety invariants are established before AI/provider polish.

## Evidence classification

Every tested capability should be labelled as one of:

- **Implemented and live-verified** — passed the target Logic/macOS qualification suite with independent readback.
- **Experimental / promising** — underlying Logic/control facility exists and the approach is plausible, but qualification has not passed.
- **Limited** — usable only within an explicit capability boundary.
- **Unknown / unsupported** — evidence insufficient; no executable claim.

Never turn "promising" into "solved" merely because a demo worked once.
