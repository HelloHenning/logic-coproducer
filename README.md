# Logic Co-Producer

Research and development of a **session-aware AI co-producer for Logic Pro**.

> **Current status:** broad research is complete. The architecture is established and the project is in empirical Logic interoperability proof-of-concept work. The core authoritative MIDI sequence has passed for the qualified stored-event subset; the remaining Phase-A gates are being tested with a lean, decision-oriented strategy.

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

There is no single documented public Logic project-object API that exposes complete live CRUD access to all project domains. The architecture therefore uses the strongest interface per operation: Accessibility/AXObserver, virtual Mackie Control/CoreMIDI, Event List and Automation Event List where empirically qualified, read-only saved `.logicx` inspection, and optional narrow Scripter/AU telemetry.

The core live stored-MIDI gates are now qualified for the exercised subset:

- complete hydrated Event List read — PASS;
- granular stored-event mutation with independent full readback/restoration — PASS;
- fresh authoritative reread after an independent/manual Logic edit — PASS.

Remaining Logic-domain uncertainty is concentrated in mixer control, plug-ins, automation, routing, saved-project reconciliation and audio-region/source mapping.

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

## Current POC strategy

Phase-A validation is **decision-oriented, not exhaustive**.

The default rule is:

> **Test a distinct architectural connection or failure mode, make the decision it unlocks, then tick it off.**

The project does not need broad micro-variation matrices before the architecture is chosen. Compatibility sweeps, stress tests and regression matrices are deferred until there is a product to harden.

The remaining lean Phase-A gates are:

1. virtual MCU/CoreMIDI mixer control;
2. one representative native plug-in parameter connection;
3. one representative automation control connection;
4. one representative routing/send connection, plus sidechain only if needed as a distinct relationship;
5. useful saved `.logicx` reconciliation;
6. useful audio-region/source mapping.

Human involvement should be reserved for genuine decisions and unavoidable Logic/macOS setup. Preferred test shape is one short setup, one command, unattended execution, automatic restoration/verification, and one evidence package.

See [Current POC validation status](docs/poc/validation-status.md).

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
- [Current POC validation status](docs/poc/validation-status.md)
- [Architecture Decision Records](docs/adr/README.md)
- [Full documentation index](docs/README.md)

The repository publishes curated research summaries rather than raw Deep Research transcripts so that dated exploratory findings do not masquerade as permanent architecture decisions.

## Contributing

Reproducible findings—especially negative results about Logic automation surfaces—are useful. Please read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

No repository-wide software license has been selected yet. This is deliberate while code-reuse, dependency and model-weight licensing are still being evaluated. Until a license is added, normal copyright rules apply.
