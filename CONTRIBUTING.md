# Contributing

Logic Co-Producer is currently a research/architecture project moving toward empirical proof-of-concept work.

## What is useful right now

Contributions are most valuable when they provide:

- reproducible observations about Logic Pro automation/state access;
- small experiments with clear pass/fail criteria;
- documentation corrections with primary sources;
- test fixtures that are synthetic or clearly redistributable;
- careful notes about macOS/Logic-version differences;
- licensing/provenance findings for candidate dependencies or model weights.

Negative results are welcome. “This interface cannot reliably enumerate X under these conditions” can save substantial duplicate work.

## Before submitting substantial code

**No repository-wide software license has been selected yet.** Please open an issue/discussion before submitting substantial source code so licensing and intended reuse are clear. Do not assume code in this repository is automatically open-source merely because the repository is public.

## Evidence standards

Please distinguish:

- documented platform/tool behavior;
- behavior observed in a reproducible experiment;
- inference/hypothesis;
- product preference.

For experiments, include the macOS version, Logic version, hardware, fixture/build revision, exact procedure, raw observations where practical, and pass/fail criteria.

## Privacy

Do not commit:

- API keys, credentials or license keys;
- unpublished personal music unless you own it and explicitly intend to publish it;
- private client/project data;
- local usernames/home paths when avoidable;
- proprietary third-party assets without redistribution rights.

Synthetic musical fixtures are preferred for Logic integration tests.

## Pull requests

Keep PRs focused. Explain what claim or test the change supports and identify any remaining uncertainty. Architecture changes should add or update an ADR when they materially alter a project principle or POC-gated decision.
