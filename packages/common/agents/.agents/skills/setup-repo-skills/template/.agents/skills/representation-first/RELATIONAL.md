# Relational Representation

[Representation first](SKILL.md), applied to the database schema and the queries that read it:

- **Push each invariant into the relation and its inferred type** so the compiler carries the proof. Establish a fact once, structurally, instead of re-checking it at every consumer.
- **Make illegal states unrepresentable** rather than representable and guarded.
- **Never defend against our own SQL.** Rows arrive as the data-access layer types them, with brands declared on the columns and named `CHECK` constraints holding each brand's invariant. No application decoder re-parses a row.

The load-bearing fact: **the data-access layer infers a column's type from its declared type and nullability alone.** `CHECK` constraints, triggers and conventions are invisible to it. A column a `CHECK` guarantees present still infers `T | null` at every read site, forcing every consumer to re-narrow or cast. A `NOT NULL` column on a typed sidecar infers `T`, and an inner join carries that non-nullability into the query's result type.

A schema change is complete when every new or changed table satisfies every section below, and every omission and writer-owned invariant is stated in the table's comment.

## Strict BCNF: Analyze, Don't Guess

A relation is in **Boyce–Codd normal form** when every non-trivial functional dependency `X → A` has a superkey `X`. For every new or changed table, identify:

1. **Every candidate key:** the primary key, and every `UNIQUE` constraint that is a key.
2. **Every functional dependency (FD):** for each non-key attribute, verify that it depends on **each whole candidate key**, never on a proper subset of a key, another non-key attribute, or a parent row reached through a foreign key.
3. **Every violation:** any FD `X → A` where `X` is not a superkey. Remove `A` from the relation.

**The two recurring violations:**

- **Parent-determined attributes** (transitive dependencies through a foreign key). If `order_lines` references `order_id` and `order_id → customer_id` holds in `orders`, storing `customer_id` on `order_lines` violates BCNF. The same holds when a column is added solely to support a composite-FK membership check, unless it is a membership column (below).
- **Derivable facts.** Never store an attribute that a stored key determines through joins.

**The one exception: membership columns.** A child may carry columns its parent determines when they exist only to complete composite foreign keys proving the child belongs with its parent: a link between two versions carries their shared `document_id` so that `(document_id, version_id)` and `(document_id, parent_version_id)` → `versions (document_id, id)` prove both ends are in one document. The exception holds only when the parent is immutable and the child is written with it, or after it, in the writer's transaction:

- the foreign key checks the copy once, when the child is inserted, and no later write can make it disagree;
- a child its parent cannot satisfy fails its insert with that foreign key, which the writer maps to a typed failure;
- deleting the parent stays refused while children reference it.

The copy can never disagree with its parent, so it carries no update anomaly. The table's comment names each membership column and the foreign key it completes. A column copied for reading convenience is still a violation.

**Refactoring procedure:**

1. Drop the violating attribute from the table.
2. Rewrite readers to recover it by joining along the dependency.
3. When the attribute enforced a cross-entity invariant, move the check to the relation's **single writer** inside its transaction, failing with a typed error and covering the refusal with a property test.
4. State the omitted attribute, the FD that makes it derivable, and the writer that owns the invariant in the table's comment.

## Discriminated Unions: Header Plus Typed Sidecars

**The banned shape.** A _monomorphic discriminated-union table_ models a sum type as one wide table with nullable payload columns gated by a `CHECK` on `kind` (or inferred from the null pattern). Illegal states are representable, and the access layer infers every payload column as `T | null`. Also banned: JSON columns used as a shortcut for structured domain variants.

**Detection.** A table is a monomorphic discriminated union when it has any of:

- a `CHECK` gating one column's nullability on another column's value (`(kind = 'label') = (text IS NOT NULL)`, XOR groups, all-null-or-all-set groups);
- a cluster of nullable columns that are set together or null together;
- a `kind` / `status` / `outcome` enum beside nullable payload columns with no sidecars.

**The required shape:**

- **Header table:**
  - Holds the `NOT NULL` discriminant (`kind`) and the attributes common to **every** arm, all `NOT NULL`.
  - Carries `UNIQUE (id, kind)` as the composite-FK target for sidecars, so one header row can never attach two conflicting arms.
- **One typed sidecar per payload-bearing arm:**
  - Primary key is the header's primary key.
  - Every payload column is `NOT NULL`; any genuinely optional field within that arm is justified in the table's comment.
  - Pins its arm with a **generated constant discriminant** and a composite foreign key `(<header>_id, kind) → <header> (id, kind)`. Because a generated column cannot be written, a wrong-arm row is unrepresentable without a redundant `CHECK`.
- **Payload-less arms get no sidecar.** An empty or marker arm is represented by the header value or a key-only marker row, never a payloadless sidecar alongside a discriminant.

**Naming.** Every table name is plural (`orders`, `shipments`), and every sidecar carries its header's **full singular stem** plus the **plural arm noun** (`shipment_events` → `shipment_event_delays` / `shipment_event_deliveries`).

**Completeness.** A composite foreign key enforces child → parent only; an orphan header (inserted without its sidecar) is closed by **writer-transaction discipline**: insert the header and its sidecar together in one transaction, and state this invariant in the header's comment.

```sql
CREATE TYPE overlay_kind AS ENUM ('label', 'arrow');

-- One overlay on a segment: the discriminant every arm shares. Its arm's payload lives
-- in exactly one sidecar, inserted in the same transaction as this row.
CREATE TABLE segment_overlays (
  id uuid NOT NULL DEFAULT uuidv7(),
  segment_id uuid NOT NULL,
  kind overlay_kind NOT NULL,
  CONSTRAINT segment_overlays_pk PRIMARY KEY (id),
  CONSTRAINT segment_overlays_id_v7_ck CHECK (uuid_extract_version(id) = 7),
  CONSTRAINT segment_overlays_id_kind_uq UNIQUE (id, kind)
);

-- The label arm's payload, pinned to its arm by a generated discriminant.
CREATE TABLE segment_overlay_labels (
  overlay_id uuid NOT NULL,
  kind overlay_kind NOT NULL GENERATED ALWAYS AS ('label'::overlay_kind) STORED,
  body text NOT NULL,
  CONSTRAINT segment_overlay_labels_pk PRIMARY KEY (overlay_id),
  CONSTRAINT fk_segment_overlay_labels_segment_overlays
    FOREIGN KEY (overlay_id, kind) REFERENCES segment_overlays (id, kind)
);
```

**Set-gated variance (the set-pin).** When a sidecar or child reference is valid for a **subset** of kinds (`media_kind IN ('image', 'video')` referencing `assets (id, kind)`), a generated constant cannot pin multiple values. Carry a real `NOT NULL` discriminant column on the referencing table, pin it with the composite foreign key `(asset_id, media_kind) → assets (id, kind)`, and add `CHECK (media_kind IN ('image', 'video'))`.

**The decomposition limit.** A mandatory 1:1 sidecar that is present for every header row adds no FD and encodes no arm. Collapse it into the header table. Decompose until illegal states vanish, and no further.

**Reading unions:**

- **Known arm: inner-join the sidecar.** It both filters the query to that arm and infers every payload column as `NOT NULL`. Prefer it over a redundant `WHERE kind = '<arm>'`.
- **Union boundary: left-join every sidecar and switch once on `kind`,** exhaustively, at the boundary that constructs the domain union. Inside a payload-bearing arm's case, a `null` sidecar column means an orphan header violated writer-transaction discipline: a defect. Fail loudly, never with a fallback value or an N-column `!== null` conjunction.

## Keys Carry Time

- **Entity and event tables** use a UUIDv7 primary key with a version-7 `CHECK`. `ORDER BY id` is creation order on the primary-key index, and the id yields its creation time.
- **Content-addressed tables** use the content hash as their primary key, validated by a format `CHECK`.
- **Time lives in the key, not a column:** no `created_at`, `updated_at`, or other timestamp columns. Append-only history derives current state from the latest row by id (`SELECT DISTINCT ON (subject_id) … ORDER BY subject_id, id DESC`).
- **A domain duration or offset** is an integer column named for its unit (`duration_ms`, `start_ms`) with a non-negative `CHECK`.

## Brands and Constraints

- **Brand every distinct column.** Columns carrying domain identifiers, hashes, slugs, titles, ordinals or measurements declare the application's brand type and pair it with a `CHECK` enforcing exactly that brand's decoder invariant. Prove agreement with a property test that draws valid and invalid values and asserts the decoder and the `CHECK` accept and reject the same inputs.
- **Name every constraint explicitly** from the full table name, within the engine's identifier limit (63 bytes in PostgreSQL):
  - Primary key: `<table>_pk`
  - Foreign key: `fk_<table>_<target>`
  - Unique: `<table>_<columns>_uq`
  - Check: `<table>_<rule>_ck` (including `<table>_id_v7_ck` on every UUIDv7 primary key)
- **Enums** are backed by the application's closed roster, so application types and SQL enums share one source of truth.
- **The table's comment** states what one row represents, its write discipline (append-only, or the change its grant exception admits), any BCNF omissions, and writer-owned invariants including sidecar completeness.

## Append-Only by Default

The application's database role holds `SELECT, INSERT` on every table, so the database refuses any change to a written row: a change is a new row. A table whose rows change takes an explicit, listed grant exception with its reason: `UPDATE` of exactly the columns that change in place, or `DELETE`. Reach for the exception only when the domain changes the row; an insert-or-read needs none (`ON CONFLICT DO NOTHING` beside a read of the existing row).
