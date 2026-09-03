# ADR 0007 — Provider-Neutral Semantic Plans and a Local Safety Compiler

**Status:** Accepted  
**Last updated:** 2026-09-03

## Context

The Co-Producer may use local models, manual ChatGPT collaboration or optional cloud providers. Provider output is probabilistic and can be malformed, stale, over-broad or based on invented target state.

Allowing natural-language output or provider-specific tool calls to operate Logic directly would couple musical reasoning to fragile UI mechanisms and weaken the safety boundary.

## Decision

All reasoning routes return a **provider-neutral, versioned semantic Co-Producer Plan**.

Models may propose only whitelisted DAW/music-domain operations. They do not output raw UI clicks, arbitrary AppleScript, shell commands or executable controller code.

A local safety compiler validates every plan before preview/application.

## Required validation layers

At minimum:

1. JSON parsing;
2. envelope schema;
3. operation-specific schema;
4. known-operation registry;
5. current entity resolution;
6. parameter semantics/ranges;
7. current adapter capability;
8. request scope;
9. protected-state rules;
10. stale-state/precondition hashes;
11. dependencies;
12. change budget;
13. atomic-group validity;
14. human preview;
15. transactional application;
16. independent postcondition verification.

Model confidence never bypasses any layer.

## Consequences

- Logic-control implementation can change from AX to MCU/Event List/etc. without changing the AI contract.
- Local, ChatGPT and cloud providers can be benchmarked against the same output semantics.
- Unsupported capabilities fail closed before they become UI actions.
- Invalid ChatGPT/manual JSON executes nothing and can be repaired/re-imported safely.
- True inverse/undo operations are created by the local transaction engine from authoritative pre-state, not by the model.
