# Design Principles

These principles are the strongest common architectural conclusions from Research 1–3. Research 4 may refine implementation details, but these are the current guardrails.

## 1. Logic is authoritative for factual project state

Tracks, regions, MIDI events, mixer values, plug-ins, routing, automation, tempo and other project facts must come from current Logic state or be explicitly marked stale/incomplete/saved-only.

## 2. Creative memory is separate from factual state

Preferences, intentions, rejected ideas and prior rationales may persist locally. They must never override current Logic facts.

## 3. Observation, mutation and verification are different capabilities

A mechanism that can change something does not automatically prove what Logic ultimately stored. Every adapter is evaluated separately for observation, change detection, refresh, mutation and independent verification.

## 4. Events mark possible staleness; refresh establishes truth

Notifications and feedback should mark state domains dirty. Before reasoning or editing, refresh the relevant dependency set from Logic rather than depending on stale cache or conversation history.

## 5. Prefer granular semantic edits

The AI should request domain operations such as `move_note`, `set_plugin_parameter` or `create_send`, not raw UI clicks or whole-region replacement unless no safer interface exists.

## 6. Preview → Apply → Verify → Undo

A model response is a proposal, not proof. Valid operations are previewed, applied transactionally, then independently read back from Logic. Reversal data is generated locally from real pre-edit state.

## 7. Inference is not fact

Keep a visible hierarchy:

`Logic fact → measurement/event → hypothesis → interpretation → creative intent → proposed action`

Uncertain chord names, section labels or effect identifications remain hypotheses with provenance and alternatives.

## 8. Local-first measurable analysis

Deterministic DSP, timing, symbolic MIDI analysis and other measurable tasks should remain local where practical. External reasoning should consume compact structured evidence rather than re-derive facts unnecessarily.

## 9. Reasoning providers are replaceable

Local models, manual ChatGPT collaboration, free APIs and optional paid APIs are adapters behind one provider-neutral request/plan contract. No cloud provider is a core dependency.

## 10. Privacy permission is scoped

Cloud approval should depend on provider and data sensitivity. Permission to send symbolic features does not imply permission to upload unpublished audio or an entire Logic project.

## 11. Capability claims are qualified

Especially for third-party plug-ins and Logic UI surfaces, the app must know what it can read, write and verify. Unsupported operations should be unavailable to the reasoning layer rather than guessed.

## 12. Failed experiments are useful project output

This project documents negative results and fragile interfaces as carefully as successful ones. Several remaining questions can only be answered on the target Logic/macOS environment.
