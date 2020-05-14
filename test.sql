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
SELECT plan(18);

select metagration.create(
'create table foo (bar int)',
'drop table foo');

call metagration.run();

SELECT metagration.current_revision() AS checkpoint \gset

SELECT has_table('foo'::name);

select metagration.create(
'create table lii (bar int)',
'drop table lii');

select metagration.create(
'create table loo (bar int)',
'drop table loo');

call metagration.run();
select * from metagration.log;

SELECT has_table('lii'::name);
SELECT has_table('loo'::name);

select metagration.create(
'create table zink (bar int)',
'drop table zink cascade');

call metagration.run();
select * from metagration.log;

call metagration.run(:checkpoint);

SELECT hasnt_table('zink'::name);

call metagration.run();

SELECT has_table('zink'::name);

call metagration.run(0);

SELECT hasnt_table('zink'::name);
SELECT hasnt_table('lii'::name);
SELECT hasnt_table('loo'::name);

SELECT * FROM finish();

select * from metagration.log order by migration_start;

select metagration.export();
COMMIT;
