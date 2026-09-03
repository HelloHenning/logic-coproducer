# Research Summary

This directory contains curated public summaries of the project's Deep Research work. The full raw reports are not currently published here; these summaries focus on conclusions, uncertainty and build implications.

> **Important:** Research 4 is still in progress. The architecture documents in this repository are therefore preliminary synthesis, not final product specification.

## Research program

| Report | Scope | Status |
|---|---|---|
| [Research 1](research-1-logic-integration.md) | Logic access, control, state observation, change detection and verification | Complete |
| [Research 2](research-2-local-music-intelligence.md) | Local audio/music intelligence on Apple Silicon | Complete |
| [Research 3](research-3-ai-routing.md) | Local/manual/cloud reasoning architecture, privacy and provider routing | Complete |
| Research 4 | Final synthesis, architecture, kill tests, MVP and build order | In progress |

See also [research-status.md](research-status.md).

## What we know before Research 4

### 1. The product is technically plausible, but Logic integration is fragmented

There is no single documented public Logic object API that exposes complete live CRUD access to all tracks, regions, stored MIDI events, automation, mixer state, plug-ins and routing. A trustworthy implementation will need a hybrid adapter layer and explicit capability/provenance tracking.

The mixer/control-surface plane looks substantially stronger than exact stored-MIDI access. Exact Event List MIDI read/write is therefore a critical empirical gate rather than an assumed feature.

### 2. Logic—not AI memory—must define current project facts

Research 1's most important product definition is that “session aware” means current relevant state is demonstrably derived from Logic at the time of reasoning/action, or marked incomplete/stale. A user manual edit must supersede any earlier AI-generated state.

### 3. Local music/audio analysis can do most measurable work

Research 2 found a credible local boundary for DSP, timing, symbolic MIDI understanding, source separation, useful transcription, structural analysis, basic harmony and multi-feature energy/arrangement analysis.

The limiting factor is often epistemology: rendered audio does not uniquely identify exact production history, plug-ins, hidden sidechains or exact settings. The product should preserve evidence, hypotheses, alternatives and uncertainty.

### 4. The reasoning layer should be replaceable

Research 3 recommends a provider-independent router. Local inference is a normal route; manual ChatGPT collaboration is first-class; free or paid APIs are optional. All routes return the same versioned semantic plan before any edit can reach Logic.

### 5. Safety is local and deterministic

Natural-language output never directly controls Logic. Stable targets, scoped revisions/hashes, capability checks, protected-state rules, preview, transaction boundaries and independent post-write verification form the safety boundary.

### 6. The next big answers come from experiments, not another broad survey

The most important unresolved questions are now empirical:

- Can Event List Accessibility enumerate and mutate every stored MIDI event deterministically?
- Can Automation Event List support complete point-level CRUD?
- How much mixer/plugin/routing state can virtual Mackie Control expose bidirectionally?
- Can saved `.logicx` snapshots be reconciled reliably with live state?
- How well do local audio-analysis pipelines perform on the actual fanless M5 machine while Logic is open?
- Are local and external reasoning routes musically useful on a Co-Producer-specific benchmark?
- Is the manual ChatGPT round-trip practical enough in real use?

These questions are tracked in the preliminary POC plan.

## Evidence labels

Until Research 4 finishes, public documentation uses these meanings informally:

- **Established/documented** — supported by platform/tool documentation or directly known behavior.
- **Strong working direction** — multiple findings support the architecture, but product engineering remains.
- **POC-gated** — plausible and important, but must be proven on the target environment.
- **Limited** — useful only in constrained cases.
- **Unknown** — evidence is insufficient; do not build assumptions on it.
