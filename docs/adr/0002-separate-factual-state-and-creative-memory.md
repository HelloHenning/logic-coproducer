# ADR 0002 — Separate factual project state from creative memory

**Status:** Accepted architectural principle

## Decision

Maintain two different concepts:

**Factual project state** — current Logic facts such as notes, regions, routing, plug-ins and automation.

**Creative memory** — durable local context such as mood, preferences, rejected ideas, arrangement goals and prior rationale.

Creative memory may persist across requests and sessions. Factual project state must be refreshed from Logic and cannot be reconstructed from conversation history.

## Why

A producer can remember that the user wants a restrained chorus without pretending to remember the exact current note at bar 38 after the user has edited Logic manually.

## Consequences

- Different storage/authority rules for state versus memory.
- Model requests contain an immutable scoped projection of current facts plus only relevant creative memory.
- Older AI discussion can never override current-state artifacts.
- Sensitive one-off reasoning can use fresh conversations while local creative memory preserves project continuity.
