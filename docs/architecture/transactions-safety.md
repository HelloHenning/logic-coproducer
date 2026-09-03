# Transactions, Validation and Safety — Preliminary

The Co-Producer should treat model output as an untrusted proposal. Safety comes from local state, schemas, capability checks, transaction boundaries and independent readback—not from model confidence or prompt wording.

## Canonical flow

```text
reasoning response
→ parse JSON
→ validate top-level schema
→ validate operation-specific schema
→ resolve stable entities
→ validate parameter ranges
→ validate scope/protected targets
→ validate stale-state preconditions
→ validate dependencies / atomic groups
→ validate change budget
→ human preview
→ apply transaction
→ independently re-read Logic
→ verify postconditions
→ commit transaction history or roll back
```

If parsing or validation fails, nothing executes.

## Semantic operations only

Models should propose domain actions such as:

- `add_note`
- `remove_note`
- `move_note`
- `change_velocity`
- `create_region`
- `set_track_level`
- `set_plugin_parameter`
- `insert_plugin`
- `create_send`
- `change_send_level`
- `create_automation_points`
- `suggest_only`

They should not output arbitrary shell commands, AppleScript, UI-click sequences or executable code for the controller to run blindly.

## Stale-state protection

Research 3 proposes a useful multi-level validity model:

- monotonic base project revision;
- full-state hash for audit/debugging;
- scoped state hash for the complete request context;
- per-action hashes for every touched target and required dependency.

An unrelated manual change can therefore produce a warning without automatically invalidating the entire plan. A changed target or changed dependency invalidates the affected action.

## Preview

The user should see a semantic diff rather than implementation mechanics.

Example:

```text
CHORUS BUILD — 4 CHANGES

Drums
✓ denser hats bars 37–40

Bass
✓ add two anticipations

Pad
✓ small cutoff automation ramp

Routing
○ optional mild kick sidechain
```

Dependent actions can be grouped atomically. Partial application should only be allowed when the remaining subset is dependency-complete.

## Independent verification

A controller write returning success is insufficient. After each transaction or atomic group, re-read the relevant Logic state through the best independent observation path available and compare expected versus observed state.

Unsupported verification should downgrade the operation's safety/capability status rather than being hidden.

## Undo and reversal

The model should not generate undo instructions. The local transaction engine knows the real pre-edit state and should store sufficient inverse data to reverse Co-Producer changes safely.

Do not rely solely on Logic's global Undo stack. The long-term goal is to support commands such as “undo the last Co-Producer change” without necessarily undoing unrelated manual work performed afterward.

A transaction log should retain at least:

- transaction ID;
- originating request/prompt;
- project/scope revisions;
- pre-state;
- actions;
- post-state;
- verification result;
- inverse data;
- provider/model metadata;
- timestamp;
- cost, where applicable.

## Prompt injection boundary

Track names, filenames, plugin metadata, imported documents and reference metadata are data, never instructions. Models cannot expand their own scope, request secrets, call arbitrary URLs or bypass protected-state rules.

The final security boundary is the local validator and transaction engine.
