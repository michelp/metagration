DROP SCHEMA IF EXISTS metagration CASCADE;
CREATE SCHEMA metagration;

CREATE SCHEMA IF NOT EXISTS metagration_scripts;

CREATE TABLE metagration.script (
    revision      bigserial PRIMARY KEY,
    is_current    boolean DEFAULT false,
    script_schema text NOT null DEFAULT 'metagration_scripts',
    up_script     text,
    up_args       jsonb,
    down_script   text,
    down_args     jsonb,
    comment       text
);

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

INSERT INTO metagration.script (revision, is_current) VALUES (0, true);

CREATE TABLE metagration.log (
    revision_start    bigint REFERENCES metagration.script (revision),
    revision_end      bigint REFERENCES metagration.script (revision),
    migration_start   timestamptz not null,
    migration_end     timestamptz,
    txid              bigint,
    restore_point     text,
    restore_point_lsn pg_lsn,
    PRIMARY KEY       (revision_start, revision_end, migration_start)
);

CREATE OR REPLACE FUNCTION metagration.current_revision()
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script WHERE is_current;
$$;

CREATE OR REPLACE FUNCTION metagration.previous_revision(from_revision bigint=null)
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script
        WHERE revision < coalesce(from_revision, metagration.current_revision())
        ORDER BY revision DESC
        LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION metagration.next_revision(from_revision bigint=null)
    RETURNS bigint LANGUAGE sql AS $$
    SELECT revision FROM metagration.script
        WHERE revision > coalesce(from_revision, metagration.current_revision())
        ORDER BY revision ASC
        LIMIT 1;
$$;

CREATE OR REPLACE PROCEDURE metagration.run_up(
    revision_start bigint,
    revision_end   bigint)
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
        USING current_script.up_args;

        UPDATE metagration.script
            SET is_current = false WHERE is_current;
        UPDATE metagration.script
            SET is_current = true
            WHERE revision = current_script.revision;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE metagration.run_down(
    revision_start bigint,
    revision_end   bigint)
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
            USING current_script.down_args;
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

CREATE OR REPLACE PROCEDURE metagration.run(run_to bigint=null)
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
        CALL metagration.run_down(current_revision, 0);
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
       CALL metagration.run_up(revision_start, revision_end);
    ELSE
       CALL metagration.run_down(revision_start, revision_end);
    END IF;
    INSERT INTO metagration.log (
       revision_start,
       revision_end,
       migration_start,
       migration_end,
       txid,
       restore_point,
       restore_point_lsn)
   VALUES (
       revision_start,
       revision_end,
       clock_now,
       clock_timestamp(),
       txid_current(),
       restore_point,
       restore_point_lsn);
END;
$$;

CREATE OR REPLACE PROCEDURE metagration.run(run_to text)
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
     CALL metagration.run(revision_end);
END;
$$;

CREATE OR REPLACE FUNCTION metagration._proc_body(script text)
    RETURNS text LANGUAGE plpgsql AS $$
BEGIN
RETURN format(
$f$BEGIN
    %s;
    RETURN;
END;$f$, script);
END;$$;

CREATE OR REPLACE FUNCTION metagration._build_proc(
    use_schema  text,
    script_name text,
    body        text)
    RETURNS text LANGUAGE plpgsql AS $$
BEGIN
RETURN format(
$f$
CREATE OR REPLACE PROCEDURE %I.%I
    (args jsonb default '{}') LANGUAGE plpgsql AS $%s$
%s
$%s$;
$f$, use_schema, script_name, script_name, body, script_name);
END;
$$;

CREATE OR REPLACE FUNCTION metagration.create(
    up_script   text,
    down_script text=null,
    use_schema  text='metagration_scripts',
    comment     text=null)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    this      metagration.script;
    up_name   text;
    down_name text = null;
BEGIN
    INSERT INTO metagration.script (script_schema, comment)
        VALUES (use_schema, comment) returning * INTO this;
    up_name = '_' || this.revision || '_' || 'up';
    if down_script IS NOT null THEN
        down_name = '_' || this.revision || '_' || 'down';
        EXECUTE metagration._build_proc(
            use_schema, down_name,
            metagration._proc_body(down_script));
    END IF;
    EXECUTE metagration._build_proc(
       use_schema, up_name,
       metagration._proc_body(up_script));
    UPDATE metagration.script
    SET up_script = up_name,
        down_script = down_name,
        script_schema = use_schema
    WHERE revision = this.revision;
    RETURN this.revision;
END;
$$;

CREATE OR REPLACE FUNCTION metagration._get_source(
    proc_schema text, proc_name text)
RETURNS text LANGUAGE sql AS $$
    SELECT prosrc
        FROM pg_proc p, pg_namespace n
        WHERE p.pronamespace = n.oid
        AND p.proname=proc_name
        AND n.nspname=proc_schema;
$$;

CREATE OR REPLACE FUNCTION metagration.export(
    replace_scripts boolean=false,
    transactional boolean=false)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    current_script metagration.script;
    buffer         text='';
    proc_source    text;
BEGIN
    IF transactional THEN
        buffer = buffer || 'BEGIN;';
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
        proc_source = metagration._get_source(
            current_script.script_schema,
            current_script.up_script);
        buffer = buffer || metagration._build_proc(
            current_script.script_schema,
            current_script.up_script,
            proc_source);
        IF current_script.down_script IS NOT null THEN
            proc_source = metagration._get_source(
                current_script.script_schema,
                current_script.down_script);
            buffer = buffer || metagration._build_proc(
                current_script.script_schema,
                current_script.down_script,
                proc_source);
        END IF;
        IF replace_scripts THEN
            buffer = buffer || format(
$f$
INSERT INTO metagration.script
    (revision, script_schema, up_script, up_args, down_script, down_args, comment)
    VALUES (%L, %L, %L, %L, %L, %L, %L);
$f$,
current_script.revision,
current_script.script_schema,
current_script.up_script,
current_script.up_args,
current_script.down_script,
current_script.down_args,
current_script.comment);
        END IF;
    END LOOP;
    IF transactional THEN
        buffer = buffer || 'COMMIT;';
    END IF;
    RETURN buffer;
END;
$$;
