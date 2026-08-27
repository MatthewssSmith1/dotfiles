# Monorepos

Use multiple glossaries only when repository areas assign different meanings or ownership to domain language. Package and workspace boundaries are evidence to inspect, not a reason by themselves.

## Select The Layout

1. Identify each genuine meaning boundary and its prospective glossary path.
2. Give each term scope one glossary owner; resolve conflicting definitions rather than recording both.
3. Keep root `GLOSSARY.md` only when it owns terms shared across boundaries.
4. Keep architecture and business decision records centralized under root `docs/`.

## Adapt The Base Template

In `.agents/skills/domain-modeling/SKILL.md`, replace:

```md
## Applicable Glossary

Use root `GLOSSARY.md` as the authority for domain language.
```

with:

```md
## Applicable Glossaries

Use `GLOSSARY-MAP.md` as the authoritative glossary index. Read every glossary it marks applicable, shared first when present, then the nearest scoped glossary.
```

Add this rule to `.agents/skills/domain-modeling/GLOSSARY-FORMAT.md`:

```md
- Give each term one owning glossary and register every glossary with its path and scope in `GLOSSARY-MAP.md`.
```

Replace the root `AGENTS.md` domain-doc pointer with:

```md
Domain model: before work involving domain concepts, read `GLOSSARY-MAP.md` and the glossaries it marks applicable; use the project `domain-modeling` skill when discussing or changing domain language or recording architecture or business decisions.
```

Add a scoped `GLOSSARY.md` at each selected meaning boundary. Remove root `GLOSSARY.md` when it has no shared terms to own.

## Map Template

```md
# Glossary Map

Authoritative index of this project's domain glossaries.

## Glossaries

- [Shared](./GLOSSARY.md): terms used across repository areas
- [Area](./path/to/GLOSSARY.md): terms owned by this domain area
```

Add every selected glossary to the map. Include the Shared entry only when root `GLOSSARY.md` remains, and replace the Area entry with the actual scoped glossaries. The map records paths and scopes only; keep relationships and architecture in their authoritative documentation.
