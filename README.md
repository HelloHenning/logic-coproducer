# Logic Co-Producer

Research and development of a **session-aware AI co-producer for Logic Pro**.

> **Current status:** research / architecture phase. Research 1–3 are complete; Research 4 is still running and is expected to finalize the architecture, kill tests, MVP and proof-of-concept order.

## The core idea

Logic Pro remains the authoritative source of factual project state.

If the Co-Producer generates a progression and the user then changes notes, voicing, key, instrument, routing or automation manually in Logic, the next request must use **what is actually in Logic now**—not what the AI remembers creating earlier.

That source-of-truth requirement is the project's defining test.

```text
Logic Pro
   ↕
Hybrid observation/control adapters
   ↕
Authoritative project state
   ├── local music/audio analysis
   └── creative memory
          ↓
   context + reasoning router
          ↓
local / manual ChatGPT / optional cloud
          ↓
provider-neutral semantic edit plan
          ↓
validate → preview → apply → independently verify → undo
```

## What this project is trying to build

A companion that can eventually:

- understand the current Logic session rather than stale AI history;
- inspect and develop MIDI/harmony/arrangement;
- reason about mixer, plug-in, routing and automation state where those surfaces can be read and verified reliably;
- analyze project/reference audio largely on-device;
- explain changes such as why a chorus feels more energetic using measurable evidence;
- propose small semantic edits instead of blindly replacing whole regions/projects;
- use local reasoning by default and manual ChatGPT collaboration as a first-class option;
- optionally use free/paid cloud providers without making them core dependencies;
- preview, validate, verify and reverse its own changes.

## What it is not

- a one-shot song generator;
- a chatbot whose conversation history is treated as DAW state;
- an autonomous system that silently changes an entire project;
- a claim that rendered audio can reveal exact hidden production history;
- a promise of universal third-party plug-in control.

## Current research conclusions

### Logic integration

There is no single documented public Logic project-object API that exposes complete live CRUD access to all project domains. The strongest working direction is a **hybrid adapter** using the best available surface per operation: Accessibility/AXObserver, Event List, Automation Event List, virtual Mackie Control/CoreMIDI, read-only saved `.logicx` inspection, and optional narrow telemetry.

The largest unresolved gate is exact live stored-MIDI access. Event List Accessibility is promising but remains **POC-gated**.

### Local music/audio intelligence

Most measurable work appears suitable for local execution: deterministic DSP, beat/downbeat analysis, symbolic MIDI interpretation, useful source separation/transcription, structure, harmony evidence and multi-feature energy/arrangement comparison.

The system should distinguish measurement, event, hypothesis and interpretation rather than letting a language model invent facts.

### AI routing

Reasoning should be provider-independent. Local models are a normal route; manual ChatGPT collaboration is first-class; free and paid APIs are optional and privacy-gated. Provider/model availability, prices and quotas are runtime data rather than permanent product assumptions.

## Documentation

Start with:

- [Vision](docs/vision.md)
- [Design principles](docs/principles.md)
- [Architecture overview](docs/architecture/overview.md)
- [Research summaries](docs/research/README.md)
- [Preliminary proof-of-concept kill tests](docs/poc/preliminary-kill-tests.md)
- [Architecture Decision Records](docs/adr/README.md)
- [Full documentation index](docs/README.md)

## Research status

| Study | Scope | Status |
|---|---|---|
| Research 1 | Logic access, control and state awareness | Complete |
| Research 2 | Local audio/music intelligence | Complete |
| Research 3 | AI routing and external reasoning | Complete |
| Research 4 | Final synthesis, feasibility, architecture and POC plan | **In progress** |

The repository currently publishes curated summaries rather than the raw Deep Research transcripts. Research 4 will be used to revise these docs before the first coding POC.

## Near-term work

The first development work is expected to be a **Logic interoperability laboratory**, not AI UI polish. High-value tests include exact Event List MIDI census/mutation/manual-edit detection, Automation Event List CRUD, virtual MCU round-trip, plug-in/routing capability tests and saved-state reconciliation.

See [`docs/poc/preliminary-kill-tests.md`](docs/poc/preliminary-kill-tests.md).

## Contributing

Reproducible findings—especially negative results about Logic automation surfaces—are useful. Please read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

No repository-wide software license has been selected yet. This is deliberate while code-reuse, dependency and model-weight licensing are still being evaluated. Until a license is added, normal copyright rules apply.
