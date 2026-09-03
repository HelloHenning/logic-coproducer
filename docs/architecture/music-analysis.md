# Local Music and Audio Analysis — Preliminary

Research 2 suggests that a surprisingly large part of the measurable music-analysis workload can run locally on an Apple-silicon Mac. The important limitation is epistemic rather than merely computational: a rendered mix does not uniquely reveal the production history that created it.

## Staged pipeline

The preferred design is not one monolithic “music AI.”

```text
Logic MIDI / audio / reference audio
        ↓
canonical decode + time mapping
        ↓
fast DSP / beat / onset analysis
        ↓
conditional source separation
        ↓
musical event analyzers
        ↓
harmony / rhythm / structure / timbre / effect evidence
        ↓
measurements + events + hypotheses + uncertainty
        ↓
provider-independent Music State
        ↓
local or external reasoning
```

## Local-by-default responsibilities

Research 2 recommends keeping the following local where practical:

- audio decoding and canonical PCM;
- loudness, waveform, spectral, dynamic and stereo features;
- exact symbolic MIDI interpretation once MIDI events are available;
- beat/downbeat/tempo hypotheses;
- source separation;
- useful melody/bass timing and register extraction;
- drum-groove comparison;
- key/basic harmony with alternatives and confidence semantics;
- structure boundaries;
- energy/arrangement trajectories.

## Energy analysis

Do not create one canonical “energy score.” For a transition such as verse → chorus, compare multiple bar-aligned evidence families:

- physical mix: loudness, crest, spectra, band energy, width;
- rhythm: onset density, drum subdivisions, fills, syncopation;
- pitch/harmony: bass articulation/register, harmonic rhythm, voicing span;
- arrangement: stem/instrument entries and exits, layer count, register occupancy;
- learned descriptors/embeddings as corroboration rather than causal proof.

A useful explanation should say “likely arrangement-driven lift” and cite observations. It should not pretend that correlation proves the exact producer action.

## Source separation

Source separation should be task-routed rather than always-on.

- **Quick:** avoid separation unless the task needs it.
- **Detailed:** one four-stem separator plus relevant analyzers.
- **Maximum:** specialized/alternative models only where disagreement or instrument-specific isolation is useful.

The current Apple-specific POC candidate is `mlx-audio-separator`, but model/checkpoint quality and licensing must be evaluated separately.

## Candidate components from Research 2

These are research candidates, not permanent architecture commitments:

- **Beat This!** — first timing/downbeat engine to test; attractive code/weight licensing in the report.
- **mlx-audio-separator** — MLX-native source-separation runtime candidate.
- **Basic Pitch** — lightweight transcription candidate, especially after isolation.
- **music21** — useful symbolic-theory prototyping library while preserving original MIDI as truth.
- custom/native DSP using Core Audio / AVFoundation / Accelerate/vDSP for a shippable core.

Some otherwise useful research libraries/models have copyleft, non-commercial or unclear checkpoint restrictions. Repository license and model-weight license are separate questions.

## Evidence hierarchy

Store analysis in distinct layers:

1. **Measurement** — e.g. spectral centroid, RMS, width.
2. **Event** — e.g. kick onset, bass note onset.
3. **Hypothesis** — e.g. likely Dm9 with alternatives.
4. **Interpretation** — e.g. lift is mainly arrangement-driven.

Each derived object should record source/range, analyzer, version/checkpoint, parameters, confidence semantics and upstream artifacts.

## Caching

Research 2 recommends a content-addressed artifact graph rather than one giant JSON result. A likely storage design is SQLite metadata plus an artifact directory containing stems, time-series features, transcription and other derived files.

Cache keys should include source/range hash, analyzer/model version, checkpoint hash, parameters and upstream artifact IDs.

## Non-identifiability boundary

Some production properties are often inferable as broad families (delay timing, tremolo, filter sweep, pumping, gating, width change). Exact plug-in identity, exact compressor settings, exact reverb algorithm, hidden sidechain source, and whether a result came from automation versus performance are generally not recoverable reliably from rendered audio alone.

The product should communicate hypotheses and alternatives rather than fabricate production history.

## M5 performance

Published Apple-silicon numbers found by Research 2 are encouraging but are not direct M5 MacBook Air benchmarks. The fanless target machine must be tested while Logic is open. Local-model sizing around roughly 7–14B class is a reasonable POC target, not a guarantee.
