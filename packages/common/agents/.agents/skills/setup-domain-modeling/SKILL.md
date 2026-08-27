---
name: setup-domain-modeling
description: Bootstrap repository-owned domain modeling with glossaries and architecture/business decision records.
disable-model-invocation: true
---

# Setup Domain Modeling

Bootstrap portable domain modeling from [`template/`](template/). The repository's project skill and copied instructions own the behavior after setup.

## Process

### 1. Select The Layout

Inspect the repository's domain boundaries and root `AGENTS.md`. Default to the literal template with one root `GLOSSARY.md`.

When the user requests multiple glossaries or the repository has genuine meaning boundaries, read [`monorepos.md`](monorepos.md).

If root `AGENTS.md` already contains a domain-doc pointer, or any generated file or decision-record directory in the selected layout already exists, stop and report the collision. Root `AGENTS.md` itself is not a collision.

Selection is complete when each term scope has one prospective owner and no collision exists.

### 2. Confirm

Show the user:

- The resulting file tree.
- The exact domain-doc pointer for root `AGENTS.md`.
- For a multi-glossary layout, the exact project-skill replacement and glossary-format rule from `monorepos.md`.
- Every scoped glossary and whether root `GLOSSARY.md` remains.

Wait for confirmation before writing.

### 3. Apply

Copy the base template structure, materializing `.agents/skills/domain-modeling/SKILL.template.md` as `SKILL.md`. For a multi-glossary layout, apply the confirmed adaptations from `monorepos.md`. Merge the domain-doc pointer into root `AGENTS.md` without replacing unrelated instructions.

Application is complete when the selected files and pointer are on disk and unrelated root instructions are unchanged.

### 4. Verify

Verify all of the following:

- Every referenced path exists and every relative Markdown link resolves.
- Root `AGENTS.md` contains the confirmed domain-doc pointer.
- The project `domain-modeling` skill is discoverable.
- ADR and BDR instructions reach the project `domain-modeling` skill and shared format.
- The default layout refers only to root `GLOSSARY.md` and contains no multi-glossary behavior.
- A multi-glossary layout has a complete `GLOSSARY-MAP.md`, map-aware skill and root pointer, the glossary ownership rule, and one owner for every term scope.
- ADRs and BDRs remain centralized and independently numbered.

Report the resulting layout. Setup is complete only when every check passes.
