# Logic Co-Producer

Research and development of a **session-aware AI co-producer for Logic Pro**.

> **Current status:** broad research is complete. The architecture is established and the project is moving into the first empirical Logic interoperability proof of concept.

## The core idea

Logic Pro remains the authoritative source of factual project state.

If the Co-Producer generates a progression and the user then changes notes, voicing, key, instrument, routing or automation manually in Logic, the next request must use **what is actually in Logic now**—not what the AI remembers creating earlier.

That source-of-truth requirement is the project's defining test.

```text
Logic Pro
   ↕
Hybrid Logic observation/control adapters
   ↕
Authoritative state kernel
   ├── factual Logic state + provenance/revisions/hashes
   ├── local music/audio analysis + artifact graph
   └── separate creative memory
          ↓
   context selector + reasoning router
          ↓
local / manual ChatGPT / optional cloud
          ↓
provider-neutral semantic Co-Producer Plan
          ↓
safety compiler → preview → transaction → independent readback
          ↓
verified result / rollback / Co-Producer undo
```

## What this project is trying to build

A companion that can eventually:

- understand the current Logic session rather than stale AI history;
- inspect and develop MIDI, harmony and arrangement;
- reason about mixer, plug-in, routing and automation state where those surfaces can be read and verified reliably;
- analyze project/reference audio largely on-device;
- explain changes such as why a chorus feels more energetic using measurable evidence;
- propose small semantic edits instead of blindly replacing whole regions/projects;
- use local reasoning normally and manual ChatGPT collaboration as a first-class option;
- optionally use free/paid cloud providers without making them core dependencies;
- preview, validate, verify and reverse its own changes.

## What it is not

- a one-shot song generator;
- a chatbot whose conversation history is treated as DAW state;
- an autonomous system that silently changes an entire project;
- a claim that rendered audio can reveal exact hidden production history;
- a promise of universal third-party plug-in control.

## Architecture status

The four research stages now support one recommended architecture rather than a menu of competing designs.

### Logic integration

There is no single documented public Logic project-object API that exposes complete live CRUD access to all project domains. The architecture therefore uses the strongest interface per operation: Accessibility/AXObserver, virtual Mackie Control/CoreMIDI, Event List and Automation Event List if their critical POCs pass, read-only saved `.logicx` inspection, and optional narrow Scripter/AU telemetry.

The largest unresolved gate is **exact live stored-MIDI access**. Event List Accessibility remains promising but is deliberately POC-gated rather than treated as solved.

### State and safety

The application will maintain a normalized authoritative state kernel with local entity IDs, provenance, completeness, live/saved status, dirty domains, project/entity revisions and scoped/dependency hashes.

The synchronization rule is:

> **Events tell us what may have become stale; refresh tells us what is true.**

AI never emits UI clicks, shell commands or arbitrary scripts. It emits a versioned semantic plan that must pass capability, schema, entity, scope, protected-state, stale-state, dependency and change-budget validation before a user can apply it.

### Local music/audio intelligence

Most measurable work should remain local: deterministic DSP, beat/downbeat analysis, symbolic MIDI interpretation, useful source separation/transcription, structure, harmony evidence and multi-feature energy/arrangement comparison.

The system separates raw Logic facts, measurements/events, musical hypotheses, interpretation, creative intent and proposed actions instead of letting a language model blur those layers.

### AI routing

Reasoning is provider-independent. Local models are a normal route; manual ChatGPT collaboration is first-class; free and paid APIs are optional and privacy-gated. Provider/model availability, prices and quotas are runtime data rather than permanent product assumptions.

## Research status

| Study | Scope | Status |
|---|---|---|
| Research 1 | Logic access, control and state awareness | Complete |
| Research 2 | Local audio/music intelligence | Complete |
| Research 3 | AI routing and external reasoning | Complete |
| Research 4 | Final synthesis, feasibility, architecture and POC plan | **Complete** |

No further broad research phase is planned before coding. Remaining high-value uncertainties are better answered empirically on the target Mac.

## Immediate next step

Build **`LogicInteroperabilityLab`**, a small native macOS harness focused on the decisive MIDI path:

1. identify the selected Logic MIDI region;
2. enumerate its Event List completely, including events outside the visible viewport;
3. export a canonical machine-readable snapshot and compare it with a golden fixture;
4. modify exactly one MIDI event;
5. re-read and prove that no unrelated event changed;
6. manually edit the region in Logic;
7. refresh and prove the lab sees the user's change rather than relying on its own previous state.

Those tests answer the hardest part of the distinctive MVP: **complete read → granular edit → manual edit detection**.

If Event List MIDI fails, the architecture falls back to exact export/readback plus broader region-level mutation. That would reduce granular MIDI capability but would not invalidate the overall Co-Producer architecture.

## MVP

The first product MVP is **Authoritative MIDI Collaboration**: attach to Logic, read the current selected MIDI region, analyze current harmony, propose a semantic note-level diff, apply and verify it, observe subsequent manual user edits, reason from the updated state, and undo the last Co-Producer transaction safely.

The MVP must prove **Logic is the source of truth**, not merely that AI can generate MIDI.

## Documentation

Start with:

- [Vision](docs/vision.md)
- [Design principles](docs/principles.md)
- [Final architecture overview](docs/architecture/overview.md)
- [Research summaries](docs/research/README.md)
- [Research 4 synthesis](docs/research/research-4-final-synthesis.md)
- [Architectural kill tests](docs/poc/architectural-kill-tests.md)
- [Ordered POC plan](docs/poc/test-plan.md)
- [Architecture Decision Records](docs/adr/README.md)
- [Full documentation index](docs/README.md)

The repository publishes curated research summaries rather than raw Deep Research transcripts so that dated exploratory findings do not masquerade as permanent architecture decisions.

## Contributing

Reproducible findings—especially negative results about Logic automation surfaces—are useful. Please read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

No repository-wide software license has been selected yet. This is deliberate while code-reuse, dependency and model-weight licensing are still being evaluated. Until a license is added, normal copyright rules apply.
