# Reasoning and Provider Routing — Preliminary

Research 3 recommends a provider-independent, task-specific router rather than a fixed ladder such as “local, then ChatGPT, then free API, then paid API.”

## Routing principle

A route is viable only if it is:

```text
capability-compatible
AND privacy-authorized
AND budget-authorized
AND currently available
```

Viable routes can then be ranked by Co-Producer-specific quality evidence, latency, user effort, current Mac resource pressure, privacy and cost.

## Initial route classes

| Route | Intended role |
|---|---|
| Deterministic local | extraction, validation, transformations and simple rule-based tasks |
| Local LLM | routine summaries, classification, harmony/planning and structured edit plans when benchmark quality is adequate |
| Manual ChatGPT provider | complex occasional artistic/production reasoning through an export/import handoff |
| Free automated provider | optional structured-text automation where privacy and current quota allow |
| Paid provider | explicit opt-in escalation when benchmarked value justifies cost/privacy tradeoff |

Research 3's initial prototype candidates were Groq for free structured text and Gemini for direct-audio/multimodal work, with paid APIs optional. These provider choices are **dated research findings, not architectural constants**.

## Minimal context, not project dumps

The context selector should provide the smallest authoritative dependency closure that answers the task.

For example, “fit this bass line to the updated chorus” may need:

- current bass MIDI;
- current chorus harmony;
- relevant drum pattern;
- melody-conflict information;
- tempo/meter;
- short adjacent musical context;
- creative constraints.

It does not require every track, every plug-in or the entire project file.

Symbolic/current facts should be preferred over raw media when they answer the question adequately.

## Manual ChatGPT as a first-class provider

The manual workflow is not treated as a temporary workaround. It can be represented as a provider whose execution means:

```text
create handoff package
→ user uploads files to ChatGPT
→ model returns explanation + versioned JSON plan
→ user pastes/drops/imports response
→ local validation
→ preview
→ transaction
```

The handoff should contain a fresh scoped snapshot, not rely on conversation memory. A durable package might contain `manifest.json`, `request.md`, current state, MIDI/harmony/analysis artifacts and optional short media.

Research 3 cautions against making arbitrary music-file upload in consumer ChatGPT a permanent product assumption. The manual path therefore needs to remain useful from structured MIDI, harmony, measurements, routing and plug-in state alone.

## Provider-neutral plan

All reasoning backends should return the same versioned Co-Producer Plan schema. Natural-language prose is advisory; only validated semantic operations may become executable.

Important request/response identity fields include:

- request ID;
- base project revision;
- scoped state hash;
- artifact hashes;
- stable entity IDs;
- per-action target/dependency preconditions.

A global project hash is useful for audit but should not automatically invalidate a safe chorus action because an unrelated verse track changed.

## Privacy

Research 3 emphasizes that “free cloud” is not a single privacy class. Provider policy, retention/training terms and free-vs-paid behavior vary and change over time.

A conservative application policy should distinguish at least:

- credentials: never model context;
- unpublished audio/stems: sensitive;
- unpublished MIDI/melody/harmony: sensitive symbolic content;
- identifying project/artist metadata: redactable;
- anonymized numerical features: lower sensitivity;
- public documentation/reference metadata: generally suitable for grounding.

Consent should be remembered by **provider × sensitivity class**, not as one global cloud switch.

## Benchmark-driven quality

Generic LLM leaderboards do not establish which model is best at musical co-production. The application should build its own frozen evaluation corpus covering creative usefulness, instruction adherence, protected-state compliance, stale-state handling, theoretical correctness and schema validity.

Latency, cost and privacy remain separate routing dimensions rather than being hidden inside one opaque score.

## Offline behavior

No provider failure should disable Logic integration or deterministic local analysis. Offline mode should retain local reasoning and permit manual handoff packages to be created for later use.
