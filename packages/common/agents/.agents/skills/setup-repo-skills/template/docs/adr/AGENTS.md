# Architecture Decision Records

Write one record per real architecture decision only when all three gates pass:

1. **Hard to reverse:** changing the decision later has meaningful cost.
2. **Surprising without context:** a future reader would reasonably ask why it was done this way.
3. **A genuine trade-off:** real alternatives existed and one was selected for specific reasons.

Skip the record when any gate fails. File a decision that is also a business decision under its primary driver, and cross-link `docs/bdr/` when useful.

## What Qualifies

- **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library: just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite. These stop the next engineer from "fixing" something that was deliberate.
- **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it; otherwise someone will suggest GraphQL again in six months.

## Format

Files use `NNNN-short-slug.md`, numbered independently from `0001`: scan this directory for the highest number and increment it. Keep accepted records append-only except for lifecycle metadata and supersession links.

A single-paragraph record is valid. Record that a decision was made and why rather than filling out sections. Include these only when they add genuine value:

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by NNNN`) when decisions may be revisited.
- **Considered Options** when rejected alternatives are worth remembering.
- **Consequences** when non-obvious downstream effects need to be recorded.

```md
# {Short title of the decision}

{One to three sentences covering the context, decision, and reason.}
```
