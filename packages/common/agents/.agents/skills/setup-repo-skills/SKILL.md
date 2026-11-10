---
name: setup-repo-skills
description: Generate repository-owned engineering skills and domain docs, adapted to the repository.
disable-model-invocation: true
---

# Setup Repo Skills

Generate repository-owned skills and docs from [`template/`](template/). The template tree mirrors the target repository: each file sits at its generated path in its generic final form, and each `SKILL.template.md` becomes `SKILL.md`. After setup, the repository owns every generated file and evolves it through normal review.

## Modules

| Module                 | Template paths                                                                         | Recommend when                                                  |
| ---------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `representation-first` | `.agents/skills/representation-first/` except `RELATIONAL.md`                          | Always; on by default                                           |
| Relational             | `.agents/skills/representation-first/RELATIONAL.md`                                    | The repository has a relational database; on by default         |
| `indefensible-numbers` | `.agents/skills/indefensible-numbers/`                                                 | Code bounds concurrency, retries, timeouts, batch size or spend |
| `domain-language`      | `.agents/skills/domain-language/`, `GLOSSARY.md`; `GLOSSARY-MAP.md` for multi-glossary | Domain language shapes the work                                 |
| ADRs                   | `docs/adr/AGENTS.md`                                                                   | The user records architecture decisions                         |
| BDRs                   | `docs/bdr/AGENTS.md`                                                                   | The user records business decisions                             |

Relational requires `representation-first`.

## Process

### 1. Inspect

Read root `AGENTS.md`, the languages and type system, the database engine and data-access layer, and the gates that already run: lint, typecheck, tests, pre-commit hooks, CI.

A collision is a generated path that already exists, or a root pointer topic (domain language, decisions) already present in root `AGENTS.md`. Root `AGENTS.md` itself is not a collision.

Inspection is complete when every module has a recommendation backed by evidence and every collision is known.

### 2. Select

Present each module with its recommendation and evidence, and let the user choose. Stop and report when a selected module collides.

For `domain-language`, default to one root `GLOSSARY.md`. Choose the multi-glossary layout only when the user requests it or repository areas assign different meanings or ownership to the same language; package and workspace boundaries are evidence to inspect, not a reason by themselves. For that layout:

1. Identify each genuine meaning boundary and its glossary path.
2. Give each term scope one owning glossary; resolve conflicting definitions rather than recording both.
3. Keep root `GLOSSARY.md` only when it owns terms shared across boundaries.
4. Keep decision records centralized under root `docs/`.

Selection is complete when the user has confirmed the module set and, for `domain-language`, every term scope has one prospective owner.

### 3. Adapt

Adapt every selected file to the repository. Keep every rule, test and opinion as written; adapt examples, stack mechanics, and pointers to enforcement.

| File                                   | Adapt                                                                                                                                                                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `representation-first/SKILL.md`        | Examples and identifiers in the repository's language and types; the "Rules That Still Bind" type-safety list and gate for its type system and check command; the library vocabulary. Without Relational, drop the `RELATIONAL.md` link and the database trigger from the description. |
| `representation-first/RELATIONAL.md`   | Restate the inference fact for the actual data-access layer; DDL examples in its schema syntax; engine mechanics (generated columns, key generation, identifier limit).                                                                                 |
| `representation-first/sources.md`      | Copy verbatim.                                                                                                                                                                                                                                          |
| `indefensible-numbers/SKILL.md`        | Annotation syntax for the language; where measurement evidence lives; the concurrency and rate-limit primitives; the hunt pattern, search roots and exclusions; the check command.                                                                     |
| `domain-language/`                     | For multi-glossary, the adaptation below.                                                                                                                                                                                                               |
| `GLOSSARY-MAP.md`                      | One entry per selected glossary; the Shared entry only when root `GLOSSARY.md` remains. Paths and scopes only.                                                                                                                                         |
| `docs/adr/AGENTS.md`, `docs/bdr/AGENTS.md` | Replace generic "What Qualifies" examples with the repository's own where real ones are visible. With one journal selected, drop the cross-journal filing rule.                                                                                     |

State enforcement only where a gate actually runs it; collect every unenforced rule as a gap for the user. Every generated file references only selected modules.

**Multi-glossary adaptation.** In `domain-language/SKILL.md`, replace the Applicable Glossary section with:

```md
## Applicable Glossaries

Use `GLOSSARY-MAP.md` as the authoritative glossary index. Read every glossary it marks applicable, shared first when present, then the nearest scoped glossary.
```

Add to `domain-language/GLOSSARY-FORMAT.md` rules:

```md
- Give each term one owning glossary and register every glossary with its path and scope in `GLOSSARY-MAP.md`.
```

Place a `GLOSSARY.md` at each selected meaning boundary.

Adaptation is complete when every selected file is adapted, every gap is listed, and no generated file references an unselected module.

### 4. Confirm

Show the user:

- The resulting file tree.
- The exact root pointer lines.
- Each adapted file's changes against its template.
- The enforcement gaps.

Wait for confirmation before writing.

### 5. Apply

Write the selected files, materializing each `SKILL.template.md` as `SKILL.md`. Merge the root pointer lines into root `AGENTS.md` without changing unrelated instructions.

Application is complete when the confirmed files and pointers are on disk and unrelated root instructions are unchanged.

### 6. Verify

- Every referenced path exists and every relative Markdown link resolves.
- Every generated skill is discoverable: `.agents/skills/<name>/SKILL.md` with frontmatter `name` equal to `<name>` and a single-line `description`.
- Root `AGENTS.md` carries exactly the confirmed pointer lines.
- No generated file references an unselected module.
- A single-glossary layout refers only to root `GLOSSARY.md`; a multi-glossary layout has a complete `GLOSSARY-MAP.md`, the map-aware skill and pointer, the ownership rule, and one owner per term scope.

Report the generated layout and the enforcement gaps. Setup is complete only when every check passes.

## Root Pointers

Domain language, single glossary:

```md
Domain language: before work involving domain concepts, read `GLOSSARY.md`; use the project `domain-language` skill when discussing or changing domain language.
```

Domain language, multi-glossary:

```md
Domain language: before work involving domain concepts, read `GLOSSARY-MAP.md` and the glossaries it marks applicable; use the project `domain-language` skill when discussing or changing domain language.
```

Decisions, both journals (one line):

```md
Decisions: before changing an area, check its records in `docs/adr/` (architecture) and `docs/bdr/` (business); record a decision only when it is hard to reverse, surprising without context, and a genuine trade-off, reading that journal's `AGENTS.md` first.
```

Decisions, one journal: the same line naming only that journal, e.g. for ADRs:

```md
Decisions: before changing an area, check its records in `docs/adr/`; record an architecture decision only when it is hard to reverse, surprising without context, and a genuine trade-off, reading `docs/adr/AGENTS.md` first.
```
