
SELECT lives_ok($$
SELECT new_script(
    'CREATE TABLE laa (bar int);',
    down_script:='DROP TABLE laa;',
    test_script:=$test$
    RAISE NOTICE '%', metagration.assert(has_table('laa'::name, 'Verify laa exists'));
    $test$
    );
$$, 'CREATE laa script with test');

-- Run script and verify

CALL metagration.run(verify:=true);

CALL metagration.verify();  -- no exception

DROP TABLE laa;  -- do something evil without a migration

DO $$
BEGIN
    CALL metagration.verify();
EXCEPTION
    WHEN assert_failure THEN
        RAISE NOTICE 'expected failure it''s all good';
END$$;
