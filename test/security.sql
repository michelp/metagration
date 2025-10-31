-- Security feature tests

-- Test 1: script_schema validation - should reject invalid schema names
SELECT throws_ok(
    $$
    INSERT INTO metagration.script (revision, script_schema, up_script, down_script, comment)
    VALUES (999, 'invalid-schema!', 'metagration.up_999', 'metagration.down_999', 'test')
    $$,
    '23514',  -- check_violation
    NULL,
    'script_schema rejects invalid identifier with special chars'
);

-- Test 2: script_schema validation - should reject schema starting with number
SELECT throws_ok(
    $$
    INSERT INTO metagration.script (revision, script_schema, up_script, down_script, comment)
    VALUES (999, '9invalid', 'metagration.up_999', 'metagration.down_999', 'test')
    $$,
    '23514',
    NULL,
    'script_schema rejects identifier starting with number'
);

-- Test 3: script_schema validation - should accept valid schema name
SELECT lives_ok(
    $$
    INSERT INTO metagration.script (revision, script_schema, up_script, down_script, comment)
    VALUES (999, 'valid_schema', 'metagration.up_999', 'metagration.down_999', 'test');
    DELETE FROM metagration.script WHERE revision = 999;
    $$,
    'script_schema accepts valid identifier'
);

-- Test 4: setup_permissions creates role if not exists
SELECT lives_ok(
    $$
    DO $do$
    BEGIN
        -- Drop role if it exists from previous test run
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_migration_role') THEN
            REASSIGN OWNED BY test_migration_role TO postgres;
            DROP OWNED BY test_migration_role;
            DROP ROLE test_migration_role;
        END IF;
    END $do$;
    CREATE ROLE test_migration_role;
    CALL metagration.setup_permissions('test_migration_role');
    $$,
    'setup_permissions executes successfully'
);

-- Test 5: setup_permissions grants schema usage
SELECT ok(
    pg_catalog.has_schema_privilege('test_migration_role', 'metagration', 'USAGE'),
    'test_migration_role has USAGE on metagration schema'
);

-- Test 6: setup_permissions grants table select
SELECT ok(
    pg_catalog.has_table_privilege('test_migration_role', 'metagration.script', 'SELECT'),
    'test_migration_role has SELECT on script table'
);

-- Test 7: setup_permissions grants execute on functions
SELECT ok(
    pg_catalog.has_function_privilege('test_migration_role', 'metagration.current_revision()', 'EXECUTE'),
    'test_migration_role can execute current_revision()'
);

-- Test 8: setup_permissions grants execute on new_script
SELECT ok(
    pg_catalog.has_function_privilege('test_migration_role', 'metagration.new_script(text, text, text, text, text, text, jsonb, text, text)', 'EXECUTE'),
    'test_migration_role can execute new_script()'
);

-- Test 9: Verify PUBLIC does not have direct access after setup_permissions
-- Check that schema usage is restricted (public role shouldn't have explicit USAGE)
SELECT ok(
    NOT pg_catalog.has_schema_privilege('public', 'metagration', 'USAGE'),
    'public role does not have USAGE on metagration schema after setup_permissions'
);

-- Cleanup test role
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_migration_role') THEN
        REASSIGN OWNED BY test_migration_role TO postgres;
        DROP OWNED BY test_migration_role;
        DROP ROLE test_migration_role;
    END IF;
END $$;
