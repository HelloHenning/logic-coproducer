# Architecture Decision Table

_Status: post-Research-4 synthesis. Confidence refers to the architecture decision, not to untested Logic adapter behavior._

| Decision | Recommendation | Confidence | Evidence status | Critical POC / condition | Fallback |
|---|---|---:|---|---|---|
| Main application | Swift + SwiftUI | High | Strong platform fit | Build lab/app shell | — |
| Logic live-state strategy | Hybrid adapter layer | High | Strongly supported | Qualification by domain/version | Disable unsupported domains |
| MIDI read | Event List Accessibility if complete | Medium | Promising / POC-gated | Complete census, including non-visible rows | Controlled SMF export/readback |
| MIDI write | Granular Event List mutation if verified | Medium-low | POC-gated | One-event mutation + exact diff | SMF/region replacement |
| Manual MIDI change detection | Targeted authoritative re-read | Medium | POC-gated | Manual edit detection | Stronger export/readback refresh |
| Automation | Automation Event List exact CRUD if qualified | Medium-low | POC-gated | Complete point CRUD/readback | Broader qualified write / suggestion-only |
| Mixer | Virtual Mackie Control / CoreMIDI | High | Strongly supported | Large-track round-trip | AX for narrower operations |
| Plug-in strategy | Capability registry + qualified semantic adapters | High | Strong design constraint | Native/third-party matrix | Read-only / suggestion-only |
| Third-party Audio Units | Never assume universal semantic control | High | Strongly supported | Representative variability test | Verified plug-in/vendor adapters |
| Routing / sidechain | MCU + AX, capability-gated | Medium-high | Promising | routing/sidechain POC | Partial routing / suggestion-only |
| Saved `.logicx` | Read-only saved-state observer | High | Strongly supported | Saved/live reconciliation | Remove from authoritative flow |
| `.logicx` write to open project | Do not use | High | Strong safety constraint | none | semantic live adapters only |
| Optional AU | Narrow telemetry only, not project API | High | Strongly supported | Add only if later need is proven | none |
| Optional Scripter | Realtime MIDI/timing helper only | High | Strongly supported | task-specific need | none |
| Authoritative project DB | SQLite metadata/state kernel | High | Strongly supported | State-kernel POC | — |
| Artifact store | Content-addressed filesystem artifacts | High | Strongly supported | cache implementation | simpler temporary cache |
| State synchronization | Event-assisted + targeted refresh-before-action | High | Accepted architecture | state torture tests | more conservative refresh |
| Stable IDs | Local opaque IDs + multi-source reconciliation/confidence | High concept / medium implementation | Strongly supported | rename/reorder/duplicate/reopen tests | fail closed on ambiguity |
| Revisions | Project + entity revisions | High | Strongly supported | state-kernel tests | conservative full refresh |
| Stale responses | Scope hash + target/dependency precondition hashes | High | Accepted architecture | stale-response kill test | reject whole plan conservatively |
| Local DSP | Core Audio/AVFoundation + Accelerate/vDSP | High | Strongly supported | performance POC | prototyping helpers |
| Timing | Replaceable local beat/downbeat engine | High architecture / model-dependent | Strongly supported | target corpus benchmark | alternate engine |
| Source separation | Task-selected local model router | Medium-high | Strongly supported | target-Mac/license test | skip/defer/external route |
| Transcription | Exact MIDI when present; targeted local audio transcription | High architecture | Strongly supported | corpus benchmark | uncertainty/human confirmation |
| Energy analysis | Bar/beat-aligned multidimensional evidence fusion | High | Strongly supported | blind usefulness test | measured comparison only |
| Local reasoning runtime | Provider-independent local runtime; MLX-first implementation candidate | High architecture | Strongly supported | coexistence stress test | llama.cpp/other local runtime |
| Normal local model class | Roughly 8–14B-class candidate, benchmark-selected | Medium | Engineering hypothesis | Logic coexistence test | smaller local / manual/cloud |
| Manual ChatGPT route | First-class export/import provider | High | Strongly supported | round-trip usability test | local/automated provider |
| ChatGPT handoff | Loose JSON/Markdown files; optional media | High | Strongly supported | handoff POC | reduced symbolic package |
| Local archival handoff | `.coproducer-handoff` ZIP container | High | Strongly supported | implementation | ordinary folder |
| Free API strategy | Optional replaceable adapter, never dependency | High | Strong architecture | provider-specific benchmark/consent | local/manual route |
| Paid API policy | Disabled by default | High | Accepted product policy | explicit user opt-in/budget | no paid route |
| Provider abstraction | Capability/privacy/budget/availability first, then ranking | High | Accepted architecture | routing benchmark | manual selection |
| Action language | Versioned semantic JSON Schema | High | Accepted architecture | schema/fuzz/transaction POC | suggestion-only |
| Safety compiler | Local deterministic validation chain | Very high | Accepted architecture | adversarial/stale tests | disable writes |
| Transaction model | Preview → revalidate → apply → readback → verify → rollback | Very high | Accepted architecture | rollback kill test | disable unsafe mutation class |
| Undo | Co-Producer transaction pre-state/inverse, not only global Logic Undo | High | Accepted architecture | restore tests | qualified Logic checkpoint/Undo |
| Privacy | Consent per provider × sensitivity class | High | Accepted architecture | UX/implementation test | local only |
| UI form | Main side companion window + optional menu/status presence | High | Architecture fit | later usability test | window only |
| Initial distribution | Developer-ID signed/notarized direct distribution before App Store optimization | Medium-high | Strong engineering direction | permissions/helper/entitlement validation | personal/internal build |

## Interpretation

A **high-confidence architecture decision** can still depend on a lower-confidence adapter. For example, it is high confidence that exact MIDI access must be capability-gated and independently verified; it is only medium/POC confidence that Event List Accessibility will satisfy that requirement.

This distinction prevents a promising implementation mechanism from being mistaken for a solved product capability.
