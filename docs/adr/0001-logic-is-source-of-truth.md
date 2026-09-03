# ADR 0001 — Logic Pro is the factual source of truth

**Status:** Accepted architectural principle

## Decision

Current factual project state is authoritative only when derived from Logic Pro through a qualified observation path, or explicitly marked stale/incomplete/saved-only.

AI conversation history, previously generated MIDI and the Co-Producer's own cached assumptions are never allowed to override fresher Logic state.

## Context

The defining product scenario includes manual user edits after an AI suggestion. If the Co-Producer later develops the song from its old generated state rather than the user's current Logic edits, the product fails its central session-aware requirement.

## Consequences

- Every reasoning request needs a fresh scoped project snapshot or qualified current-state refresh.
- Every write needs target/dependency revalidation.
- Saved `.logicx` data is useful but cannot silently stand in for unsaved live state.
- Conversation history may carry creative intent but not current note/plugin/mixer facts.
- The state kernel must expose provenance and staleness.

## Revisit condition

Only revisit if Logic later provides a first-class external project API that changes how authoritative observation is obtained. The source-of-truth principle itself would still remain.
