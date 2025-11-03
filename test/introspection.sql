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

-- Test metagration.foreign_tables_detail view

-- Test 27: foreign_tables_detail view exists
SELECT has_view('metagration', 'foreign_tables_detail', 'foreign_tables_detail view should exist');

-- Note: Foreign tables require foreign data wrapper setup which is complex for tests
-- Test that view exists and is queryable (will return 0 rows in test environment)
-- Test 28: foreign_tables_detail is queryable
SELECT lives_ok($$
    SELECT * FROM metagration.foreign_tables_detail LIMIT 1;
$$, 'foreign_tables_detail should be queryable');

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
