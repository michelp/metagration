\pset format unaligned
\pset tuples_only true
\pset pager

-- \set ECHO none
-- \set ON_ERROR_ROLLBACK 1
-- \set ON_ERROR_STOP true
-- \set QUIET 1

CREATE EXTENSION pgtap;

SET search_path = public, pgtap, metagration;

SELECT plan(100);
\ir core.sql
\ir verify.sql
SELECT * FROM finish();
