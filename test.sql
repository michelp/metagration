\pset format unaligned
\pset tuples_only true
\pset pager

\set ECHO none
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
\set QUIET 1

CREATE EXTENSION pgtap;

SET search_path = pgtap, metagration, public;

SELECT plan(78);

SELECT lives_ok($$
SELECT new_script(
'create table foo (bar int)',
'drop table foo');
$$, 'create foo script');

call run();

SELECT current_revision() AS checkpoint \gset
SELECT is(:checkpoint, 1, 'checkpoint is first');

SELECT has_table('foo'::name, 'floo exists');

SELECT lives_ok($$
SELECT new_script(
'create table lii (bar int)',
'drop table lii');
$$, 'create lii script');

SELECT lives_ok($$
SELECT new_script(
'create table loo (bar int)',
'drop table loo');
$$, 'create loo script');

call run();

-- SELECT * from log order by migration_start;

SELECT is(previous_revision(), 2::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 3::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

SELECT lives_ok($$
SELECT new_script(
'create table zink (bar int)',
'drop table zink cascade');
$$, 'create zink script');

call run();
-- SELECT * from log order by migration_start;

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

call run(:checkpoint);

SELECT is(previous_revision(), 0::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 1::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 2::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');

call run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');

call run(0);

SELECT is(previous_revision(), null, 'previous revision is null');
SELECT is(current_revision(), 0::bigint, 'current revision is ' || current_revision());
SELECT is(next_revision(), 1::bigint, 'next revision is ' || next_revision());

SELECT hasnt_table('zink'::name, 'no zink');
SELECT hasnt_table('lii'::name, 'no lii');
SELECT hasnt_table('loo'::name, 'no loo');

call run();

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

call run(0);

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

call run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

call run(0);

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

call run();

SELECT is(previous_revision(), 3::bigint, 'previous revision is ' || previous_revision());
SELECT is(current_revision(), 4::bigint, 'current_revision is ' || current_revision());
SELECT is(next_revision(), null, 'next revision is null');

SELECT has_table('zink'::name, 'zink exists');
SELECT has_table('lii'::name, 'lii exists');
SELECT has_table('loo'::name, 'loo exists');

call run(0);

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

-- SELECT * from log order by migration_start;

SELECT * FROM finish();
