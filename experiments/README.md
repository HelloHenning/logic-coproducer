# Experiments

This directory will contain reproducible proof-of-concept code, fixtures, raw observations and test notes.

The project is intentionally keeping experiments separate from eventual production code. A fragile Accessibility probe may be valuable for answering an architectural question even if it is not suitable for a distributable application.

## Planned first experiment family

The first work is expected to be a **Logic interoperability laboratory**, including:

- Event List enumeration and exact MIDI census;
- one-note mutation and readback;
- manual MIDI edit detection;
- Automation Event List exploration;
- virtual Mackie Control state round-trip;
- plug-in inventory/parameter capability tests;
- routing/sidechain tests;
- saved `.logicx` reconciliation.

See [`docs/poc/preliminary-kill-tests.md`](../docs/poc/preliminary-kill-tests.md).

## Reproducibility

Each experiment should record the exact macOS version, Logic version, hardware, project fixture version/hash, app/probe revision, procedure, raw results and pass/fail criteria.

Use synthetic or openly shareable fixtures. Do not commit unpublished personal music, credentials, license keys or identifying private project data.
