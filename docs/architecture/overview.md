# Architecture Overview — Preliminary, pre-Research-4

> **Status:** architectural working hypothesis derived from Research 1–3. Research 4 is still running and may change boundaries, priorities or terminology.

The current direction is a hybrid companion architecture rather than a single Logic API or a single AI model.

```text
Logic Pro (authoritative factual state)
        ↕
Logic Adapter Layer
        ↕
Authoritative State Kernel
        ├── Music Analysis + Artifact Graph
        └── Creative Memory
                ↓
        Context Selector
                ↓
        Reasoning Router
        ├── deterministic local logic
        ├── local LLM
        ├── manual ChatGPT handoff
        ├── approved free API
        └── optional paid API
                ↓
        Provider-neutral Co-Producer Plan
                ↓
        Safety / Validation Compiler
                ↓
        Human Preview
                ↓
        Transaction Engine
                ↓
        Logic Adapter Layer
                ↓
        Logic Pro
                ↓
        Independent Readback / Verification
```

## Why hybrid Logic access?

Research 1 found no documented public Logic project-object API that provides complete CRUD access to tracks, regions, MIDI events, automation, mixer state, plug-ins and routing. Instead, several narrower surfaces appear complementary:

- Accessibility / AXObserver for live UI and context surfaces.
- Event List as a promising candidate for exact stored MIDI-event read/write.
- Automation Event List as a promising candidate for point-level automation access.
- Virtual Mackie Control / CoreMIDI for strong bidirectional mixer/control-surface operations.
- Read-only `.logicx` parsing for deep **saved-state** inspection and reconciliation.
- Optional Scripter or Audio Unit telemetry for narrow realtime signals.

The architecture therefore chooses the strongest adapter per operation and records the provenance and limitations of each observed field.

## Separate state layers

The system should not maintain one undifferentiated “AI project state.” At minimum:

1. **Raw Logic facts** — authoritative when freshly observed from a qualified adapter.
2. **Measurements/events** — deterministic or model-derived local analysis.
3. **Hypotheses** — chord names, section labels, effect families, etc.
4. **Interpretations** — musical/production explanations.
5. **Creative memory** — user goals, preferences, rejected ideas, prior rationale.
6. **Proposed actions** — semantic edits not yet applied.

## State synchronization

The current preferred strategy is **event-assisted, refresh-before-action**:

- feedback/notifications mark affected domains dirty;
- the app refreshes only the dependency closure needed for the next request or mutation;
- stale or incomplete fields are explicit;
- the app does not require a continuous perfect mirror of every Logic object.

## Local analysis

Research 2 supports a staged local pipeline:

`decode → timing/DSP → conditional separation → musical events/features → hypotheses → evidence fusion → structured Music State → constrained reasoning`

This is intentionally different from asking one audio-language model to infer everything from raw stereo.

## Reasoning

Research 3 recommends a provider-independent router. Local reasoning is a normal route; manual ChatGPT collaboration is first-class; free/paid APIs are optional and privacy-gated. All routes return the same versioned semantic plan format before anything can reach Logic.

## Safety boundary

Natural-language model output never controls Logic directly. The local application resolves stable targets, validates schema and scope, checks stale-state preconditions and protected elements, presents a preview, applies a transaction, then independently re-reads Logic.

## Biggest unresolved architecture gate

Exact live stored-MIDI access remains the leading kill test. If Event List Accessibility can be complete and deterministic, granular MIDI collaboration becomes much stronger. If it cannot, fallback approaches may require controlled MIDI export/import or region replacement and would reduce product granularity.
