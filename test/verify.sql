
SELECT lives_ok($$
SELECT new_script(
    'CREATE TABLE laa (bar int);',
    down_script:='DROP TABLE laa;',
    test_script:=$test$
        CALL metagration.assert(has_table('laa'::name, 'Verify laa exists'));
        RAISE NOTICE 'hi this is the test script calling.';
    $test$
    );
$$, 'CREATE laa script with test');

-- Run script and verify

CALL metagration.run(verify:=true);

CALL metagration.verify();  -- no exception

DROP TABLE laa;  -- do something evil without a migration

select throws_ok('CALL metagration.verify()');
