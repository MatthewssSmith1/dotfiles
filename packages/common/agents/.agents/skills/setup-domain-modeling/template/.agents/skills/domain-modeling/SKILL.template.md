---
name: domain-modeling
description: Use when discussing domain concepts, changing glossary language, or editing architecture/business decisions.
---

# Domain Modeling

## Applicable Glossary

Use root `GLOSSARY.md` as the authority for domain language.

## During Work

- Use canonical terms consistently.
- Surface conflicts with documented language immediately rather than choosing silently.
- Replace vague or overloaded language with one precise canonical term.
- Stress-test relationships and boundaries with concrete edge cases.
- Check domain claims against the implementation. Surface contradictions without assuming the current code is authoritative.
- Record resolved language promptly rather than batching glossary maintenance.

## Glossaries

Keep glossaries focused on domain language, free of implementation details, specifications, plans, scratch notes, and technical decisions. Follow [`GLOSSARY-FORMAT.md`](GLOSSARY-FORMAT.md) when changing a glossary.

## Decision Records

Architecture and business decisions are centralized in `docs/adr/` and `docs/bdr/`. Before choosing a journal, read their qualification guidance in [`docs/adr/AGENTS.md`](../../../docs/adr/AGENTS.md) and [`docs/bdr/AGENTS.md`](../../../docs/bdr/AGENTS.md).

Write one record per real decision only when all three gates pass:

1. **Hard to reverse:** changing the decision later has meaningful cost.
2. **Surprising without context:** a future reader would reasonably ask why it was done this way.
3. **A genuine trade-off:** real alternatives existed and one was selected for specific reasons.

Skip the record when any gate fails.

- Number ADRs and BDRs independently, beginning at `0001`.
- File a decision spanning both journals under its primary driver; cross-link the other journal when useful.
- Keep accepted records append-only except for lifecycle metadata and supersession links.
- Follow [`DR-FORMAT.md`](DR-FORMAT.md) when recording or editing a decision.
