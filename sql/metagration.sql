DROP SCHEMA IF EXISTS metagration CASCADE;
CREATE SCHEMA metagration;
CREATE SCHEMA IF NOT EXISTS metagration_scripts;

CREATE TABLE metagration.script (
    revision      bigserial PRIMARY KEY,
    is_current    boolean DEFAULT false,
    script_schema text NOT null DEFAULT 'metagration_scripts',
    up_script     text,
    down_script   text,
    test_script   text,
    args          jsonb,
    comment       text
);

COMMENT ON TABLE metagration.script IS
    'Table for metagration scripts.';

CREATE UNIQUE INDEX ON metagration.script (is_current)
    WHERE is_current = true;

CREATE OR REPLACE FUNCTION metagration.check_script_trigger()
    RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    max_revision bigint;
BEGIN
    SELECT max(revision) INTO max_revision FROM metagration.script;
    IF new.revision <= max_revision THEN
        RAISE 'Cannot insert script with revision <= %', max_revision;
    END IF;
    RETURN new;
END;
$$;

CREATE TRIGGER before_insert_script_trigger
    BEFORE INSERT ON metagration.script
    FOR EACH ROW EXECUTE PROCEDURE metagration.check_script_trigger();

-- 0 is the "base" revision, which means no scripts applied.
INSERT INTO metagration.script (revision, is_current) VALUES (0, true);

CREATE TABLE metagration.log (
    revision_start    bigint REFERENCES metagration.script (revision),
    revision_end      bigint REFERENCES metagration.script (revision),
    migration_start   timestamptz not null,
    migration_end     timestamptz,
    migration_args    jsonb,
    txid              bigint,
    restore_point     text,
    restore_point_lsn pg_lsn,
    PRIMARY KEY       (revision_start, revision_end, migration_start)
);

COMMENT ON TABLE metagration.script IS
'Log of metagrations that have been applied, when and their restore points.';

CREATE OR REPLACE FUNCTION metagration.current_revision()
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script WHERE is_current;
$$;

COMMENT ON FUNCTION metagration.current_revision() IS
'Returns the current revision or null if no revisions applied.';

CREATE OR REPLACE FUNCTION metagration.previous_revision(from_revision bigint=null)
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script
        WHERE revision < coalesce(from_revision, metagration.current_revision())
        ORDER BY revision DESC
        LIMIT 1;
$$;

COMMENT ON FUNCTION metagration.previous_revision(bigint) IS
'Returns the previons revision or null if no previous revision to the
one supplied.  If no revision is supplied, default to the current
revision';

CREATE OR REPLACE FUNCTION metagration.next_revision(from_revision bigint=null)
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script
        WHERE revision > coalesce(from_revision, metagration.current_revision())
        ORDER BY revision ASC
        LIMIT 1;
$$;

COMMENT ON FUNCTION metagration.next_revision(bigint) IS
'Returns the next revision or null if no next revision to the
one supplied.  If no revision is supplied, default to the current
revision';

CREATE OR REPLACE PROCEDURE metagration.run_up(
    revision_start bigint,
    revision_end   bigint,
    args           jsonb='{}',
    verify         boolean=true)
    LANGUAGE plpgsql AS $$
DECLARE
    current_script metagration.script;
BEGIN
    FOR current_script IN
        SELECT * FROM metagration.script
        WHERE revision > revision_start
        AND revision <= revision_end
        ORDER BY revision ASC
    LOOP
        EXECUTE format(
            'CALL %I.%I($1)',
            current_script.script_schema,
            current_script.up_script)
        USING current_script.args || args;

        IF verify AND current_script.test_script IS NOT null THEN
            COMMIT;
            EXECUTE format(
                'CALL %I.%I($1)',
                current_script.script_schema,
                current_script.test_script)
            USING current_script.args || args;
            ROLLBACK;
        END IF;
        UPDATE metagration.script
            SET is_current = false WHERE is_current;
        UPDATE metagration.script
            SET is_current = true
            WHERE revision = current_script.revision;
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE metagration.run_up(bigint, bigint, jsonb, boolean) IS
'Apply up scripts from start to end revisions.';

CREATE OR REPLACE PROCEDURE metagration.run_down(
    revision_start bigint,
    revision_end   bigint,
    args           jsonb='{}')
    LANGUAGE plpgsql AS $$
DECLARE
    current_script metagration.script;
BEGIN
    FOR current_script IN
        SELECT * FROM metagration.script
        WHERE revision <= revision_start
        AND revision > revision_end
        ORDER BY revision DESC
    LOOP
        IF current_script.down_script IS null THEN
            RAISE 'No down script for revision %', current_script.revision;
        END IF;
        EXECUTE format('CALL %I.%I($1)',
            current_script.script_schema,
            current_script.down_script)
            USING current_script.args || args;
        UPDATE metagration.script
           SET is_current = false
           WHERE is_current;
        UPDATE metagration.script
           SET is_current = true
           WHERE
             revision = metagration.previous_revision(current_script.revision);
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE metagration.run_down(bigint, bigint, jsonb) IS
'Apply down scripts from start to end revisions.';

CREATE OR REPLACE PROCEDURE metagration.run(run_to bigint=null, args jsonb='{}', verify boolean=true)
    LANGUAGE plpgsql AS $$
DECLARE
    current_revision  bigint;
    revision_start    bigint;
    revision_end      bigint;
    clock_now         timestamptz;
    restore_point     text;
    restore_point_lsn pg_lsn;
BEGIN
    LOCK TABLE metagration.script IN SHARE MODE;
    current_revision = metagration.current_revision();
    IF run_to = 0 THEN
        IF current_revision is null THEN
            RAISE 'No starting revision available.';
        END IF;
        CALL metagration.run_down(current_revision, 0, args);
        RETURN;
    END IF;
    IF run_to IS null THEN
       SELECT max(revision) INTO run_to FROM metagration.script;
    END IF;
    SELECT revision INTO revision_end
        FROM metagration.script
        WHERE revision = run_to;
    IF revision_end IS null THEN
       RAISE 'no revision %', run_to;
    END IF;
    SELECT revision INTO revision_start
        FROM metagration.script
        WHERE is_current;
    IF revision_start IS null THEN
       revision_start = 0;
    END IF;
    IF revision_start = revision_end THEN
       RAISE '% is already the current revision', run_to;
    END IF;
    SELECT clock_timestamp() INTO clock_now;
    restore_point = format('%s|%s|%s',
        revision_start,
        revision_end,
        replace(clock_now::text, ' ', '|'));
    SELECT pg_create_restore_point(restore_point) INTO restore_point_lsn;
    IF revision_start < revision_end THEN
       CALL metagration.run_up(revision_start, revision_end, args, verify=verify);
    ELSE
       CALL metagration.run_down(revision_start, revision_end, args);
    END IF;
    INSERT INTO metagration.log (
       revision_start,
       revision_end,
       migration_start,
       migration_end,
       migration_args,
       txid,
       restore_point,
       restore_point_lsn)
   VALUES (
       revision_start,
       revision_end,
       clock_now,
       clock_timestamp(),
       args,
       txid_current(),
       restore_point,
       restore_point_lsn);
END;
$$;

COMMENT ON PROCEDURE metagration.run(bigint, jsonb, boolean) IS
'Run from thecurrent revision, forwards or backwards to the target
revision.';

CREATE OR REPLACE PROCEDURE metagration.run(run_to text, args jsonb='{}', verify boolean=true)
    LANGUAGE plpgsql AS $$
DECLARE
    revision_start bigint;
    revision_end bigint;
    delta bigint = run_to::bigint;
BEGIN
    revision_start = metagration.current_revision();
    EXECUTE format($f$
    SELECT revision
       FROM metagration.script
       WHERE
          CASE WHEN $1 < 0 THEN
              revision < $2
          ELSE
              revision > $2
          END
       ORDER BY revision %s LIMIT 1 OFFSET %s
       $f$,
       CASE WHEN delta < 0 THEN 'desc' ELSE 'asc' END,
       abs(delta)-1)
     INTO revision_end
     USING delta, revision_start;
     IF revision_end IS null THEN
         RAISE 'No revision % away', run_to;
     END IF;
     CALL metagration.run(revision_end, args, verify=verify);
END;
$$;

COMMENT ON PROCEDURE metagration.run(text, jsonb, boolean) IS
'Run from the current revision, forwards or backwards to the target
revision using relative notation -1 to go back one, +3 to go forward
3, etc...';

CREATE OR REPLACE PROCEDURE metagration.assert(result text)
    LANGUAGE plpgsql AS $$
BEGIN
    ASSERT starts_with(result, 'ok');
    RAISE NOTICE '%', result;
END;
$$;

CREATE OR REPLACE PROCEDURE metagration.verify()
    LANGUAGE plpgsql AS $$
DECLARE
    current_script metagration.script;
BEGIN
    FOR current_script IN
        SELECT * FROM metagration.script
        ORDER BY revision ASC
    LOOP
        IF current_script.test_script IS NOT null THEN
            EXECUTE format(
                'CALL %I.%I($1)',
                current_script.script_schema,
                current_script.test_script)
            USING current_script.args;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE metagration.verify() IS
'Verify all revisions.';

CREATE OR REPLACE FUNCTION metagration._proc_body(script_declare text, script text)
    RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    buffer text = '';
BEGIN
    IF script_declare IS NOT null THEN
        buffer = buffer || format($f$
DECLARE
    %s;
$f$, script_declare);
    END IF;
    
    buffer = buffer || format($f$
BEGIN
    %s
    RETURN;
END;$f$, script);
    RETURN buffer;
END;$$;

CREATE OR REPLACE FUNCTION metagration._build_proc(
    use_schema      text,
    script_name     text,
    script_body     text)
    RETURNS text LANGUAGE plpgsql AS $$
BEGIN
RETURN format(
$f$
CREATE OR REPLACE PROCEDURE %I.%I
    (args jsonb='{}') LANGUAGE plpgsql AS $%s$
%s
$%s$;
$f$, use_schema, script_name, script_name, script_body, script_name);
END;
$$;

CREATE OR REPLACE FUNCTION metagration.new_script(
    up_script    text,
    down_script  text=null,
    test_script  text=null,
    up_declare   text=null,
    down_declare text=null,
    test_declare text=null,
    args         jsonb='{}',
    use_schema   text='metagration_scripts',
    comment      text=null)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    this      metagration.script;
    up_name   text;
    down_name text = null;
    test_name text = null;
BEGIN
    INSERT INTO metagration.script
        (args, script_schema, comment)
        VALUES
        (args, use_schema, comment)
    RETURNING * INTO this;
    up_name = '_' || this.revision || '_' || 'up';
    if down_script IS NOT null THEN
        down_name = '_' || this.revision || '_' || 'down';
        EXECUTE metagration._build_proc(
            use_schema,
            down_name,
            metagration._proc_body(down_declare, down_script));
    END IF;
    if test_script IS NOT null THEN
        test_name = '_' || this.revision || '_' || 'test';
        EXECUTE metagration._build_proc(
            use_schema,
            test_name,
            metagration._proc_body(test_declare, test_script));
    END IF;
    EXECUTE metagration._build_proc(
       use_schema,
       up_name,
       metagration._proc_body(up_declare, up_script));
    UPDATE metagration.script
    SET up_script = up_name,
        down_script = down_name,
        test_script = test_name
    WHERE revision = this.revision;
    RETURN this.revision;
END;
$$;

CREATE OR REPLACE FUNCTION metagration._get_sourcedef(
    proc_schema text, proc_name text)
RETURNS text LANGUAGE sql AS $$
    SELECT pg_get_functiondef(p.oid) || ';'
        FROM pg_proc p, pg_namespace n
        WHERE p.pronamespace = n.oid
        AND p.proname=proc_name
        AND n.nspname=proc_schema;
$$;

CREATE OR REPLACE FUNCTION metagration.export(
    replace_scripts boolean=false,
    transactional boolean=false,
    run_migrations boolean=false)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    current_script metagration.script;
    buffer         text='';
    proc_source    text;
    proc_language  text;
BEGIN
    IF transactional THEN
        buffer = buffer || '
BEGIN;';
    END IF;
    IF replace_scripts THEN
        buffer = buffer || format(
$f$
TRUNCATE metagration.script CASCADE;
INSERT INTO metagration.script (revision, is_current) VALUES (0, true);
$f$);
    END IF;
    FOR current_script IN
        SELECT * FROM metagration.script
        WHERE revision > 0
        ORDER BY revision
    LOOP
        buffer = buffer || metagration._get_sourcedef(
            current_script.script_schema,
            current_script.up_script);
    
        IF current_script.down_script IS NOT null THEN
            buffer = buffer || metagration._get_sourcedef(
                current_script.script_schema,
                current_script.down_script);
        END IF;
        IF replace_scripts THEN
            buffer = buffer || format(
$f$
INSERT INTO metagration.script
    (revision, script_schema, up_script, down_script, args, comment)
    VALUES (%L, %L, %L, %L, %L, %L);
$f$,
current_script.revision,
current_script.script_schema,
current_script.up_script,
current_script.down_script,
current_script.args,
current_script.comment);
        END IF;
    END LOOP;
    IF run_migrations THEN
        buffer = buffer || '
CALL metagration.run();';
    END IF;
    IF transactional THEN
        buffer = buffer || '
COMMIT;';
    END IF;
    RETURN buffer;
END;
$$;

COMMENT ON FUNCTION metagration.export(boolean, boolean, boolean) IS
'Export metagration scripts as SQL file that can be loaded into fresh
database. ';
