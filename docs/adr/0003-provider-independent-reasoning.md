# ADR 0003 — Keep reasoning providers replaceable

**Status:** Accepted architectural principle

## Decision

Reasoning backends are adapters behind a provider-neutral request/plan contract. The architecture must not depend on one model vendor, free tier, API or consumer-chat product.

Supported route classes may include deterministic local logic, local LLMs, manual ChatGPT handoff, approved free APIs and optional paid APIs.

## Why

Provider quality, quotas, prices, privacy terms and model catalogs change. Research 3 documented recent provider/model retirements and explicitly found that no general benchmark establishes a permanent best co-production model.

## Consequences

- Capabilities are data, not provider-specific branches scattered through the app.
- Provider availability and quotas are runtime/cached metadata with expiry.
- The canonical response is a versioned Co-Producer Plan schema.
- Core Logic integration and local analysis remain useful when every cloud service is unavailable.
- New providers are benchmarked before being recommended.

## Privacy

Provider preference never grants broader data permission. Routing remains constrained by explicit provider × sensitivity-class authorization.
