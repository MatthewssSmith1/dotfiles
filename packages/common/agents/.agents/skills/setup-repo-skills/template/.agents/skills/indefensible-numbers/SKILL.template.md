---
name: indefensible-numbers
description: Use when adding or reviewing a literal that bounds concurrency, retries, timeouts, batch size or spend, or hunting for limits without `@limitKind` evidence.
---

# Indefensible Numbers

A name and a rationale alone do not defend a limit. Its immediately preceding doc comment identifies the evidence category, units, scope and owner. Published limits and measured operating limits are both legitimate; they are not the same claim. Derived arithmetic is legitimate only when its inputs are defensible.

## Required Doc Comment

Every limit uses `@limitKind published`, `@limitKind measured` or `@limitKind derived`, plus `@owner`, `@unit` and `@scope`. Prose that explains the limit's purpose stays above the tags.

### Published

Include `@source` with the exact HTTPS document stating the exact number, a short quote, and `@constraint` naming what it really is: hard quota, advisory threshold, protocol constant or configurable default. Open the source and verify the value. A vendor default is not a maximum, and an example in a vendor's guide is an advisory threshold, not a quota. Record the retrieval date with `@verified`.

```ts
/**
 * @limitKind published
 * @owner RFC 8628 device authorization grant
 * @unit seconds
 * @scope the wait between token polls when a device authorization names no `interval`
 * @constraint the client must wait this long between polls if no interval is provided
 * @source https://datatracker.ietf.org/doc/html/rfc8628#section-3.2 "If no value is provided,
 * clients MUST use 5 as the default."
 * @verified 2026-10-13
 */
const DEFAULT_POLL_SECONDS = 5
```

### Measured

Include all of these:

- `@evidence`: a resolvable measurement record, not a comment asserting success: the application's traces in its observability tool (by query), or a run's output files. No credentials, personal data or raw sensitive errors in code.
- `@observed`: the actual observation interval, including timezone.
- `@environment`: provider, region, plan or account scope, deployment or revision, and the relevant SDK and configuration versions.
- `@workload`: operation family, input size and population, batching and aggregate concurrency. A per-instance pool is not an account-wide cap: every process or serverless instance holds its own.
- `@result`: admitted sample size or duration, measured throughput, latency, throttles and errors, and resource pressure where available. State missing metrics. Distinguish unique operations from duplicated log lines and retries.
- `@decision`: how the selected operating value follows from the observations. State any headroom explicitly. A successful sample demonstrates that sample, not a universal maximum; locating the actual throttling boundary is not required.
- `@revalidate`: concrete invalidation triggers such as an SDK, region, plan, instance class, workload or concurrency change, and newly observed throttling.

A guess, an experiment's starting width and "seemed fast" are not measured operating limits. An observed failure threshold is not a successful operating point. A measured setting cannot override a lower applicable published quota. When the evidence lives in uncommitted run output and disappears with its run, the measured claim is no longer independently verifiable: remeasure it or replace it with a defensible published or derived authority.

### Derived

Use `@derivation` to name the data or the defensible constants and show the arithmetic in code, with why that arithmetic bounds the relevant resource. A derived limit reads its inputs from the constants that defend them, never a second spelling of their numbers:

```ts
/**
 * @limitKind derived
 * @owner the database pool
 * @unit seconds
 * @scope the lifetime of one pooled physical connection
 * @derivation IAM_TOKEN_MINUTES, the published lifetime of the token that signs a connection in, in seconds
 */
const POOL_MAX_LIFETIME_SECONDS = IAM_TOKEN_MINUTES * 60
```

Label reused published defaults as defaults, not empirical throughput or safety. Do not hide an invented factor or reserve inside an otherwise sourced formula. Data lengths, graph cardinalities and `0`/`1` identities need no made-up citation. Code points and unit conversions are not tuning caps. A page size under keyset pagination is not a cap: every row stays reachable through the next cursor, so it is a plain choice with a doc comment saying so, never a `@limitKind`.

## Backpressure, Not Dropped Work

Use scoped concurrency, semaphore, pool or rate-limiting primitives at the resource owner. A concurrency bound controls in-flight work, not requests per second. A rate quota needs rate-aware admission or a finite event budget that provably fits the quota, including retries and lifecycle events.

Queue overflow for later processing; never truncate the population. Batching amortizes orchestration overhead but must preserve every admitted item. Error classification and the provider's retry semantics stay explicit: retry only what a typed error says may succeed when run again, and a retry never grants permission to repeat an ambiguous write.

When no published quota or measured setting exists, keep the documented provider default or derive capacity from a real resource. Do not delete an existing protective cap merely because its documentation is missing and thereby unleash unbounded work: resolve its evidence or report the missing authority. This skill never authorizes a load test, spend or a write to a shared database. Measure only inside authorized traffic, and stop increasing load when throttling, latency collapse or failures appear.

## Hunt and Verification

Search live source, skipping dependencies, vendored code and fixtures. Include inline limits, not just named constants:

```sh
rg -n --glob '*.ts' --glob '*.tsx' --glob '!**/node_modules/**' --glob '!**/fixtures/**' \
  'const [A-Z][A-Z0-9_]* = [0-9_]+|concurrency:|times:|[Tt]imeout|millis|seconds|minutes|max:' .
```

For each hit, verify its category against the actual source or measurement, its units, its scope, its aggregation across instances and its consumers. Check that the bound acts at the resource it claims to protect. For derived values, audit the factors. Use source and diff inspection and the repository's check gate; no synthetic harnesses or disguised acceptance corpora.

Report unsupported values by path, symbol, number and missing evidence. Replace them with sourced or measured limits, or remove obsolete behaviour. Never rename a guess into authority or present a clean typecheck as proof of remote capacity.
