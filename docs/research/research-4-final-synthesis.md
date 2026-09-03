# Research 4 — Final Architecture Synthesis

_Status: Complete — 2026-09-03_

Research 4 did not perform another broad technology survey. It reconciled the three prior research tracks into one build-ready architecture, identified which claims are design constraints versus POC hypotheses, defined the main fallback branches, and ordered the empirical tests that should happen before broader implementation.

## Executive conclusion

The project is ready to move from broad research to an empirical proof of concept.

The recommended system is a **local macOS companion with a hybrid Logic adapter, authoritative state kernel, local music-analysis/artifact graph, separate creative memory, context selector, provider-independent reasoning router, provider-neutral semantic action plan, safety compiler and transactional Logic execution with independent verification and undo**.

The largest remaining unknown is not AI quality or local compute. It is whether Logic's Event List and Automation Event List can serve as complete, deterministic, independently verifiable live adapters on the target Logic/macOS build.

That uncertainty is better answered by experiments than by another research report.

## Reconciliation of Research 1–3

The reports are complementary rather than contradictory.

### Research 1

Established that there is no single documented public Logic project-object API covering all tracks, regions, MIDI, mixer, plug-ins, routing and automation. The realistic integration is hybrid, using the strongest interface for each domain. Exact live MIDI and automation CRUD remain critical experiments.

### Research 2

Established that once symbolic/audio material has been acquired, much of the musical intelligence can remain local: deterministic DSP, timing, source separation, transcription support, harmony evidence, groove/bass/melody analysis, structure and multidimensional energy analysis.

### Research 3

Established the reasoning boundary: current scoped Logic state is authoritative, provider choice is modular, local reasoning is normal, manual ChatGPT is first-class, cloud services are optional, and all executable proposals use versioned semantic JSON plus local validation and state preconditions.

### Important MIDI distinction

These two statements are both true:

1. **Exact MIDI can be understood symbolically once exact events are available.**
2. **Reliably obtaining and granularly modifying the authoritative live events currently stored in Logic remains unproven.**

The first is a music-analysis problem; the second is a Logic-interoperability problem.

## Final architecture

```text
Logic Pro — authoritative reality
        ↕
Hybrid Logic Adapter Layer
  - Accessibility / AXObserver
  - Event List [conditional on POC]
  - Automation Event List [conditional on POC]
  - virtual Mackie Control / CoreMIDI
  - read-only saved .logicx observer
  - filesystem observer
  - optional Scripter / AU telemetry
        ↕
Authoritative State Kernel
  - local entity IDs
  - provenance + completeness
  - live/saved status
  - dirty domains
  - project/entity revisions
  - scoped/dependency hashes
        ↕
Music Analysis + Artifact Graph
        +
Separate Creative Memory
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
Logic
        ↓
Independent readback → VERIFIED / FAILED / ROLLBACK
```

## State layers

The architecture must preserve these separately:

1. **Raw Logic facts** — notes, regions, tracks, mixer values, plug-in state, routing, automation, tempo, selection.
2. **Derived measurements/events** — loudness, onset density, beat events, spectral features, bass events.
3. **Musical hypotheses** — likely chord, section role, effect-family hypothesis.
4. **Interpretation** — e.g. "the lift appears arrangement-driven."
5. **Creative intent** — e.g. "keep the chorus dark and restrained."
6. **Proposed actions** — semantic edits that have not yet occurred in Logic.

Inferred values preserve provenance, time span, analyzer/model/version, confidence semantics and alternatives.

## Synchronization

The governing rule is:

> **Events tell us what may have become stale; refresh tells us what is true.**

Use three refresh levels:

- **Fast refresh** for selection, transport, current channel and cheap live state.
- **Targeted refresh** for the exact dependency closure of a reasoning request or transaction. This is the normal safety path.
- **Full/deep refresh** for project attach, save reconciliation, major topology changes, diagnostics and low-confidence identity reconciliation.

A full-project rescan is not required for every command.

## Stable IDs, revisions and stale plans

The Co-Producer assigns local IDs to tracks, regions, MIDI events, plug-in instances/parameters, buses, sends, automation lanes, assets and analysis artifacts.

Because Logic does not necessarily expose permanent public IDs for every object, identities can be reconciled from multiple observations and can carry confidence. Ambiguous identity fails closed.

Use:

- monotonic project revision for audit/warnings;
- entity revisions for local change tracking;
- a full-state hash for audit;
- a scoped request hash;
- per-action target/dependency precondition hashes.

A global project revision change does **not** automatically invalidate every plan. Unrelated changes may be allowed; changed targets or dependencies invalidate only the affected actions and their dependents.

## Conditional MIDI architecture

### If Event List POC passes

Event List becomes the preferred live MIDI adapter for selected/scoped regions. It must prove exhaustive enumeration, deterministic pagination, exact event fields, single-event mutation/create/delete, manual re-read and preservation of unrelated events.

### If reading succeeds but granular writing fails

Retain Event List as authoritative readback. Use controlled SMF transformation/import or broader region replacement for writes.

### If Event List read fails

Fall back to controlled MIDI export, saved `.logicx` corroboration and broader mutation paths.

**Failure does not kill the overall Co-Producer.** It downgrades the strongest granular MIDI-editing experience and may temporarily make some composition workflows region-level rather than event-level.

## Conditional automation architecture

Use the same branching pattern for Automation Event List.

If exact point enumeration/editing passes, expose semantic point CRUD. If it fails, use qualified broader automation-writing paths or suggestion-only behavior where verification is not possible.

Failure limits surgical automation editing but does not kill the product.

## Mixer, plug-ins and routing

- Prefer virtual Mackie Control/CoreMIDI for transport, core mixer state and sends where supported.
- Use Accessibility for live context, track/region surfaces and qualified UI controls.
- Use plug-in-specific semantic adapters only where parameter identity, units, range, write and readback are known.
- Treat arbitrary third-party Audio Units as a variability boundary.
- Maintain a capability registry per plug-in instance/operation.
- Never let AI propose an executable operation that the current adapter cannot verify.

## Local audio/music analysis

Use a staged DAG, not one raw-audio language model.

**Quick:** canonical decode, deterministic DSP, cached/cheap timing, exact symbolic state, simple harmony/change-point analysis.

**Detailed:** add one task-selected separation pass, drum/bass/harmonic activity, structure, targeted transcription and bar-aligned energy comparison.

**Maximum:** specialized/alternate separators and deeper analyses only when the question justifies them.

Energy analysis remains multidimensional: physical mix, rhythm, pitch/harmony, arrangement and supporting learned descriptors. The explanation engine reports evidence-backed likely contributors rather than pretending to reconstruct hidden production history.

## Artifact/cache architecture

Use SQLite metadata plus a content-addressed artifact directory.

Cache keys include source/range hash, analyzer version, checkpoint hash, parameters and upstream artifact hashes. Unrelated project changes should not invalidate unrelated reference-audio artifacts.

## Reasoning and providers

Viability comes before ranking:

```text
capability compatible
AND privacy authorized
AND budget authorized
AND currently available
```

Then rank viable routes using Co-Producer-specific quality evidence, latency, user effort, current Mac pressure, privacy, cost and task-specific user history.

Initial route classes:

- deterministic/local;
- local LLM;
- manual ChatGPT handoff;
- optional free automated provider;
- optional paid provider.

No paid AI service is required for the core product.

## ChatGPT manual provider

Manual ChatGPT is a first-class adapter whose execution semantics are export/import rather than an API call.

Primary upload format: loose `manifest.json`, `request.md`, current scoped state, MIDI/harmony/analysis/creative context and optional media.

Local archival format: `.coproducer-handoff` ZIP container.

Imported model output must parse and validate. Invalid JSON executes nothing.

## Semantic action plan and safety

Models never output raw UI clicks, shell commands, arbitrary AppleScript or executable code. They output whitelisted semantic operations such as:

- `add_note`, `remove_note`, `move_note`, `change_velocity`;
- `create_region`, `move_region`, `duplicate_region`;
- `set_track_level`, `set_pan`;
- `insert_plugin`, `set_plugin_parameter`, `set_sidechain`;
- `create_send`, `change_send_level`;
- `create_automation_points`;
- `create_marker`;
- `suggest_only`.

The local validator checks schema, operation type, entity resolution, parameter semantics, capability, scope, protected state, freshness/preconditions, dependencies, change budget and atomic groups before preview/application.

## Transaction model

Every write follows:

**Inspect → Plan → Preview → Revalidate → Apply → Independent readback → Verify → Commit/rollback.**

The Co-Producer keeps its own transaction log and inverse/pre-state information rather than relying solely on Logic's global Undo stack.

## Kill-test conclusions

Sixteen core tests are defined separately in [`../poc/architectural-kill-tests.md`](../poc/architectural-kill-tests.md).

The closest product-level safety blockers are:

- stale-response protection must reliably reject changed targets/dependencies;
- transaction rollback/restore must be reliable for every mutation class that is enabled.

Most other failures reduce a feature or force a fallback rather than kill the product.

## MVP

The first MVP is **Authoritative MIDI Collaboration**:

1. attach to Logic;
2. identify selected MIDI region;
3. obtain exact current MIDI;
4. analyze current harmony locally;
5. create a semantic note-level proposal;
6. preview/apply/verify it;
7. user manually edits the Logic region;
8. Co-Producer re-reads the current state;
9. next reasoning request uses the user's changed state rather than stale AI history;
10. safely undo the last Co-Producer transaction.

The MVP proves **Logic is the source of truth**, not that an AI can generate notes.

## Immediate next action

Build **`LogicInteroperabilityLab`** first.

The first three decisive tests are:

1. complete Event List MIDI read;
2. one-event granular mutation with exact diff verification;
3. manual MIDI edit detection on refresh.

Do not begin with AI UI polish, cloud APIs or source-separation integration.

## Do we need Research 5?

**No broad Research 5 is required before coding.**

The remaining high-value uncertainties are empirical properties of Logic and the target Mac and should be treated as targeted experiments. Narrow factual/licensing lookups can still be performed when a specific implementation decision requires them.

**NEXT STEP: BUILD THE FIRST PROOF OF CONCEPT.**
