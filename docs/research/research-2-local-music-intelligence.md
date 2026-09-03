# Research 2 — Local Audio and Music Intelligence

**Status:** complete research report; model/runtime recommendations are dated candidates and must be benchmarked/licensed before shipping.

## Question

How much useful musical and production intelligence can run locally on an Apple-silicon Mac, especially the target M5/32-GB machine, without making cloud AI responsible for measurable facts?

## Executive conclusion

The report found that the local boundary is substantially farther out than expected. A staged local system can plausibly handle most deterministic DSP, strong beat/downbeat analysis, useful source separation, exact symbolic-MIDI interpretation once MIDI is available, practical bass/melody/drum extraction, low-level timbral/dynamic/stereo analysis, structure boundaries and a meaningful amount of harmony/key inference.

The harder boundary is **epistemology**: a rendered stereo mix does not uniquely expose the original dry sources, automation, routing, plug-in identity, exact effect settings or production history. The product should therefore produce evidence-backed hypotheses with alternatives rather than opaque certainty.

## Architecture recommendation

Do not use one monolithic audio-language model as the analysis engine.

Use a staged pipeline:

```text
canonical audio + timing
→ fast DSP / beat / onset analysis
→ source separation only when useful
→ musical event analyzers
→ harmony / rhythm / structure / timbre / effect evidence
→ measurements + hypotheses + uncertainty
→ provider-independent Music State
→ constrained local/external reasoning
```

## Local responsibilities

The report recommends local-by-default handling of:

- waveform/DSP, loudness, spectra, dynamics and stereo metrics;
- symbolic MIDI understanding;
- beat/downbeat/tempo hypotheses;
- source separation;
- useful melody/bass timing and register;
- drum-groove comparison;
- key/basic harmony with alternatives;
- structural boundaries;
- energy trajectory and evidence-backed explanation.

Extended chord labels, inversions from audio, dense polyphonic transcription and semantic section labels should remain qualified hypotheses rather than silent ground truth.

## Energy/arrangement analysis

A core product opportunity is explaining why one section feels more energetic than another.

The report explicitly rejects a single “energy score.” Compare bar-aligned changes across:

- **physical mix** — loudness, dynamics, spectral balance, width;
- **rhythm** — onset density, drum subdivisions, fills and syncopation;
- **pitch/harmony** — bass articulation/register, harmonic rhythm, voicing span;
- **arrangement** — active layers, entrances/exits, register occupancy;
- **learned descriptors/embeddings** — supporting evidence, not causal explanation.

This allows conclusions such as “likely arrangement-driven lift” supported by observed hat density, bass articulation and added layers even if loudness changes only modestly.

## Source separation

Research 2 recommends a portfolio/router rather than one permanent separator.

- Quick mode: avoid separation unless needed.
- Detailed mode: one four-stem pass.
- Maximum mode: specialized/alternative models only where downstream value is demonstrated.

The leading Apple-specific POC candidate identified was [mlx-audio-separator](https://github.com/ssmall256/mlx-audio-separator), which provides MLX-native inference across several separator families. Published project benchmarks were encouraging but were **not M5 MacBook Air measurements**.

Separation models must be judged by downstream analytical utility as well as how clean their solo stems sound.

## Other useful candidates

- [Beat This!](https://github.com/CPJKU/beat_this) — first timing/downbeat candidate to test; report found favorable code/weight licensing.
- [Basic Pitch](https://github.com/spotify/basic-pitch) — lightweight transcription baseline, especially on isolated material.
- [music21](https://github.com/cuthbertLab/music21) — useful symbolic-analysis prototyping library; original MIDI remains authoritative.
- native Core Audio / AVFoundation / Accelerate/vDSP — preferred eventual deterministic processing layer.

Harmony should combine chroma/pitch/bass/key evidence and preserve competing labels rather than forcing one extended-chord name.

## Effects and production-history boundary

Broad phenomena such as delay timing, tremolo, autopan, filter sweeps, obvious gating, width change or pumping may often be measurable or inferable.

The report warns against claiming reliable recovery of:

- exact plug-in identity;
- exact compressor attack/release/ratio;
- exact reverb algorithm/preset;
- hidden sidechain sources;
- whether a result came from automation versus source/performance change.

## Analysis state model

Keep these separate:

1. measurement;
2. event;
3. hypothesis;
4. interpretation.

Every derived artifact should carry source/range, analyzer/model version, checkpoint hash where relevant, parameters, confidence semantics, alternatives and upstream dependencies.

## Caching

Research 2 recommends content-addressed artifacts: SQLite for metadata/relationships plus an artifact directory for stems, time-series data, transcription, embeddings and other large outputs.

Changing one source/range should invalidate only dependent artifacts rather than re-running an entire song analysis.

## Licensing risk

A major finding is that **repository code license and pretrained-weight license are separate**. Some attractive systems use non-commercial, copyleft or unclear model assets even when the wrapper code is permissive.

A shippable model manifest should track architecture, original author/source, weight hash, license, redistribution/commercial permissions, attribution and available training-data disclosure.

## Highest-value POCs from Research 2

1. **Chorus-energy explanation** — blind review of whether explanations identify the musically important changes and cite real observations.
2. **Separation shootout** — compare models by downstream drum/harmony/event accuracy, not only listening quality.
3. **Full M5 performance while Logic is open** — wall time, memory pressure, thermal behavior, audio stability.
4. **Clean-guitar harmony** — known triads/sevenths/add9/sus/inversions with uncertainty behavior.
5. **Verse/chorus drum comparison**.
6. **Bass-behavior extraction**.
7. **Controlled mystery-effect tests** before attempting unverifiable forensic claims on commercial mixes.

## Product implication

The local analysis engine should do the measurable/private/repeatable work. Reasoning models should consume compact structured evidence and explain or plan from it rather than inventing observations from raw audio.
