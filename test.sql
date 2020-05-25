\pset format unaligned
\pset tuples_only true
\pset pager

-- \set ECHO none
-- \set ON_ERROR_ROLLBACK 1
-- \set ON_ERROR_STOP true
-- \set QUIET 1

CREATE EXTENSION pgtap;
CREATE EXTENSION plpython3u;

SET search_path = public, pgtap, metagration;

SELECT plan(95);

SELECT lives_ok($$
SELECT new_script(
'CREATE TABLE foo (bar int)',
'DROP TABLE foo');
$$, 'CREATE foo script');

CALL run();

SELECT current_revision() AS checkpoint \gset
SELECT is(:checkpoint, 1, 'checkpoint is first');

SELECT has_table('foo'::name, 'floo exists');

SELECT lives_ok($$
SELECT new_script(
'CREATE TABLE lii (bar int)',
'DROP TABLE lii');
$$, 'CREATE lii script');

SELECT lives_ok($$
SELECT new_script(
'CREATE TABLE loo (bar int)',
'DROP TABLE loo');
$$, 'CREATE loo script');

CALL run();

-- SELECT * from log order by migration_start;

SELECT is(previous_revision(), 2::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 3::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

SELECT lives_ok($$
SELECT new_script(
'CREATE TABLE zink (bar int)',
'DROP TABLE zink cascade');
$$, 'CREATE zink script');

CALL run();
-- SELECT * from log order by migration_start;

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

CALL run(:checkpoint);

SELECT is(previous_revision(), 0::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 1::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 2::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');

CALL run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');

CALL run(0);

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

CALL run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

-- SELECT * from log order by migration_start order by migration_start;

\o _tmp_test_migration_export.sql
SELECT export();
\o
\i _tmp_test_migration_export.sql
\! rm _tmp_test_migration_export.sql

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

CALL run(0);

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

\o _tmp_test_migration_export_txn.sql
SELECT export(transactional:=true);
\o
\i _tmp_test_migration_export_txn.sql
\! rm _tmp_test_migration_export_txn.sql

CALL run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

CALL run(0);

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

\o _tmp_test_migration_export_replace.sql
SELECT export(replace_scripts:=true);
\o
\i _tmp_test_migration_export_replace.sql
\! rm _tmp_test_migration_export_replace.sql

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

CALL run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

CALL run(0);

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

\o _tmp_test_migration_export_run.sql
SELECT export(run_migrations:=true);
\o
\i _tmp_test_migration_export_run.sql
\! rm _tmp_test_migration_export_run.sql

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

SELECT lives_ok($$
SELECT new_script(
$up$
    FOR i IN (SELECT * FROM generate_series(1, (args->>'target')::bigint, 1)) LOOP
        EXECUTE format('CREATE TABLE %I (id serial)', 'forks_' || i);
    END LOOP
$up$,
$down$
    FOR i IN (SELECT * FROM generate_series(1, (args->>'target')::bigint, 1)) LOOP
        EXECUTE format('DROP TABLE %I', 'forks_' || i);
    END LOOP
$down$,
    up_declare:='i bigint',
    down_declare:='i bigint',
    args:=jsonb_build_object('target', 3)
    );
$$, 'CREATE forks script');

CALL run();

SELECT has_table('forks_1'::name, 'forks_1 exists');
SELECT has_table('forks_2'::name, 'forks_2 exists');
SELECT has_table('forks_3'::name, 'forks_3 exists');

CALL run('-1');

SELECT hasnt_table('forks_1'::name, 'no forks_1');
SELECT hasnt_table('forks_2'::name, 'no forks_2');
SELECT hasnt_table('forks_3'::name, 'no forks_3');

CALL run('+1', args:=jsonb_build_object('target', 2));

SELECT has_table('forks_1'::name, 'forks_1 exists');
SELECT has_table('forks_2'::name, 'forks_2 exists');
SELECT hasnt_table('forks_3'::name, 'no forks_3');

CALL run('-1', args:=jsonb_build_object('target', 2));

SELECT hasnt_table('forks_1'::name, 'no forks_1');
SELECT hasnt_table('forks_2'::name, 'no forks_2');
SELECT hasnt_table('forks_3'::name, 'no forks_3');

SELECT * from log order by migration_start;

SELECT * FROM finish();
