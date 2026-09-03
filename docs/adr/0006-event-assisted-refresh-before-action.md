# ADR 0006 — Event-Assisted, Refresh-Before-Action Synchronization

**Status:** Accepted  
**Last updated:** 2026-09-03

## Context

Logic does not expose one complete public event bus containing every current project mutation. Different observation planes have different coverage: Accessibility notifications, MCU/CoreMIDI feedback, filesystem/save events, optional telemetry and on-demand structured readers.

Attempting to maintain a supposedly perfect continuously mirrored project graph would either be incomplete or unnecessarily expensive.

## Decision

Use **event-assisted, refresh-before-action synchronization**.

> **Events tell us what may have become stale; refresh tells us what is true.**

Notifications/feedback update authoritative values only when the source is itself qualified to provide the new value; otherwise they mark the relevant state domain dirty.

Before reasoning or mutation, refresh the minimum authoritative dependency closure required for that operation.

## Refresh levels

- **Fast:** selection, transport, current channel and cheap live state.
- **Targeted:** the exact targets/dependencies for one request or transaction; normal safety path.
- **Full/deep:** project attach, settled saves, major topology changes, identity ambiguity, diagnostics/regression tests.

## Consequences

- A 500-track project does not need a whole-project crawl for every request.
- A missed notification does not automatically create stale reasoning if pre-action refresh is correct.
- State domains must explicitly carry dirty/freshness/completeness metadata.
- The controller must know which observer can authoritatively refresh each field.
- Unsupported/unavailable live fields remain labelled accordingly rather than guessed.
