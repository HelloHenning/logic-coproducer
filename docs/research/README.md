# Research Index

The broad research program is complete. This directory contains curated, maintainable summaries rather than raw Deep Research transcripts.

## Research sequence

1. [Research 1 — Logic integration and authoritative state](research-1-logic-integration.md)
2. [Research 2 — Local audio/music intelligence](research-2-local-music-intelligence.md)
3. [Research 3 — AI routing and external reasoning](research-3-ai-routing.md)
4. [Research 4 — Final architecture synthesis](research-4-final-synthesis.md)
5. [Current research/build status](research-status.md)

## What the four stages established

### 1. Logic integration

Logic Pro does not expose one comprehensive documented project-object API. A trustworthy companion therefore needs a hybrid observation/control plane and must qualify each executable capability separately.

The most important unresolved interface questions are exact live stored-MIDI access and granular automation access. Event List and Automation Event List are promising but remain empirical POC hypotheses.

### 2. Local music/audio intelligence

Most measurable work can plausibly remain local: deterministic DSP, beat/downbeat analysis, exact symbolic MIDI interpretation once events are acquired, source separation, targeted transcription, harmony evidence, structural analysis and multidimensional energy/arrangement comparison.

Rendered audio cannot uniquely identify hidden production history, so effect/production explanations remain evidence-backed hypotheses rather than reconstructed facts.

### 3. Reasoning/provider architecture

AI should reason over current structured evidence instead of rediscovering state. Local reasoning and manual ChatGPT collaboration are normal routes; optional cloud providers remain behind capability, privacy, availability and budget gates.

All model output is normalized into a provider-neutral semantic plan. Natural-language responses never directly control Logic.

### 4. Final synthesis

Research 4 reconciled the previous reports into one recommended build architecture:

```text
Logic
↕
Hybrid Logic adapters
↕
Authoritative state kernel
↕
Local analysis / artifact graph + separate creative memory
↓
Context selector + reasoning router
↓
Provider-neutral semantic plan
↓
Safety compiler + human preview
↓
Transaction engine
↓
Logic
↓
Independent verification / rollback
```

It also finalized:

- factual state versus creative memory boundaries;
- raw fact → measurement/event → hypothesis → interpretation → intent → proposed action layers;
- dirty-domain refresh strategy;
- stable local entity IDs and reconciliation confidence;
- project/entity revisions plus scoped/dependency hashes;
- conditional MIDI and automation fallback architectures;
- capability-gated mixer/plug-in/routing behavior;
- local analysis/cache/process architecture;
- semantic Co-Producer Plan and safety compiler;
- preview/apply/verify/undo transaction model;
- the 16 architectural kill tests;
- exact POC order;
- the first MVP: **Authoritative MIDI Collaboration**.

## Research-to-build transition

No additional broad research phase is required before coding.

The immediate task is **`LogicInteroperabilityLab`** and the first three decisive experiments:

1. complete Event List MIDI read;
2. one-event granular mutation;
3. manual MIDI edit detection.

See:

- [Final architecture](../architecture/overview.md)
- [Architectural kill tests](../poc/architectural-kill-tests.md)
- [Ordered POC plan](../poc/test-plan.md)

## Evidence policy

Public documentation should keep distinguishing:

- live-verified/implemented;
- strongly supported design constraints;
- promising but POC-dependent;
- limited;
- unknown/unsupported.

Provider capabilities and prices are point-in-time implementation data rather than permanent architecture decisions. Model/code/checkpoint licensing must be evaluated separately when a component is selected for use or distribution.
