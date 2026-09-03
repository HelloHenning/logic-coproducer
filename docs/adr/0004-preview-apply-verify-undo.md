# ADR 0004 — Preview, apply, independently verify, then support reversal

**Status:** Accepted architectural principle

## Decision

Every executable Co-Producer change follows this lifecycle:

`Preview → Validate → Apply → Independent Readback → Verify → Record inverse state`

Model output alone is never considered proof that a requested edit exists in Logic.

## Why

Logic access is fragmented. Some mechanisms are strong for mutation but weak for observation. A successful controller/UI command can still target the wrong object or leave unexpected state.

## Consequences

- The model proposes semantic actions; it does not generate arbitrary executable code or its own undo procedure.
- The local transaction engine stores true pre-edit state and creates reversal data.
- Postconditions are checked through the strongest qualified observation path.
- Failed verification stops dependent operations and is surfaced explicitly.
- Long-term undo should be able to reverse a Co-Producer transaction without blindly walking back unrelated later manual Logic edits.
