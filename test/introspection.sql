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
