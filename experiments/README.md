# Experiments

This directory will contain reproducible proof-of-concept code, fixtures, raw observations and test notes.

The project is intentionally keeping experiments separate from eventual production code. A fragile Accessibility probe may be valuable for answering an architectural question even if it is not suitable for a distributable application.

## Active first experiment family — LogicInteroperabilityLab

The immediate work is the **Logic interoperability laboratory** defined after Research 4.

The first decisive sequence is:

1. complete Event List MIDI read;
2. one-event granular mutation with exact diff verification;
3. manual MIDI edit detection.

GitHub issues:

- #1 — umbrella `LogicInteroperabilityLab` work;
- #2 — complete Event List MIDI read;
- #3 — one-event granular MIDI mutation;
- #4 — manual MIDI edit detection.

Later experiment families include:

- virtual Mackie Control state round-trip;
- native/third-party plug-in capability matrix;
- Automation Event List CRUD;
- routing/sidechain tests;
- saved `.logicx` reconciliation;
- audio-region source mapping;
- local source-separation/LLM coexistence with Logic;
- reference energy-explanation evaluation.

See:

- [`docs/poc/test-plan.md`](../docs/poc/test-plan.md)
- [`docs/poc/architectural-kill-tests.md`](../docs/poc/architectural-kill-tests.md)
- [`docs/research/research-4-final-synthesis.md`](../docs/research/research-4-final-synthesis.md)

## Reproducibility

Each experiment should record:

- exact macOS version;
- exact Logic version;
- hardware class;
- project/fixture version and hash;
- lab/probe commit/revision;
- permissions/configuration needed;
- procedure;
- expected state;
- raw observations;
- canonical machine-readable result;
- exact diff where applicable;
- pass/fail criteria and conclusion;
- known limitations or ambiguous observations.

Use synthetic or openly shareable fixtures. Do not commit unpublished personal music, credentials, license keys, personal filesystem paths or identifying private project data.

## Evidence labels

Use one of these in experiment conclusions:

- **Implemented and live-verified**
- **Experimental / promising**
- **Limited**
- **Unknown / unsupported**

Negative results are valuable and should be documented rather than hidden.
