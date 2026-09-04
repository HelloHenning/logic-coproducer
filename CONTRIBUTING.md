# Contributing

Thanks for the interest in Logic Co-Producer.

This repository is currently in an architecture/empirical proof-of-concept phase rather than a general feature-development phase.

## Useful contributions

The most useful findings are reproducible observations about Logic Pro integration surfaces, especially:

- Accessibility behavior and limitations;
- Event List / Automation Event List completeness or mutation behavior;
- Mackie Control/CoreMIDI behavior;
- plug-in parameter accessibility and identity;
- routing/send/sidechain control surfaces;
- saved `.logicx` observations;
- audio-region/source mapping;
- negative results that rule out unsafe assumptions.

## POC validation philosophy

The current POC is decision-oriented rather than exhaustive.

> Test a distinct architectural connection or failure mode, make the decision it unlocks, then move on.

Please do not expand a proof into a large compatibility or micro-variation matrix unless a representative result is ambiguous or exposes a materially different failure mode. Broad regression/stress/compatibility coverage belongs later, once there is a product to harden.

See [`docs/poc/validation-status.md`](docs/poc/validation-status.md) for current evidence and stop conditions.

## Safety

- Use synthetic projects/fixtures rather than unpublished or private music.
- Never treat a UI/API action return value as proof that Logic changed.
- Independently reread affected state after a mutation.
- Refuse ambiguous targets rather than guessing.
- Restore reversible test changes and verify restoration.
- Do not modify an open `.logicx` package directly.
- Raw AX snapshots and evidence ZIPs may reveal unrelated recent-file/UI history; sanitize before committing.

## Scope

The architecture is intentionally hybrid. A negative result for one integration surface does not automatically kill the product; it may instead define a capability boundary or trigger a different adapter.

AI/provider integrations are downstream of authoritative state and transaction safety. Please avoid adding provider-specific action execution paths that bypass semantic plans or local verification.

## Licensing

No repository-wide software license has been selected yet. Do not assume permission to reuse repository code outside normal copyright rules until a license is added. Dependencies, model weights, datasets and sample media must have compatible rights before they become product dependencies.
