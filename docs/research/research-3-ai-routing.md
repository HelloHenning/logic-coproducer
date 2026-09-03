# Research 3 — AI Routing and External Reasoning

**Status:** complete research report; provider/model details are dated to September 2026 and should be treated as runtime-discoverable product data rather than permanent architecture.

## Question

How should the Co-Producer choose among local models, manual ChatGPT collaboration, free cloud APIs and optional paid APIs while balancing quality, privacy, effort, latency, system load and cost?

## Executive conclusion

The report rejects a fixed provider ladder. The recommended architecture is a **provider-independent, task-specific router** that first builds one fresh, authoritative, minimal context package and then evaluates which routes are viable.

A route should be considered only when it is:

```text
capability-compatible
AND privacy-authorized
AND budget-authorized
AND available
```

It can then be ranked using Co-Producer-specific benchmark quality, expected latency, manual effort, current local resource pressure and cost.

## Initial route classes

Research 3 recommends five classes while initially implementing only a small number of concrete providers:

- **Local deterministic / local LLM** — normal route for routine work.
- **Manual subscription provider** — ChatGPT handoff for high-value occasional creative/production reasoning.
- **Free automated text** — Groq was the leading initial candidate in the report for structured text, subject to current availability and privacy configuration.
- **Audio/multimodal provider** — Gemini was the strongest documented direct-audio candidate, with an important free-vs-paid privacy distinction.
- **Optional paid reasoning** — only where project-specific benchmarks show meaningful value.

No core product feature should require a paid API subscription.

## Manual ChatGPT collaboration

The report treats manual ChatGPT Plus collaboration as a genuine provider adapter rather than a temporary workaround.

Advantages include:

- uses an existing consumer subscription rather than requiring per-request API spend;
- keeps the human at an explicit privacy/action boundary;
- avoids coupling the control path to one provider API;
- supports nuanced artistic reasoning over structured project evidence.

The cost is manual friction and weaker machine-enforced structured-output guarantees than an API.

### Handoff concept

A handoff should contain a **fresh scoped snapshot**, not rely on old conversation facts. Typical loose files might include:

```text
manifest.json
request.md
current_state.json
harmony.json
midi.json
analysis.json
creative_context.json
optional short media
```

Each request should carry a request ID, base revision, scoped state hash and artifact hashes. Current state is authoritative; change history and conversation history are explanatory only.

The report cautions against building the product around a permanent assumption that ordinary consumer ChatGPT will always accept arbitrary DAW audio formats. The symbolic/measurement handoff should be useful on its own; audio remains optional/capability-gated.

## Provider-neutral plan

The canonical external interchange should be versioned JSON with a domain-specific operation whitelist.

Natural-language prose may explain reasoning, but executable actions need stable targets and preconditions. The local app should parse and validate the response; malformed or unsupported plans execute nothing.

Research 3 recommends scoped and per-entity preconditions rather than only a global hash. An unrelated edit can therefore warn without automatically invalidating a safe plan, while a changed target or dependency rejects the affected action.

## Privacy

A major finding is that free cloud services have materially different data policies. The app should not label them simply “cloud.”

A conservative classification from the report:

- credentials/API keys/license keys — never model context;
- unpublished raw mixes/stems — sensitive;
- unpublished MIDI/melody/harmony — sensitive symbolic content;
- artist/project/track names — potentially identifying, with redaction option;
- anonymized derived feature summaries — lower sensitivity;
- public plugin documentation/reference metadata — generally suitable for grounding.

Consent should be remembered per **provider × sensitivity class**. A learned provider preference never broadens privacy authority.

## Current provider findings are not constants

Research 3 documented rapid changes in free tiers, model catalogs and service availability. Provider capabilities, prices, quotas and privacy metadata should therefore be cached with expiry and probed where possible rather than hard-coded into the product.

Free services are accelerators, never prerequisites.

## Local reasoning

The report recommends a model-independent local runtime, with MLX/MLX-LM as a strong Apple-silicon default and compatibility paths for llama.cpp/Ollama/LM Studio.

A rough POC hierarchy on 32 GB unified memory is:

- small model for classification/routing;
- roughly 8–14B quantized class for routine reasoning;
- larger ~20–27B-class models only as optional “deep local” experiments when Logic/resource headroom allows.

Actual coexistence with Logic must be stress-tested; “fits in memory” is not the same as “safe beside a low-latency DAW session.”

## Separate grounding from musical reasoning

Web/current-documentation lookup should be its own capability. Asking whether an installed plug-in version supports external sidechain should require only the plug-in/version/question—not unpublished MIDI or audio.

## Co-Producer benchmark

Generic AI leaderboards do not answer which model makes useful, safe production decisions.

Research 3 recommends a frozen evaluation corpus covering:

- constrained chord continuation;
- contrasting chorus/arrangement suggestions;
- energy-analysis explanation from supplied evidence;
- vague request → executable plan;
- effect interpretation;
- protected-state compliance (“do not change X”);
- stale-state handling;
- ambiguity/uncertainty behavior;
- structured JSON validity.

Objective validators should be combined with blinded human musical ratings. Latency, cost and privacy remain separate routing dimensions.

## Highest-priority POCs from Research 3

1. **Stale-state/execution safety** — unrelated edits can remain eligible; changed targets/dependencies must invalidate affected actions.
2. **ChatGPT Plus round trip** — real package → manual upload → plan import → validation → preview → transaction; measure handling time and schema failures.
3. **Same-input routing benchmark** — compare local, manual and selected API routes on identical scoped evidence.
4. **Logic coexistence test** — exercise small/normal/deep local models beside representative Logic projects; measure memory pressure, thermals, dropouts and responsiveness.
5. **Cost estimator** for paid requests.
6. **Quota/outage simulation** so provider failure becomes normal route-state change rather than application failure.
7. **Hybrid reference analysis** — compare local structured evidence + manual reasoning against direct-audio cloud reasoning to test whether raw audio adds enough value.

## Product implication

The router should know capabilities and constraints, not a permanent winner. Musical quality must eventually be earned through project-specific benchmarks and user outcomes.
