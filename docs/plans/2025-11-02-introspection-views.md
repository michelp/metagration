# Database Introspection Views Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comprehensive database introspection views to metagration schema for webapp access to table structure, columns, constraints, and statistics.

**Architecture:** Hierarchical view design with base `relations` view for common fields, type-specific detail views for specialized attributes, and supporting views for columns, constraints, and statistics. All views respect PostgreSQL permissions using `has_table_privilege()`.

**Tech Stack:** PostgreSQL 18, pg_catalog views, information_schema, pgTAP for testing

---

## Task 1: Add metagration.relations Base View

**Files:**
- Modify: `sql/metagration.sql` (add view at end, before closing comment)
- Create: `test/introspection.sql` (new test file)
- Modify: `test/test.sql` (update plan count and include new test file)

**Step 1: Write the failing test**

Create `test/introspection.sql`:

```sql
-- Test metagration.relations view

-- Test 1: relations view exists and is accessible
SELECT has_view('metagration', 'relations', 'relations view should exist');

-- Test 2: relations view has expected columns
SELECT has_column('metagration', 'relations', 'schema_name', 'relations should have schema_name column');
SELECT has_column('metagration', 'relations', 'relation_name', 'relations should have relation_name column');
SELECT has_column('metagration', 'relations', 'relation_type', 'relations should have relation_type column');
SELECT has_column('metagration', 'relations', 'owner', 'relations should have owner column');
SELECT has_column('metagration', 'relations', 'row_estimate', 'relations should have row_estimate column');

-- Test 3: relations view shows at least metagration schema tables
SELECT ok(
    (SELECT COUNT(*) FROM metagration.relations WHERE schema_name = 'metagration') >= 2,
    'relations view should show metagration.script and metagration.log tables'
);

-- Test 4: relation_type contains expected values
SELECT ok(
    (SELECT relation_type FROM metagration.relations WHERE schema_name = 'metagration' AND relation_name = 'script') = 'table',
    'metagration.script should have relation_type = table'
);
```

**Step 2: Update test.sql to include new test file**

Modify `test/test.sql`:

```sql
SELECT plan(118);  -- Was 109, adding 9 new tests
\ir core.sql
\ir verify.sql
\ir security.sql
\ir introspection.sql
SELECT * FROM finish();
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'relations' does not exist"

**Step 4: Write minimal implementation**

Add to end of `sql/metagration.sql` (before final comment):

```sql
-- ============================================================================
-- DATABASE INTROSPECTION VIEWS
-- ============================================================================

-- Base view: metagration.relations
-- All table-like objects with common attributes
CREATE VIEW metagration.relations
    SECURITY INVOKER
    AS
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN CASE
            WHEN c.relispartition THEN 'partition'
            ELSE 'table'
        END
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'matview'
        WHEN 'f' THEN 'foreign_table'
        WHEN 'p' THEN 'table'  -- partitioned table
    END AS relation_type,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    ts.spcname AS tablespace,
    c.reltuples::bigint AS row_estimate,
    COALESCE(pg_catalog.pg_total_relation_size(c.oid), 0) AS total_bytes,
    COALESCE(pg_catalog.pg_table_size(c.oid), 0) AS table_bytes,
    COALESCE(pg_catalog.pg_indexes_size(c.oid), 0) AS index_bytes,
    COALESCE(pg_catalog.pg_total_relation_size(c.oid), 0) -
        COALESCE(pg_catalog.pg_table_size(c.oid), 0) -
        COALESCE(pg_catalog.pg_indexes_size(c.oid), 0) AS toast_bytes,
    pg_catalog.obj_description(c.oid, 'pg_class') AS comment,
    s.last_vacuum AS created_at,
    s.last_analyze AS last_analyzed,
    (c.relhasindex) AS has_indexes,
    (EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid = c.oid AND tgisinternal = false)) AS has_triggers,
    (c.relhasrules) AS has_rules
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_tablespace ts ON ts.oid = c.reltablespace
LEFT JOIN pg_catalog.pg_stat_all_tables s ON s.relid = c.oid
WHERE c.relkind IN ('r', 'v', 'm', 'f', 'p')
    AND n.nspname NOT IN ('pg_toast')
    AND pg_catalog.has_table_privilege(c.oid, 'SELECT');
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 118 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.relations base introspection view"
```

---

## Task 2: Add metagration.columns View

**Files:**
- Modify: `sql/metagration.sql` (add view after relations)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.columns view

-- Test 10: columns view exists
SELECT has_view('metagration', 'columns', 'columns view should exist');

-- Test 11: columns view has expected columns
SELECT has_column('metagration', 'columns', 'schema_name', 'columns should have schema_name');
SELECT has_column('metagration', 'columns', 'table_name', 'columns should have table_name');
SELECT has_column('metagration', 'columns', 'column_name', 'columns should have column_name');
SELECT has_column('metagration', 'columns', 'data_type', 'columns should have data_type');
SELECT has_column('metagration', 'columns', 'is_nullable', 'columns should have is_nullable');

-- Test 12: columns view shows metagration.script columns
SELECT ok(
    (SELECT COUNT(*) FROM metagration.columns WHERE schema_name = 'metagration' AND table_name = 'script') >= 5,
    'columns view should show metagration.script columns'
);

-- Test 13: column metadata is accurate
SELECT is(
    (SELECT data_type FROM metagration.columns WHERE schema_name = 'metagration' AND table_name = 'script' AND column_name = 'revision'),
    'bigint',
    'revision column should be bigint type'
);
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(125);  -- Was 118, adding 7 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'columns' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after relations view:

```sql
-- metagration.columns
-- Comprehensive column information for all accessible tables
CREATE VIEW metagration.columns
    SECURITY INVOKER
    AS
SELECT
    c.table_schema AS schema_name,
    c.table_name,
    c.column_name,
    c.ordinal_position,
    c.data_type,
    c.udt_name,
    c.character_maximum_length,
    c.numeric_precision,
    c.numeric_scale,
    (c.is_nullable = 'YES') AS is_nullable,
    c.column_default,
    COALESCE(c.is_generated = 'ALWAYS', false) AS is_generated,
    c.generation_expression,
    COALESCE(c.is_identity = 'YES', false) AS is_identity,
    c.identity_generation,
    c.identity_start::bigint,
    c.identity_increment::bigint,
    c.collation_name,
    pg_catalog.col_description(
        (c.table_schema || '.' || c.table_name)::regclass::oid,
        c.ordinal_position
    ) AS comment
FROM information_schema.columns c
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = c.table_schema
    AND r.relation_name = c.table_name
);
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 125 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.columns introspection view"
```

---

## Task 3: Add metagration.constraints View

**Files:**
- Modify: `sql/metagration.sql` (add view after columns)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.constraints view

-- Test 14: constraints view exists
SELECT has_view('metagration', 'constraints', 'constraints view should exist');

-- Test 15: constraints view has expected columns
SELECT has_column('metagration', 'constraints', 'schema_name', 'constraints should have schema_name');
SELECT has_column('metagration', 'constraints', 'table_name', 'constraints should have table_name');
SELECT has_column('metagration', 'constraints', 'constraint_name', 'constraints should have constraint_name');
SELECT has_column('metagration', 'constraints', 'constraint_type', 'constraints should have constraint_type');

-- Test 16: constraints view shows metagration.script primary key
SELECT ok(
    (SELECT COUNT(*) FROM metagration.constraints
     WHERE schema_name = 'metagration'
     AND table_name = 'script'
     AND constraint_type = 'PRIMARY KEY') >= 1,
    'constraints view should show metagration.script primary key'
);
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(131);  -- Was 125, adding 6 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'constraints' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after columns view:

```sql
-- metagration.constraints
-- All constraint types unified
CREATE VIEW metagration.constraints
    SECURITY INVOKER
    AS
SELECT
    tc.table_schema AS schema_name,
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    ARRAY_AGG(kcu.column_name ORDER BY kcu.ordinal_position) FILTER (WHERE kcu.column_name IS NOT NULL) AS column_names,
    cc.check_clause,
    ccu.table_schema AS foreign_schema_name,
    ccu.table_name AS foreign_table_name,
    ARRAY_AGG(ccu.column_name ORDER BY kcu.ordinal_position) FILTER (WHERE ccu.column_name IS NOT NULL) AS foreign_column_names,
    rc.match_option,
    rc.update_rule,
    rc.delete_rule,
    (tc.is_deferrable = 'YES') AS is_deferrable,
    (tc.initially_deferred = 'YES') AS initially_deferred
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
    ON tc.constraint_schema = kcu.constraint_schema
    AND tc.constraint_name = kcu.constraint_name
    AND tc.table_name = kcu.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_schema = ccu.constraint_schema
    AND tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.referential_constraints rc
    ON tc.constraint_schema = rc.constraint_schema
    AND tc.constraint_name = rc.constraint_name
LEFT JOIN information_schema.check_constraints cc
    ON tc.constraint_schema = cc.constraint_schema
    AND tc.constraint_name = cc.constraint_name
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = tc.table_schema
    AND r.relation_name = tc.table_name
)
GROUP BY
    tc.table_schema, tc.table_name, tc.constraint_name, tc.constraint_type,
    cc.check_clause, ccu.table_schema, ccu.table_name,
    rc.match_option, rc.update_rule, rc.delete_rule,
    tc.is_deferrable, tc.initially_deferred;
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 131 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.constraints introspection view"
```

---

## Task 4: Add metagration.tables_detail View

**Files:**
- Modify: `sql/metagration.sql` (add view after constraints)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.tables_detail view

-- Test 17: tables_detail view exists
SELECT has_view('metagration', 'tables_detail', 'tables_detail view should exist');

-- Test 18: tables_detail shows metagration.script
SELECT ok(
    (SELECT COUNT(*) FROM metagration.tables_detail WHERE schema_name = 'metagration' AND table_name = 'script') = 1,
    'tables_detail should show metagration.script'
);

-- Test 19: persistence attribute is correct
SELECT is(
    (SELECT persistence FROM metagration.tables_detail WHERE schema_name = 'metagration' AND table_name = 'script'),
    'permanent',
    'metagration.script should be permanent table'
);
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(134);  -- Was 131, adding 3 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'tables_detail' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after constraints view:

```sql
-- metagration.tables_detail
-- Table-specific attributes
CREATE VIEW metagration.tables_detail
    SECURITY INVOKER
    AS
SELECT
    r.schema_name,
    r.relation_name AS table_name,
    CASE c.relpersistence
        WHEN 'p' THEN 'permanent'
        WHEN 't' THEN 'temporary'
        WHEN 'u' THEN 'unlogged'
    END AS persistence,
    (c.relkind = 'p' OR c.relispartition) AS is_partitioned,
    pg_catalog.pg_get_partkeydef(c.oid) AS partition_key
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
WHERE r.relation_type IN ('table', 'partition');
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 134 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.tables_detail introspection view"
```

---

## Task 5: Add metagration.views_detail View

**Files:**
- Modify: `sql/metagration.sql` (add view after tables_detail)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.views_detail view

-- Test 20: views_detail view exists
SELECT has_view('metagration', 'views_detail', 'views_detail view should exist');

-- Test 21: Create test view and verify it appears
SELECT lives_ok($$
    CREATE VIEW public.test_introspection_view AS SELECT 1 AS id;
$$, 'create test view');

-- Test 22: views_detail shows test view
SELECT ok(
    (SELECT COUNT(*) FROM metagration.views_detail WHERE schema_name = 'public' AND view_name = 'test_introspection_view') = 1,
    'views_detail should show test view'
);

-- Cleanup
DROP VIEW public.test_introspection_view;
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(137);  -- Was 134, adding 3 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'views_detail' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after tables_detail view:

```sql
-- metagration.views_detail
-- View-specific attributes
CREATE VIEW metagration.views_detail
    SECURITY INVOKER
    AS
SELECT
    r.schema_name,
    r.relation_name AS view_name,
    v.definition,
    (v.is_updatable = 'YES') AS is_updatable,
    v.check_option
FROM metagration.relations r
JOIN information_schema.views v
    ON v.table_schema = r.schema_name
    AND v.table_name = r.relation_name
WHERE r.relation_type = 'view';
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 137 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.views_detail introspection view"
```

---

## Task 6: Add metagration.materialized_views_detail View

**Files:**
- Modify: `sql/metagration.sql` (add view after views_detail)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.materialized_views_detail view

-- Test 23: materialized_views_detail view exists
SELECT has_view('metagration', 'materialized_views_detail', 'materialized_views_detail view should exist');

-- Test 24: Create test matview and verify it appears
SELECT lives_ok($$
    CREATE MATERIALIZED VIEW public.test_introspection_matview AS SELECT 1 AS id;
$$, 'create test matview');

-- Test 25: materialized_views_detail shows test matview
SELECT ok(
    (SELECT COUNT(*) FROM metagration.materialized_views_detail
     WHERE schema_name = 'public' AND matview_name = 'test_introspection_matview') = 1,
    'materialized_views_detail should show test matview'
);

-- Test 26: has_data is true after creation
SELECT is(
    (SELECT has_data FROM metagration.materialized_views_detail
     WHERE schema_name = 'public' AND matview_name = 'test_introspection_matview'),
    true,
    'test matview should have data'
);

-- Cleanup
DROP MATERIALIZED VIEW public.test_introspection_matview;
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(141);  -- Was 137, adding 4 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'materialized_views_detail' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after views_detail view:

```sql
-- metagration.materialized_views_detail
-- Materialized view attributes
CREATE VIEW metagration.materialized_views_detail
    SECURITY INVOKER
    AS
SELECT
    r.schema_name,
    r.relation_name AS matview_name,
    mv.definition,
    mv.ispopulated AS has_data,
    s.last_vacuum AS last_refresh
FROM metagration.relations r
JOIN pg_catalog.pg_matviews mv
    ON mv.schemaname = r.schema_name
    AND mv.matviewname = r.relation_name
LEFT JOIN pg_catalog.pg_stat_all_tables s
    ON s.schemaname = r.schema_name
    AND s.relname = r.relation_name
WHERE r.relation_type = 'matview';
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 141 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.materialized_views_detail introspection view"
```

---

## Task 7: Add metagration.foreign_tables_detail View

**Files:**
- Modify: `sql/metagration.sql` (add view after materialized_views_detail)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.foreign_tables_detail view

-- Test 27: foreign_tables_detail view exists
SELECT has_view('metagration', 'foreign_tables_detail', 'foreign_tables_detail view should exist');

-- Note: Foreign tables require foreign data wrapper setup which is complex for tests
-- Test that view exists and is queryable (will return 0 rows in test environment)
-- Test 28: foreign_tables_detail is queryable
SELECT lives_ok($$
    SELECT * FROM metagration.foreign_tables_detail LIMIT 1;
$$, 'foreign_tables_detail should be queryable');
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(143);  -- Was 141, adding 2 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'foreign_tables_detail' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after materialized_views_detail view:

```sql
-- metagration.foreign_tables_detail
-- Foreign table attributes
CREATE VIEW metagration.foreign_tables_detail
    SECURITY INVOKER
    AS
SELECT
    r.schema_name,
    r.relation_name AS table_name,
    fs.srvname AS server_name,
    fdw.fdwname AS server_type,
    fs.srvversion AS server_version,
    ARRAY(
        SELECT pg_catalog.quote_ident(option_name) || '=' || pg_catalog.quote_literal(option_value)
        FROM pg_catalog.pg_options_to_table(ft.ftoptions)
    ) AS foreign_table_options
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
JOIN pg_catalog.pg_foreign_table ft ON ft.ftrelid = c.oid
JOIN pg_catalog.pg_foreign_server fs ON fs.oid = ft.ftserver
JOIN pg_catalog.pg_foreign_data_wrapper fdw ON fdw.oid = fs.srvfdw
WHERE r.relation_type = 'foreign_table';
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 143 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.foreign_tables_detail introspection view"
```

---

## Task 8: Add metagration.partitions_detail View

**Files:**
- Modify: `sql/metagration.sql` (add view after foreign_tables_detail)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.partitions_detail view

-- Test 29: partitions_detail view exists
SELECT has_view('metagration', 'partitions_detail', 'partitions_detail view should exist');

-- Test 30: Create partitioned table and verify
SELECT lives_ok($$
    CREATE TABLE public.test_parent_table (
        id bigint,
        created_at date
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE public.test_child_partition PARTITION OF public.test_parent_table
        FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
$$, 'create partitioned table with child');

-- Test 31: partitions_detail shows child partition
SELECT ok(
    (SELECT COUNT(*) FROM metagration.partitions_detail
     WHERE schema_name = 'public' AND partition_name = 'test_child_partition') = 1,
    'partitions_detail should show child partition'
);

-- Test 32: parent table info is correct
SELECT is(
    (SELECT parent_table_name FROM metagration.partitions_detail
     WHERE schema_name = 'public' AND partition_name = 'test_child_partition'),
    'test_parent_table',
    'child partition should reference parent table'
);

-- Cleanup
DROP TABLE public.test_parent_table CASCADE;
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(147);  -- Was 143, adding 4 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'partitions_detail' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after foreign_tables_detail view:

```sql
-- metagration.partitions_detail
-- Partition relationship information
CREATE VIEW metagration.partitions_detail
    SECURITY INVOKER
    AS
SELECT
    r.schema_name,
    r.relation_name AS partition_name,
    pn.nspname AS parent_schema_name,
    pc.relname AS parent_table_name,
    pg_catalog.pg_get_expr(c.relpartbound, c.oid) AS partition_expression,
    c.relispartition AS is_default
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
LEFT JOIN pg_catalog.pg_inherits i ON i.inhrelid = c.oid
LEFT JOIN pg_catalog.pg_class pc ON pc.oid = i.inhparent
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
WHERE r.relation_type = 'partition';
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 147 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.partitions_detail introspection view"
```

---

## Task 9: Add metagration.column_statistics View

**Files:**
- Modify: `sql/metagration.sql` (add view after partitions_detail)
- Modify: `test/introspection.sql` (add tests)
- Modify: `test/test.sql` (update plan count)

**Step 1: Write the failing test**

Add to `test/introspection.sql`:

```sql
-- Test metagration.column_statistics view

-- Test 33: column_statistics view exists
SELECT has_view('metagration', 'column_statistics', 'column_statistics view should exist');

-- Test 34: column_statistics is queryable
SELECT lives_ok($$
    SELECT * FROM metagration.column_statistics LIMIT 10;
$$, 'column_statistics should be queryable');

-- Test 35: column_statistics shows data for analyzed tables
-- First ensure metagration.script is analyzed
ANALYZE metagration.script;

SELECT ok(
    (SELECT COUNT(*) FROM metagration.column_statistics
     WHERE schema_name = 'metagration' AND table_name = 'script') >= 1,
    'column_statistics should show stats for metagration.script after ANALYZE'
);
```

**Step 2: Update test.sql plan count**

Modify `test/test.sql`:

```sql
SELECT plan(150);  -- Was 147, adding 3 new tests
```

**Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL with "view 'column_statistics' does not exist"

**Step 4: Write minimal implementation**

Add to `sql/metagration.sql` after partitions_detail view:

```sql
-- metagration.column_statistics
-- Statistical distribution data
CREATE VIEW metagration.column_statistics
    SECURITY INVOKER
    AS
SELECT
    s.schemaname AS schema_name,
    s.tablename AS table_name,
    s.attname AS column_name,
    s.null_frac AS null_fraction,
    s.avg_width,
    s.n_distinct,
    s.correlation,
    s.most_common_vals::text[] AS most_common_vals,
    s.most_common_freqs
FROM pg_catalog.pg_stats s
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = s.schemaname
    AND r.relation_name = s.tablename
);
```

**Step 5: Run test to verify it passes**

Run: `make test`
Expected: All 150 tests PASS

**Step 6: Commit**

```bash
git add sql/metagration.sql test/introspection.sql test/test.sql
git commit -m "feat: add metagration.column_statistics introspection view"
```

---

## Task 10: Create Migration Script

**Files:**
- Modify: `sql/metagration.sql` (add script creation at end)

**Step 1: Add migration script to create all views**

Add at the very end of `sql/metagration.sql`:

```sql
-- Create migration script for introspection views
-- This allows views to be versioned and rolled back if needed
DO $$
BEGIN
    -- Only create if we're in a database where metagration extension is loaded
    -- (not during TLE installation)
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'metagration' AND c.relname = 'script'
    ) THEN
        -- Check if this script already exists
        IF NOT EXISTS (
            SELECT 1 FROM metagration.script WHERE comment = 'Add database introspection views'
        ) THEN
            PERFORM metagration.new_script(
                $up$
                    -- Views are already created above, this is a no-op placeholder
                    -- In production, views would be created here
                    SELECT true;
                $up$,
                $down$
                    -- Drop all introspection views in reverse order
                    DROP VIEW IF EXISTS metagration.column_statistics;
                    DROP VIEW IF EXISTS metagration.partitions_detail;
                    DROP VIEW IF EXISTS metagration.foreign_tables_detail;
                    DROP VIEW IF EXISTS metagration.materialized_views_detail;
                    DROP VIEW IF EXISTS metagration.views_detail;
                    DROP VIEW IF EXISTS metagration.tables_detail;
                    DROP VIEW IF EXISTS metagration.constraints;
                    DROP VIEW IF EXISTS metagration.columns;
                    DROP VIEW IF EXISTS metagration.relations;
                $down$,
                comment := 'Add database introspection views'
            );
        END IF;
    END IF;
END $$;
```

**Step 2: Verify views survive rebuild**

Run: `make test`
Expected: All 150 tests PASS

**Step 3: Commit**

```bash
git add sql/metagration.sql
git commit -m "feat: add migration script for introspection views"
```

---

## Task 11: Update Documentation

**Files:**
- Modify: `README.md` (add section on introspection views)
- Modify: `CLAUDE.md` (document view structure for future development)

**Step 1: Add README section**

Add to `README.md` after the Security section:

```markdown
## Database Introspection

Metagration includes comprehensive introspection views for discovering and analyzing database structure from webapps or admin tools.

### Available Views

**Base View:**
- `metagration.relations` - All table-like objects (tables, views, matviews, foreign tables, partitions)

**Detail Views:**
- `metagration.tables_detail` - Table-specific attributes
- `metagration.views_detail` - View definitions and updatability
- `metagration.materialized_views_detail` - Matview status and refresh info
- `metagration.foreign_tables_detail` - Foreign data wrapper configuration
- `metagration.partitions_detail` - Partition hierarchy

**Supporting Views:**
- `metagration.columns` - Column metadata with types and defaults
- `metagration.constraints` - Primary keys, foreign keys, unique, check constraints
- `metagration.column_statistics` - Statistical distribution data

### Security

All introspection views respect PostgreSQL permissions using `has_table_privilege()`. Users only see objects they have SELECT access to.

### Example Usage

```sql
-- List all tables in public schema
SELECT relation_name, row_estimate, total_bytes
FROM metagration.relations
WHERE schema_name = 'public' AND relation_type = 'table';

-- Get all columns for a specific table
SELECT column_name, data_type, is_nullable, column_default
FROM metagration.columns
WHERE schema_name = 'public' AND table_name = 'users'
ORDER BY ordinal_position;

-- Find all foreign key relationships
SELECT table_name, constraint_name,
       foreign_schema_name, foreign_table_name,
       update_rule, delete_rule
FROM metagration.constraints
WHERE schema_name = 'public' AND constraint_type = 'FOREIGN KEY';
```
```

**Step 2: Add CLAUDE.md section**

Add to `CLAUDE.md`:

```markdown
## Database Introspection Views

Metagration includes a hierarchical set of introspection views in the `metagration` schema.

### Architecture

**Hierarchical design:**
- Base `relations` view: common attributes for all table-like objects
- Detail views: type-specific attributes (tables_detail, views_detail, etc.)
- Supporting views: columns, constraints, statistics

**Security model:**
- All views use `SECURITY INVOKER`
- Permission filtering via `has_table_privilege()`
- Only shows objects user can SELECT

**Data sources:**
- Primary: pg_catalog (pg_class, pg_attribute, pg_constraint, etc.)
- Secondary: information_schema (for standardized column metadata)
- Statistics: pg_stats (automatically permission-filtered)

### View Dependencies

```
relations (base)
├── tables_detail
├── views_detail
├── materialized_views_detail
├── foreign_tables_detail
├── partitions_detail
├── columns (also uses information_schema.columns)
└── constraints (also uses information_schema.table_constraints)

column_statistics (independent, uses pg_stats)
```

### Adding New Introspection Features

When adding new introspection views:

1. Follow TDD: write test first in `test/introspection.sql`
2. Add view to `sql/metagration.sql` with `SECURITY INVOKER`
3. Use fully-qualified names (pg_catalog.pg_class)
4. Filter by `has_table_privilege()` or join to existing filtered view
5. Update test plan count in `test/test.sql`
6. Run `make test` to verify
```

**Step 3: Commit documentation**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add database introspection views documentation"
```

---

## Verification

After completing all tasks:

**Step 1: Run full test suite**

```bash
make test
```

Expected: All 150 tests PASS

**Step 2: Verify all views exist**

```bash
cd .worktrees/introspection-views
make tle
psql -f install-tle.sql
psql -c "CREATE EXTENSION metagration;"
psql -c "\dv metagration.*"
```

Expected: List showing all 9 introspection views

**Step 3: Test view queries manually**

```bash
psql -c "SELECT COUNT(*) FROM metagration.relations;"
psql -c "SELECT COUNT(*) FROM metagration.columns;"
psql -c "SELECT COUNT(*) FROM metagration.constraints;"
```

Expected: Non-zero counts for each view

**Step 4: Verify git history**

```bash
git log --oneline
```

Expected: 11 commits following TDD pattern

---

## Rollback Plan

If issues arise, views can be dropped individually or via the down migration:

```sql
-- Individual view removal
DROP VIEW metagration.column_statistics;
DROP VIEW metagration.partitions_detail;
-- ... etc in reverse dependency order

-- Or use the migration system
CALL metagration.run('<previous_revision>');
```
