# Final Architecture Overview

_Status: architecture established; empirical qualification in progress._

The Logic Co-Producer is a **local macOS companion**. Logic Pro remains the authoritative source of factual project state. AI and local analysis operate on fresh, scoped projections of that state and can only propose semantic operations that a local safety/transaction layer may execute.

## System architecture

```text
Logic Pro — authoritative factual state
        ↕
Hybrid Logic Adapter Layer
  - Accessibility / AXObserver
  - Event List [POC-gated]
  - Automation Event List [POC-gated]
  - virtual Mackie Control / CoreMIDI
  - read-only saved .logicx observer
  - filesystem observer
  - optional Scripter / AU telemetry
        ↕
Authoritative State Kernel
  - normalized entities
  - provenance / completeness
  - live vs saved status
  - dirty domains
  - project + entity revisions
  - scoped + dependency hashes
        ↕
Music Analysis / Artifact Graph
        +
Creative Memory
        ↓
Context Selector
        ↓
Reasoning Router
  - deterministic local logic
  - local LLM
  - manual ChatGPT
  - approved free cloud
  - optional paid cloud
        ↓
Provider-neutral Co-Producer Plan
        ↓
Safety Compiler
        ↓
Human Preview
        ↓
Transaction Engine
        ↓
Logic Adapter Layer
        ↓
Logic Pro
        ↓
Independent readback / verification / rollback
```

## Authority boundaries

The system must not collapse these layers:

1. **Raw Logic facts** — current notes, tracks, regions, mixer values, plug-in/routing/automation state, tempo, selection.
2. **Measurements/events** — beat events, loudness, onset density, spectral measurements, bass/drum events.
3. **Musical hypotheses** — likely chord, section role, probable effect family.
4. **Interpretation** — e.g. a chorus lift is probably arrangement-driven.
5. **Creative intent** — persistent user preferences and project goals.
6. **Proposed actions** — edits that have not happened yet.

Logic facts have the highest factual authority. Derived/inferred layers retain provenance, time span, analyzer/model/version, uncertainty semantics and alternatives.

## Synchronization

The governing rule is:

> **Events tell us what may have become stale; refresh tells us what is true.**

Three refresh levels are planned:

- **Fast refresh** — selection, transport, current channel and cheap live state.
- **Targeted refresh** — exact dependency closure needed for one request or transaction; this is the normal safety path.
- **Full/deep refresh** — project attach, save reconciliation, major topology change, diagnostics or low-confidence identity reconciliation.

A whole-project crawl is not required before every command.

## Logic adapter responsibilities

Choose the strongest mechanism per operation rather than forcing one interface to do everything.

| Domain | Preferred path | Fallback / corroboration |
|---|---|---|
| Transport | virtual MCU/CoreMIDI | AX |
| Volume/pan/mute/solo | MCU | AX readback |
| Sends | MCU where exposed | AX |
| Track/context state | AX | saved parser |
| Regions | AX | saved parser |
| Exact MIDI | Event List if POC passes | controlled SMF export / saved parser |
| Automation points | Automation Event List if POC passes | qualified broader write / saved state |
| Plug-in parameters | MCU/generic parameter view + qualified adapters | AX / suggestion-only |
| Routing/sidechain | MCU + AX | capability-gated partial support |
| Markers/chord/signature | targeted AX | saved parser |
| Audio-region mapping | Project Audio Browser AX | saved parser |
| Deep saved snapshot | read-only `.logicx` | none |

`.logicx` is a **saved-state observer**, never a live mutation API for an open project.

## State and identity

Every factual field should preserve:

- source/provenance;
- observed time;
- completeness;
- live/saved/inferred authority;
- dirty state;
- project/entity revision;
- relevant hash.

The Co-Producer assigns local IDs to tracks, regions, MIDI events, plug-in instances/parameters, buses, sends, automation lanes, audio assets and analysis artifacts.

Where Logic exposes no permanent native object ID, identity is reconciled from multiple observations and carries confidence. Ambiguous identity fails closed.

## Revision and stale-response design

Use:

- monotonic project revision for audit/warnings;
- entity revisions;
- full-state hash for audit;
- scoped request hash;
- per-action target/dependency precondition hashes.

A changed global revision does not automatically invalidate an entire plan. An unrelated verse edit may leave a chorus plan valid, while a changed target region, harmony dependency, sidechain source or plug-in invalidates only the affected actions and dependent actions.

## Conditional MIDI architecture

Event List is the preferred live MIDI path **only if the POC proves**:

- exhaustive deterministic enumeration, including non-visible rows;
- complete event fields;
- single-event modification/create/delete;
- manual edit re-read;
- preservation of unrelated events;
- independent verification.

If reading succeeds but granular writes fail, Event List remains useful for authoritative readback and writes can fall back to controlled SMF/region replacement.

If complete Event List read fails, the system falls back to exact export/readback and broader mutation paths. This reduces granular MIDI capability but does not kill the overall product.

## Conditional automation architecture

Automation Event List follows the same pattern. Exact point CRUD becomes executable only after complete point read/write/readback is proven. Otherwise use qualified broader automation operations or suggestion-only behavior.

## Local analysis

Local analysis is a staged DAG:

```text
canonical audio / exact MIDI
→ deterministic DSP + timing
→ conditional source separation
→ musical event extraction
→ hypotheses + confidence
→ evidence-backed interpretation
```

Quick/Detailed/Maximum modes alter which analysis nodes run rather than merely changing a quality number.

Analysis artifacts are cached by content and dependency hashes using SQLite metadata plus a content-addressed artifact directory.

## Reasoning

The reasoning router first determines whether a route is viable:

```text
capability compatible
AND privacy authorized
AND budget authorized
AND available
```

Then it ranks viable routes by task-specific quality evidence, latency, user effort, Mac pressure, privacy, cost and user history.

Local reasoning and manual ChatGPT are normal routes. Cloud APIs are optional. No paid AI service is required for core function.

## Semantic action boundary

Models never output raw UI automation, shell commands, arbitrary AppleScript or executable code. They output versioned semantic operations such as:

- MIDI note add/remove/move/resize/velocity;
- region create/move/duplicate;
- mixer level/pan;
- plug-in insert/qualified parameter/sidechain;
- send/routing operations;
- automation points;
- markers;
- suggestion-only actions.

The local capability registry prevents the model from proposing executable operations that the current Logic adapter cannot verify.

## Safety and transactions

Every write follows:

**Inspect → Plan → Validate → Preview → Revalidate → Apply → Independent readback → Verify → Commit/rollback.**

The Co-Producer maintains its own transaction log and inverse/pre-state data rather than depending only on Logic's global Undo stack.

## Process boundaries

Recommended eventual layout:

- `CoProducer.app` — SwiftUI shell/coordinator;
- `LogicController` — Swift, Accessibility and CoreMIDI/MCU;
- `AnalysisWorker` — DSP/MIR/ML orchestration;
- `LLMWorker` — local language inference;
- `ProviderService` — optional network providers;
- optional AU component only when later telemetry needs justify it.

Heavy ML must be isolated so failures/resource pressure cannot destabilize Logic control.

## Current engineering phase

The architecture is now stable enough to test. The immediate implementation is **`LogicInteroperabilityLab`**, focused on:

1. complete Event List MIDI read;
2. one-event granular mutation with exact diff verification;
3. manual MIDI edit detection.

See the [ordered POC plan](../poc/test-plan.md) and [architectural kill tests](../poc/architectural-kill-tests.md).
