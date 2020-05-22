-- \set ECHO none
-- \set QUIET 1
-- \!
-- \pset format unaligned
-- \pset tuples_only true
-- \pset pager

-- \set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
-- \set QUIET 1

CREATE EXTENSION pgtap;

--BEGIN;
SELECT plan(66);

select metagration.create(
'create table foo (bar int)',
'drop table foo');

call metagration.run();

SELECT metagration.current_revision() AS checkpoint \gset
select is(:checkpoint, 1);

SELECT has_table('foo'::name);

select metagration.create(
'create table lii (bar int)',
'drop table lii');

select metagration.create(
'create table loo (bar int)',
'drop table loo');

call metagration.run();

-- select * from metagration.log order by migration_start;

select is(metagration.previous_revision(), 2::bigint);
select is(metagration.current_revision(), 3::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

select metagration.create(
'create table zink (bar int)',
'drop table zink cascade');

call metagration.run();
-- select * from metagration.log order by migration_start;

select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

call metagration.run(:checkpoint);

select is(metagration.previous_revision(), 0::bigint);
select is(metagration.current_revision(), 1::bigint);
select is(metagration.next_revision(), 2::bigint);

SELECT hasnt_table('zink'::name);

call metagration.run();


select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('zink'::name);

call metagration.run(0);

select is(metagration.previous_revision(), null);
select is(metagration.current_revision(), 0::bigint);
select is(metagration.next_revision(), 1::bigint);

SELECT hasnt_table('zink'::name);
SELECT hasnt_table('lii'::name);
SELECT hasnt_table('loo'::name);

call metagration.run();

select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('zink'::name);
SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

-- select * from metagration.log order by migration_start order by migration_start;

\t
\a
\o _tmp_test_migration_export.sql
select metagration.export();
\o
\i _tmp_test_migration_export.sql

select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('zink'::name);
SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

call metagration.run(0);

select is(metagration.previous_revision(), null);
select is(metagration.current_revision(), 0::bigint);
select is(metagration.next_revision(), 1::bigint);

SELECT hasnt_table('zink'::name);
SELECT hasnt_table('lii'::name);
SELECT hasnt_table('loo'::name);

\o _tmp_test_migration_export_txn.sql
select metagration.export(transactional:=true);
\o
\i _tmp_test_migration_export_txn.sql

call metagration.run();

select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('zink'::name);
SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

call metagration.run(0);

select is(metagration.previous_revision(), null);
select is(metagration.current_revision(), 0::bigint);
select is(metagration.next_revision(), 1::bigint);

SELECT hasnt_table('zink'::name);
SELECT hasnt_table('lii'::name);
SELECT hasnt_table('loo'::name);

\o _tmp_test_migration_export_replace.sql
select metagration.export(replace_scripts:=true);
\o
\i _tmp_test_migration_export_replace.sql

\t
\a

select is(metagration.previous_revision(), null);
select is(metagration.current_revision(), 0::bigint);
select is(metagration.next_revision(), 1::bigint);

SELECT hasnt_table('zink'::name);
SELECT hasnt_table('lii'::name);
SELECT hasnt_table('loo'::name);

call metagration.run();

select is(metagration.previous_revision(), 3::bigint);
select is(metagration.current_revision(), 4::bigint);
select is(metagration.next_revision(), null);

SELECT has_table('zink'::name);
SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

-- select * from metagration.log order by migration_start;

SELECT * FROM finish();

-- \!rm _tmp_test_migration_export_replace.sql _tmp_test_migration_export.sql
