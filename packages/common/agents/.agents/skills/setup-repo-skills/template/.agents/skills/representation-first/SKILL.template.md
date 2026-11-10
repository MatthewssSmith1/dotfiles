---
name: representation-first
description: Load before designing or refactoring code, and whenever you reach for a new branch, flag, guard, optional field, sentinel value, fallback or re-validation; when designing a type, schema, roster, state machine or database table; when reviewing a diff that adds conditionals. Change the representation so the case stops being special or stops being expressible.
---

# Representation First

The biggest lever in programming is the data representation, not the control flow. When a new case shows up, you can patch the trace of the computation with another branch, flag or guard, and complexity piles up in the control flow. Or you can change the data, types and invariants so the case stops being special, or stops being expressible at all. Do the second.

Database tables follow the same principle; read [`RELATIONAL.md`](RELATIONAL.md) before designing or changing a table, query or migration.

## The Moves

In order of preference:

1. **Make the state impossible.**
   - Replace clusters of booleans, optionals and nullable fields with a tagged union whose arms carry exactly their own fields.
   - No `undefined` meaning "absent" next to a flag meaning "present". No `""` or `-1` sentinels. No `kind` plus fields that only some kinds use.

   ```ts
   // Eight representable states, few of them valid.
   type Fetch = { loading: boolean; error?: Error; data?: Data }
   // Exactly the valid states.
   type Fetch = { _tag: "loading" } | { _tag: "failed"; error: Error } | { _tag: "loaded"; data: Data }
   ```

2. **Parse at the boundary; never re-validate inside.**
   - Outside input (a request payload, environment variables, CLI arguments, a file or a provider's answer) is decoded once into a type that carries the proof, and everything downstream takes that type.
   - Never defend against a trusted component: rows from our own database arrive as the data-access layer types them, with brands on the columns and constraints holding their invariants. A check repeated deep inside is a sign the type is too weak.
3. **No fallbacks.** A fallback is usually a representation that admits a state production never has, plus a branch that papers over it: `x ?? default`, `x || default`, a defaulted or optional parameter, a `catch` that substitutes a value, "if absent, use X".
   - **When production always supplies the value, make it required** and delete the default. Tests build the real thing, through the production path.
   - **When the absence is a real case, make it a variant** whose handling is exhaustive: a configured database host means a remote database and its absence means the local one, decoded into one target type, never a default host. Absence is an option type or an arm, never a substituted value.
   - **When a failure can happen, make it a typed error** named `<Subject><State>` (`LessonNotFound`, `TransientFailure`), never a substituted value or an untyped throw.
   - **What stays:** a genuine domain absence (an accumulator's `map.get(key) ?? 0`), and a local default declared once in its package's configuration module.
4. **Brand what is distinct.** Ids, titles, endpoints and resource names get a nominal brand when mixing them up would be a bug. A brand is minted only in its declaring module, and brands are trusted once minted: no defensive validators downstream.
5. **Closed vocabularies live at their owner.** One roster and its derived type (`const GRADES = [...] as const`, `type Grade = (typeof GRADES)[number]`). A new member is a roster entry, never a second spelling, and tests name a member through its type.
6. **Exhaustive dispatch over tags.** A `switch` on a discriminant covers every arm with no `default`, so a new variant is a compile error everywhere it matters. Prefer a record of handlers keyed by tag, or pattern matching, over scattered conditionals.
7. **Choose coordinates that delete special cases:** half-open ranges, an empty element instead of "first and last are special", one uniform node shape instead of per-kind side tables, a UUIDv7 id that is its row's creation time instead of a timestamp column beside it.
8. **Reify hairy control flow as data:** a small table or IR plus an evaluator instead of nested branching.

## Rules That Still Bind

- **Fully type-safe:** no casts, no untyped values, no non-null assertions, no lying type predicates. The gate is the repository's typecheck and lint.
- **The feasibility rule:** if the type system can't prove the invariant, don't fake it with a predicate, a conditional tower or a shadow type. Use the plainest representation the type system can check, and keep the runtime check at the one boundary that parses.
- **Delete before you add,** and cut over hard: a new representation replaces the old one everywhere in one change, with no shim, alias or reader of the old form.
- **Libraries as they are meant to be used:** the language's and libraries' own option, result, decoding and matching vocabulary is the representation vocabulary; don't home-roll a second one.

## The Limit

Representation removes _accidental_ complexity, not _essential_ complexity (Brooks). Don't force two genuinely different cases into one representation; that only hides the branch in a flag, which is worse than the branch. If the right representation isn't visible yet, leave it. A refactor must be earned by the pattern the code already shows.

---

## Spiky Points of View

1. **The data representation determines a program's complexity. The algorithm and the control flow are downstream of it.**
   - Code review argues about control flow and "clean code" is taught as the art of writing better conditionals; the lineage says the leverage is upstream, in the shape of the data, in nearly identical words from Brooks to Torvalds (Insights 1–3).
   - What makes the claim more than one school's taste is the convergence: four practitioners reached it independently across thirty-one years, and two of them cite Brooks by name (Insight 4).
   - When complexity grows, change the representation before you add to the control flow, because the representation is where the complexity actually lives.
2. **Most of the branches in typical code are not handling the problem. They are guarding against states a more precise representation would have made impossible.**
   - Three independent booleans (`loading`, `error`, `data`) admit eight states, of which only a few are valid. A four-case sum type admits exactly four, and the guards have nothing left to guard (Insight 5).
   - Minsky: "make illegal states unrepresentable." King: validation checks a condition and throws away what it learned, so every caller downstream must check again; parsing returns a type that carries the proof, so the check happens once at the boundary (Insight 7).
   - Null is the proof by counterexample: it sits in every type at once, which is exactly why it forces a check on every use (Insight 6). When you reach for a guard, ask what representation would make the state impossible.
3. **Most special cases belong to the representation, not the problem. Change the representation and they are gone, not handled.**
   - **Dijkstra's half-open interval** makes length equal `b − a`, the empty range clean and adjacent ranges gap-free: the off-by-one is unrepresentable, not handled (Insight 11).
   - **Homogeneous coordinates** make translation the same matrix multiply as rotation (Insight 12).
   - **A sentinel node** makes the first and last elements stop being special (Insight 10).
   - **The ceiling** is turning tangled control flow into data: an AST with a small evaluator. Greenspun's rule is the warning that a complex enough program grows a bad interpreter by accident if you don't build a good one on purpose (Insights 13, 14).

## Insights

Conclusions drawn from the sources in [`sources.md`](sources.md); the bridge from raw material to the points of view.

### The Lineage

1. **Two ways to absorb a new case.** Patch the trace (a branch, flag or guard) and complexity gathers in the control flow; change the structure (data, types, invariants) and the case stops being special or expressible. Same problem, two surfaces, opposite cost profiles.
2. **Brooks stated it; Pike made it operational.** Brooks: "Show me your flowcharts and conceal your tables, and I shall continue to be mystified. Show me your tables, and I won't usually need your flowcharts; they'll be obvious" (_The Mythical Man-Month_, ch. 9, p. 102, under "Representation Is the Essence of Programming"). Pike's Rule 5, "Data dominates… the algorithms will almost always be self-evident," cites him: "(See Brooks p. 102.)"
3. **It holds at the largest scale.** Torvalds: "Bad programmers worry about the code. Good programmers worry about data structures and their relationships." Git's content-addressed object model is an existence proof.
4. **The convergence is the evidence.** Brooks (1975) → Pike (1989, citing Brooks) → Raymond (1997, "smart data structures and dumb code", citing Brooks) → Torvalds (2006, independent), across four subcultures with the citations written down.

### Why Precise Types Remove Branches

5. **Illegal states are the hidden source of branching.** Three independent flags give eight states, few of them valid; the invalid ones get guarded everywhere. A sum type gives exactly the valid states.
6. **Null is the mechanism, inverted.** Null is a member of every type, which is why it forces a check on every dereference. The fix Hoare knew and skipped, the disjoint union, is the sum type.
7. **Validation discards proof; parsing keeps it** (King, "Parse, Don't Validate"). A parser returns a refined type that carries the proof, so the check happens once at the boundary: the information the branch tested for moves into the type.
8. **A type signature is an enforced specification** (Wadler, "Theorems for Free!"; Reynolds' Abstraction Theorem). `∀a. [a] → [a]` can only rearrange, duplicate or drop, and well-typed clients cannot branch on a concrete representation.

### Techniques That Remove Branches

9. **A switch on a type tag is a polymorphism not yet named** (Fowler, "Replace Conditional with Polymorphism"). The variation moves from a tag plus branches into identity plus dispatch.
10. **Absence and boundaries are representational choices.** A null object (Woolf) represents "nothing" as a real value; a sentinel node (CLRS §10.2) represents the boundary as a real node. One added object removes a category of branches.
11. **Off-by-one is usually a coordinate error** (Dijkstra, EWD831). The half-open interval is the one convention where length is `b − a` and the empty range is clean.
12. **Some special cases are pure coordinate artifacts.** Translation is an exception in Cartesian coordinates and an ordinary matrix multiply in homogeneous ones.
13. **Greenspun's rule is the principle as a warning.** Deny yourself good representational tools and complexity grows you a bad interpreter by accident.
14. **The ceiling is to make control flow into data** (SICP ch. 4: "the evaluator… is just another program"). Table-driven code, state machines and DSLs are one family.

### The Limit

15. **Representation is globally cheap but locally expensive; control flow is the reverse.** A representation costs design and indirection up front; a branch is free now and expensive later, through drift and combinatorial state. That cost structure, not virtue, is why adding a branch is the common reflex.
16. **It removes accidental complexity, not essential complexity** (Brooks, "No Silver Bullet"). Force two genuinely different cases into one representation and the branching hides inside config flags. The right representation is usually only visible after the imperative version exposes the pattern.

Quotes, page references and links behind each insight: [`sources.md`](sources.md).
