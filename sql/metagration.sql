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

-- Security: Validate script_schema to prevent malicious schema injection
ALTER TABLE metagration.script
ADD CONSTRAINT valid_script_schema
CHECK (script_schema ~ '^[a-z_][a-z0-9_]*$');

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
    RETURNS bigint
    LANGUAGE sql
    STABLE
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
    SELECT revision FROM metagration.script WHERE is_current;
$$;

COMMENT ON FUNCTION metagration.current_revision() IS
'Returns the current revision or null if no revisions applied.';

CREATE OR REPLACE FUNCTION metagration.previous_revision(from_revision bigint=null)
    RETURNS bigint
    LANGUAGE sql
    STABLE
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
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
    RETURNS bigint
    LANGUAGE sql
    STABLE
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
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
    LANGUAGE plpgsql
    SECURITY INVOKER
    AS $$
DECLARE
    current_script metagration.script;
BEGIN
    -- Set search_path for security (LOCAL to avoid transaction control conflicts)
    SET LOCAL search_path = metagration, pg_catalog, pg_temp;
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
    LANGUAGE plpgsql
    SECURITY INVOKER
    AS $$
DECLARE
    current_script metagration.script;
BEGIN
    -- Set search_path for security (LOCAL to avoid transaction control conflicts)
    SET LOCAL search_path = metagration, pg_catalog, pg_temp;
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
    LANGUAGE plpgsql
    SECURITY INVOKER
    AS $$
DECLARE
    current_revision  bigint;
    revision_start    bigint;
    revision_end      bigint;
    clock_now         timestamptz;
    restore_point     text;
    restore_point_lsn pg_lsn;
BEGIN
    -- Set search_path for security (LOCAL to avoid transaction control conflicts)
    SET LOCAL search_path = metagration, pg_catalog, pg_temp;
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
    LANGUAGE plpgsql
    SECURITY INVOKER
    AS $$
DECLARE
    revision_start bigint;
    revision_end bigint;
    delta bigint = run_to::bigint;
BEGIN
    -- Set search_path for security (LOCAL to avoid transaction control conflicts)
    SET LOCAL search_path = metagration, pg_catalog, pg_temp;
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
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
BEGIN
    ASSERT starts_with(result, 'ok');
    RAISE NOTICE '%', result;
END;
$$;

CREATE OR REPLACE PROCEDURE metagration.verify()
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = metagration, pgtap, public, pg_catalog, pg_temp
    AS $$
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
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE
    SECURITY INVOKER
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
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
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE
    SECURITY INVOKER
    SET search_path = metagration, pg_catalog, pg_temp
    AS $$
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
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = metagration, pg_catalog, pg_temp
AS $$
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
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = metagration, pg_catalog, pg_temp
AS $$
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
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = metagration, pg_catalog, pg_temp
AS $$
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

CREATE OR REPLACE PROCEDURE metagration.setup_permissions(
    migration_role text DEFAULT 'migration_admin'
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = metagration, pg_catalog, pg_temp
AS $$
BEGIN
    -- Revoke all public access to metagration schema
    EXECUTE format('REVOKE ALL ON SCHEMA metagration FROM PUBLIC');
    EXECUTE format('REVOKE ALL ON SCHEMA metagration_scripts FROM PUBLIC');

    -- Grant usage on schemas
    EXECUTE format('GRANT USAGE ON SCHEMA metagration TO %I', migration_role);
    EXECUTE format('GRANT USAGE ON SCHEMA metagration_scripts TO %I', migration_role);

    -- Grant SELECT to view migration state
    EXECUTE format('GRANT SELECT ON metagration.script TO %I', migration_role);
    EXECUTE format('GRANT SELECT ON metagration.log TO %I', migration_role);

    -- Grant INSERT, UPDATE for creating and running migrations
    EXECUTE format('GRANT INSERT, UPDATE ON metagration.script TO %I', migration_role);
    EXECUTE format('GRANT INSERT ON metagration.log TO %I', migration_role);
    EXECUTE format('GRANT USAGE ON SEQUENCE metagration.script_revision_seq TO %I', migration_role);

    -- Grant CREATE on script schema for procedure creation
    EXECUTE format('GRANT CREATE ON SCHEMA metagration_scripts TO %I', migration_role);

    -- Grant EXECUTE on all functions/procedures
    EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA metagration TO %I', migration_role);
    EXECUTE format('GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA metagration TO %I', migration_role);

    RAISE NOTICE 'Permissions configured for role: %', migration_role;
    RAISE NOTICE 'Users in this role can create and run migrations';
    RAISE NOTICE 'Consider: GRANT % TO <username>', migration_role;
END;
$$;

COMMENT ON PROCEDURE metagration.setup_permissions(text) IS
'Configure recommended permissions for migration management.
Creates a restricted permission model where only the specified role
can create and run migrations. Default role is migration_admin.';

-- ============================================================================
-- DATABASE INTROSPECTION VIEWS
-- ============================================================================

-- Base view: metagration.relations
-- All table-like objects with common attributes
CREATE VIEW metagration.relations WITH (security_invoker = true) AS
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN CASE
            WHEN c.relispartition THEN 'partition'
            ELSE 'table'
        END
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'matview'
        WHEN 'f' THEN 'foreign_table'
        WHEN 'p' THEN 'table'  -- partitioned table
    END AS relation_type,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    ts.spcname AS tablespace,
    c.reltuples::bigint AS row_estimate,
    COALESCE(pg_catalog.pg_total_relation_size(c.oid), 0) AS total_bytes,
    COALESCE(pg_catalog.pg_table_size(c.oid), 0) AS table_bytes,
    COALESCE(pg_catalog.pg_indexes_size(c.oid), 0) AS index_bytes,
    COALESCE(pg_catalog.pg_total_relation_size(c.oid), 0) -
        COALESCE(pg_catalog.pg_table_size(c.oid), 0) -
        COALESCE(pg_catalog.pg_indexes_size(c.oid), 0) AS toast_bytes,
    pg_catalog.obj_description(c.oid, 'pg_class') AS comment,
    s.last_vacuum AS last_vacuum,
    s.last_analyze AS last_analyzed,
    (c.relhasindex) AS has_indexes,
    (EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid = c.oid AND tgisinternal = false)) AS has_triggers,
    (c.relhasrules) AS has_rules
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_tablespace ts ON ts.oid = c.reltablespace
LEFT JOIN pg_catalog.pg_stat_all_tables s ON s.relid = c.oid
WHERE c.relkind IN ('r', 'v', 'm', 'f', 'p')
    AND n.nspname NOT IN ('pg_toast')
    AND pg_catalog.has_table_privilege(c.oid, 'SELECT');

-- metagration.columns
-- Comprehensive column information for all accessible tables
CREATE VIEW metagration.columns WITH (security_invoker = true) AS
SELECT
    c.table_schema AS schema_name,
    c.table_name,
    c.column_name,
    c.ordinal_position,
    c.data_type,
    c.udt_name,
    c.character_maximum_length,
    c.numeric_precision,
    c.numeric_scale,
    (c.is_nullable = 'YES') AS is_nullable,
    c.column_default,
    COALESCE(c.is_generated = 'ALWAYS', false) AS is_generated,
    c.generation_expression,
    COALESCE(c.is_identity = 'YES', false) AS is_identity,
    c.identity_generation,
    c.identity_start::bigint,
    c.identity_increment::bigint,
    c.collation_name,
    pg_catalog.col_description(
        (c.table_schema || '.' || c.table_name)::regclass::oid,
        c.ordinal_position
    ) AS comment
FROM information_schema.columns c
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = c.table_schema
    AND r.relation_name = c.table_name
);

-- metagration.constraints
-- All constraint types unified
CREATE VIEW metagration.constraints WITH (security_invoker = true) AS
SELECT
    tc.table_schema AS schema_name,
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    ARRAY_AGG(kcu.column_name ORDER BY kcu.ordinal_position) FILTER (WHERE kcu.column_name IS NOT NULL) AS column_names,
    cc.check_clause,
    ccu.table_schema AS foreign_schema_name,
    ccu.table_name AS foreign_table_name,
    ARRAY_AGG(ccu.column_name ORDER BY kcu.position_in_unique_constraint) FILTER (WHERE ccu.column_name IS NOT NULL) AS foreign_column_names,
    rc.match_option,
    rc.update_rule,
    rc.delete_rule,
    (tc.is_deferrable = 'YES') AS is_deferrable,
    (tc.initially_deferred = 'YES') AS initially_deferred
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
    ON tc.constraint_schema = kcu.constraint_schema
    AND tc.constraint_name = kcu.constraint_name
    AND tc.table_name = kcu.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_schema = ccu.constraint_schema
    AND tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.referential_constraints rc
    ON tc.constraint_schema = rc.constraint_schema
    AND tc.constraint_name = rc.constraint_name
LEFT JOIN information_schema.check_constraints cc
    ON tc.constraint_schema = cc.constraint_schema
    AND tc.constraint_name = cc.constraint_name
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = tc.table_schema
    AND r.relation_name = tc.table_name
)
GROUP BY
    tc.table_schema, tc.table_name, tc.constraint_name, tc.constraint_type,
    cc.check_clause, ccu.table_schema, ccu.table_name,
    rc.match_option, rc.update_rule, rc.delete_rule,
    tc.is_deferrable, tc.initially_deferred;

-- metagration.tables_detail
-- Table-specific attributes
CREATE VIEW metagration.tables_detail WITH (security_invoker = true) AS
SELECT
    r.schema_name,
    r.relation_name AS table_name,
    CASE c.relpersistence
        WHEN 'p' THEN 'permanent'
        WHEN 't' THEN 'temporary'
        WHEN 'u' THEN 'unlogged'
    END AS persistence,
    (c.relkind = 'p' OR c.relispartition) AS is_partitioned,
    pg_catalog.pg_get_partkeydef(c.oid) AS partition_key
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
WHERE r.relation_type IN ('table', 'partition');

-- metagration.views_detail
-- View-specific attributes
CREATE VIEW metagration.views_detail WITH (security_invoker = true) AS
SELECT
    r.schema_name,
    r.relation_name AS view_name,
    v.view_definition AS definition,
    (v.is_updatable = 'YES') AS is_updatable,
    v.check_option
FROM metagration.relations r
JOIN information_schema.views v
    ON v.table_schema = r.schema_name
    AND v.table_name = r.relation_name
WHERE r.relation_type = 'view';

-- metagration.materialized_views_detail
-- Materialized view attributes
-- Note: PostgreSQL does not track REFRESH MATERIALIZED VIEW timestamps in system catalogs
CREATE VIEW metagration.materialized_views_detail WITH (security_invoker = true) AS
SELECT
    r.schema_name,
    r.relation_name AS matview_name,
    mv.definition,
    mv.ispopulated AS has_data
FROM metagration.relations r
JOIN pg_catalog.pg_matviews mv
    ON mv.schemaname = r.schema_name
    AND mv.matviewname = r.relation_name
WHERE r.relation_type = 'matview';

-- metagration.foreign_tables_detail
-- Foreign table attributes
CREATE VIEW metagration.foreign_tables_detail WITH (security_invoker = true) AS
SELECT
    r.schema_name,
    r.relation_name AS table_name,
    fs.srvname AS server_name,
    fdw.fdwname AS server_type,
    fs.srvversion AS server_version,
    ARRAY(
        SELECT pg_catalog.quote_ident(option_name) || '=' || pg_catalog.quote_literal(option_value)
        FROM pg_catalog.pg_options_to_table(ft.ftoptions)
    ) AS foreign_table_options
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
JOIN pg_catalog.pg_foreign_table ft ON ft.ftrelid = c.oid
JOIN pg_catalog.pg_foreign_server fs ON fs.oid = ft.ftserver
JOIN pg_catalog.pg_foreign_data_wrapper fdw ON fdw.oid = fs.srvfdw
WHERE r.relation_type = 'foreign_table';

-- metagration.partitions_detail
-- Partition relationship information
CREATE VIEW metagration.partitions_detail WITH (security_invoker = true) AS
SELECT
    r.schema_name,
    r.relation_name AS partition_name,
    pn.nspname AS parent_schema_name,
    pc.relname AS parent_table_name,
    pg_catalog.pg_get_expr(c.relpartbound, c.oid) AS partition_expression,
    c.relispartition AS is_default
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON c.relname = r.relation_name
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = r.schema_name
LEFT JOIN pg_catalog.pg_inherits i ON i.inhrelid = c.oid
LEFT JOIN pg_catalog.pg_class pc ON pc.oid = i.inhparent
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
WHERE r.relation_type = 'partition';

-- metagration.column_statistics
-- Statistical distribution data
CREATE VIEW metagration.column_statistics WITH (security_invoker = true) AS
SELECT
    s.schemaname AS schema_name,
    s.tablename AS table_name,
    s.attname AS column_name,
    s.null_frac AS null_fraction,
    s.avg_width,
    s.n_distinct,
    s.correlation,
    s.most_common_vals::text AS most_common_vals,
    s.most_common_freqs
FROM pg_catalog.pg_stats s
WHERE EXISTS (
    SELECT 1 FROM metagration.relations r
    WHERE r.schema_name = s.schemaname
    AND r.relation_name = s.tablename
);

-- Create migration script for introspection views
-- This allows views to be versioned and rolled back if needed
-- Note: This runs after extension creation, not during
DO $$
BEGIN
    -- Only create if we're NOT creating an extension (i.e., after extension is created)
    -- During CREATE EXTENSION, pg_extension has an entry with objid = NULL for the extension being created
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_depend d
        JOIN pg_catalog.pg_extension e ON d.refobjid = e.oid
        WHERE e.extname = 'metagration'
        AND d.deptype = 'e'
        LIMIT 1
    ) THEN
        -- We're not in extension creation context, safe to create migration script
        IF EXISTS (
            SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'metagration' AND c.relname = 'script'
        ) THEN
            -- Check if this script already exists
            IF NOT EXISTS (
                SELECT 1 FROM metagration.script WHERE comment = 'Add database introspection views'
            ) THEN
                PERFORM metagration.new_script(
                    $up$
                        -- Views are already created above, this is a no-op placeholder
                        -- In production, views would be created here
                        DO $noop$ BEGIN NULL; END $noop$;
                    $up$,
                    $down$
                        -- Drop all introspection views in reverse order
                        DROP VIEW IF EXISTS metagration.column_statistics;
                        DROP VIEW IF EXISTS metagration.partitions_detail;
                        DROP VIEW IF EXISTS metagration.foreign_tables_detail;
                        DROP VIEW IF EXISTS metagration.materialized_views_detail;
                        DROP VIEW IF EXISTS metagration.views_detail;
                        DROP VIEW IF EXISTS metagration.tables_detail;
                        DROP VIEW IF EXISTS metagration.constraints;
                        DROP VIEW IF EXISTS metagration.columns;
                        DROP VIEW IF EXISTS metagration.relations;
                    $down$,
                    comment := 'Add database introspection views'
                );
            END IF;
        END IF;
    END IF;
END $$;
