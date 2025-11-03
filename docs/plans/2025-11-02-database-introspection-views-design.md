# Database Introspection Views Design

**Date:** 2025-11-02
**Feature:** Database introspection views for webapp access
**Status:** Approved

## Overview

Add comprehensive database introspection views to the `metagration` schema to enable webapps to discover and analyze database structure. Views provide access to tables, views, materialized views, foreign tables, partitions, columns, constraints, and statistics.

## Requirements

### Use Cases
- Admin dashboards showing database structure overview
- Auto-generating API documentation or data dictionaries
- Building dynamic query builders or forms
- Schema comparison and migration tracking

### Security Model
- **Respect user permissions:** Views only show objects the current user has SELECT access to
- Use `has_table_privilege()` for permission filtering
- All views use `SECURITY INVOKER` to run with caller's privileges

### Scope
- All table-like objects: tables, views, materialized views, foreign tables, partitioned tables
- Comprehensive column information: basic attributes, constraints, statistics, documentation
- Schema filtering: Include `schema_name` column for webapp filtering (all schemas included)

## Architecture

**Hierarchical approach with detail views:**

### Base View
- `metagration.relations` - Common attributes for all table-like objects

### Type-Specific Detail Views
- `metagration.tables_detail` - Table-specific attributes
- `metagration.views_detail` - View-specific attributes
- `metagration.materialized_views_detail` - Materialized view attributes
- `metagration.foreign_tables_detail` - Foreign table attributes
- `metagration.partitions_detail` - Partition relationship info

### Supporting Views
- `metagration.columns` - Column information with joins to relations
- `metagration.constraints` - Unified constraint view (PK, FK, unique, check)
- `metagration.column_statistics` - Statistical distribution data

## View Schemas

### metagration.relations

Common fields for all table-like objects:

```sql
- schema_name          text       -- Schema containing the relation
- relation_name        text       -- Name of the table/view/etc
- relation_type        text       -- 'table', 'view', 'matview', 'foreign_table', 'partition'
- owner                text       -- Object owner
- tablespace           text       -- Tablespace name (NULL for default)
- row_estimate         bigint     -- Estimated row count (from pg_class.reltuples)
- total_bytes          bigint     -- Total size including indexes and TOAST
- table_bytes          bigint     -- Size of table data
- index_bytes          bigint     -- Size of indexes
- toast_bytes          bigint     -- Size of TOAST data
- comment              text       -- Object description/comment
- created_at           timestamp  -- Creation time (from pg_stat_all_tables)
- last_analyzed        timestamp  -- Last ANALYZE time
- has_indexes          boolean    -- Has indexes defined
- has_triggers         boolean    -- Has triggers defined
- has_rules            boolean    -- Has rules defined
```

### metagration.columns

Comprehensive column information:

```sql
- schema_name              text       -- Schema containing the table
- table_name               text       -- Table name
- column_name              text       -- Column name
- ordinal_position         integer    -- Column position in table
- data_type                text       -- High-level data type
- udt_name                 text       -- Underlying PostgreSQL type
- character_maximum_length integer    -- Max length for char/varchar
- numeric_precision        integer    -- Precision for numeric types
- numeric_scale            integer    -- Scale for numeric types
- is_nullable              boolean    -- Can contain NULL
- column_default           text       -- Default value expression
- is_generated             boolean    -- Is a generated column
- generation_expression    text       -- Generation expression for generated columns
- is_identity              boolean    -- Is an identity column
- identity_generation      text       -- 'ALWAYS' or 'BY DEFAULT'
- identity_start           bigint     -- Identity sequence start value
- identity_increment       bigint     -- Identity sequence increment
- collation_name           text       -- Collation for text types
- comment                  text       -- Column description
```

### metagration.constraints

Unified constraint information:

```sql
- schema_name           text       -- Schema containing the table
- table_name            text       -- Table name
- constraint_name       text       -- Constraint name
- constraint_type       text       -- 'PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE', 'CHECK'
- column_names          text[]     -- Array of column names in constraint
- check_clause          text       -- CHECK constraint expression
- foreign_schema_name   text       -- Referenced schema (for FK)
- foreign_table_name    text       -- Referenced table (for FK)
- foreign_column_names  text[]     -- Referenced columns (for FK)
- match_option          text       -- FK match option (FULL, PARTIAL, SIMPLE)
- update_rule           text       -- FK ON UPDATE action
- delete_rule           text       -- FK ON DELETE action
- is_deferrable         boolean    -- Can be deferred
- initially_deferred    boolean    -- Deferred by default
```

### metagration.tables_detail

Table-specific attributes:

```sql
- schema_name      text       -- Schema name
- table_name       text       -- Table name
- persistence      text       -- 'permanent', 'temporary', 'unlogged'
- is_partitioned   boolean    -- Is a partitioned table (parent)
- partition_key    text       -- Partition key expression (if partitioned)
```

### metagration.views_detail

View-specific attributes:

```sql
- schema_name   text       -- Schema name
- view_name     text       -- View name
- definition    text       -- View definition SQL
- is_updatable  boolean    -- Can be updated via UPDATE/INSERT/DELETE
- check_option  text       -- 'CASCADED', 'LOCAL', or NULL
```

### metagration.materialized_views_detail

Materialized view attributes:

```sql
- schema_name   text       -- Schema name
- matview_name  text       -- Materialized view name
- definition    text       -- View definition SQL
- has_data      boolean    -- Contains data (populated)
- last_refresh  timestamp  -- Last REFRESH MATERIALIZED VIEW time
```

### metagration.foreign_tables_detail

Foreign table attributes:

```sql
- schema_name          text       -- Schema name
- table_name           text       -- Foreign table name
- server_name          text       -- Foreign server name
- server_type          text       -- Foreign data wrapper type
- server_version       text       -- Foreign server version
- foreign_table_options text[]    -- Array of foreign table options (key=value)
```

### metagration.partitions_detail

Partition relationship information:

```sql
- schema_name           text       -- Schema name
- partition_name        text       -- Partition table name
- parent_schema_name    text       -- Parent table schema
- parent_table_name     text       -- Parent table name
- partition_expression  text       -- Partition bound expression
- is_default            boolean    -- Is the DEFAULT partition
```

### metagration.column_statistics

Statistical distribution data:

```sql
- schema_name        text       -- Schema name
- table_name         text       -- Table name
- column_name        text       -- Column name
- null_fraction      real       -- Fraction of entries that are NULL
- avg_width          integer    -- Average width in bytes
- n_distinct         real       -- Number of distinct values (-1 = all unique, positive = exact count, negative = fraction)
- correlation        real       -- Statistical correlation with physical row ordering
- most_common_vals   text[]     -- Most common values (as text)
- most_common_freqs  real[]     -- Frequencies of most common values
```

## Implementation Details

### Data Sources

**Primary source: pg_catalog**
- Use pg_catalog tables for performance and completeness
- Main tables: pg_class, pg_attribute, pg_constraint, pg_namespace, pg_stat_all_tables, pg_index, pg_trigger

**Secondary source: information_schema**
- Use information_schema.columns for standardized column metadata
- Already has permission filtering built-in

**Statistics source: pg_stats**
- Automatically respects user permissions
- Only shows statistics for tables user can SELECT

### Permission Filtering

All views include WHERE clause:
```sql
WHERE has_table_privilege(pg_class.oid, 'SELECT')
```

This ensures users only see objects they have permission to access.

### Size Calculations

```sql
total_bytes = pg_total_relation_size(oid)    -- Everything
table_bytes = pg_table_size(oid)              -- Table data + TOAST
index_bytes = pg_indexes_size(oid)            -- All indexes
toast_bytes = total_bytes - table_bytes - index_bytes
```

Use `COALESCE(size_function, 0)` since views/foreign tables may return NULL.

### Row Estimates

Use `pg_class.reltuples` for fast estimates. For exact counts, webapp queries table directly (expensive operation).

### Search Path Security

All views:
- Created with `SECURITY INVOKER`
- Use fully-qualified names (pg_catalog.pg_class, information_schema.columns)
- Prevent search_path injection attacks

### Detail View Pattern

Each detail view:
1. Joins to `metagration.relations` on (schema_name, relation_name)
2. Filters by `relation_type`
3. Joins to type-specific pg_catalog tables
4. Inherits permission filtering from base relations view

Example:
```sql
CREATE VIEW metagration.tables_detail AS
SELECT
    r.schema_name,
    r.relation_name AS table_name,
    CASE c.relpersistence
        WHEN 'p' THEN 'permanent'
        WHEN 't' THEN 'temporary'
        WHEN 'u' THEN 'unlogged'
    END AS persistence,
    c.relispartition AS is_partitioned,
    pg_get_partkeydef(c.oid) AS partition_key
FROM metagration.relations r
JOIN pg_catalog.pg_class c ON ...
WHERE r.relation_type = 'table';
```

## Migration Integration

These views will be added as a new metagration script, making them part of the migration system:

```sql
SELECT metagration.new_script(
    $up$
        -- CREATE VIEW statements
    $up$,
    $down$
        -- DROP VIEW statements (reverse order)
    $down$,
    comment := 'Add database introspection views'
);
```

This ensures:
- Views are versioned with the database schema
- Can be rolled back if needed
- Replicated across logical replication clusters
- Included in pg_dump backups

## Testing Strategy

1. **Permission tests:** Verify views respect has_table_privilege()
2. **Schema filtering:** Verify schema_name column for all objects
3. **Type coverage:** Verify each relation_type appears correctly
4. **Column metadata:** Verify all column attributes are accurate
5. **Constraint representation:** Verify PK, FK, unique, check constraints
6. **Detail view joins:** Verify detail views join correctly to base view
7. **Statistics access:** Verify pg_stats data flows through correctly

## Future Enhancements

Potential additions (YAGNI for v1):
- Index details view (index columns, type, unique, partial conditions)
- Sequence information view
- Function/procedure introspection
- Trigger details view
- Schema dependencies (what references what)
- Historical size tracking (requires materialized view + refresh)
