# Vision

Logic Co-Producer is intended to behave like a knowledgeable collaborator sitting beside a Logic Pro user: aware of what is currently in the session, able to analyze musical and production evidence, able to discuss creative options, and eventually able to make small, reversible edits.

## Distinctive product test

The defining scenario is not one-shot generation.

1. The Co-Producer creates or suggests material.
2. The user edits that material manually inside Logic.
3. The user later asks for another development.
4. The Co-Producer must use the **current Logic state**, not its memory of what it generated earlier.

If the system cannot pass that test reliably, it is not yet the product envisioned here.

## Goals

- Session-aware songwriting and production assistance.
- Granular MIDI, mixer, plug-in, routing and automation operations where the Logic interface can support and verify them.
- Local-first analysis of measurable musical/audio facts.
- Evidence-backed interpretation of reference tracks and project sections.
- Provider-independent reasoning, including local models and a manual ChatGPT collaboration path.
- Previewable, validated, reversible changes.
- Useful offline behavior.

## Non-goals

- Replacing Logic Pro as the authoritative project store.
- Treating AI conversation history as current DAW state.
- A one-shot song generator.
- Silent autonomous editing of an entire session.
- Claiming exact production history can always be recovered from rendered audio.
- Promising universal control of every third-party plug-in.

## Current phase

Research 1–3 are complete. Research 4 is in progress and is expected to synthesize the final architecture and exact proof-of-concept order. The documents in this repository are therefore intentionally explicit about what is established versus what still requires empirical testing.
