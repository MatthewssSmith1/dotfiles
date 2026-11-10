# Business Decision Records

Write one record per real business decision only when all three gates pass:

1. **Hard to reverse:** changing the decision later has meaningful cost.
2. **Surprising without context:** a future reader would reasonably ask why it was done this way.
3. **A genuine trade-off:** real alternatives existed and one was selected for specific reasons.

Skip the record when any gate fails. File a decision that is also an architecture decision under its primary driver, and cross-link `docs/adr/` when useful.

## What Qualifies

Durable decisions about business direction: positioning, audience, naming, licensing, governance, and similar choices whose primary driver is not architecture.

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
