# Metagration - Developer Guide

## Project Overview

Metagration is a PostgreSQL-native database migration framework that uses logical replication to enable zero-downtime schema migrations. This is a mature, production-ready tool (v2.0.0) distributed as a Trusted Language Extension (TLE) for PostgreSQL 18+.

The core philosophy: migrations are PostgreSQL functions, executed in dependency order via topological sort, with full ACID guarantees.

## Architecture

Metagration uses a single-file architecture where `sql/metagration.sql` (~470 lines) is the source of truth. For v2.0+, this source is built into a TLE installer using a Python build script.

**Key Components:**
- Migration scripts stored in `metagration.script` table
- Execution log in `metagration.log` table
- Topological sort for dependency resolution
- Transaction-wrapped execution with rollback support

## File Structure

### Build System
- `sql/metagration.sql`: Single source file (~470 lines) - source of truth
- `install-tle.sql.template`: Template with {{VERSION}} and {{SOURCE}} markers
- `build-tle.py`: Python script that generates TLE installer
- `install-tle.sql`: Generated TLE installer (git-ignored)
- `Makefile`: Simple build targets (tle, test, clean)

### Testing
- `test/test.sql`: Main test runner using pgTAP (plans 100 tests)
- `test/core.sql`: Core functionality tests
- `test/verify.sql`: Verification tests
- `test.sh`: Docker-based test runner
- `Dockerfile`: PostgreSQL 18 + pg_tle test image

### Documentation
- `README.md`: User-facing installation and usage
- `CLAUDE.md`: This file - developer guidance
- `docs/plans/`: Design documents and implementation plans

## Development Commands

### Building TLE Installer
```bash
# Generate install-tle.sql from source
make tle

# This runs: python3 build-tle.py
# Reads: sql/metagration.sql, install-tle.sql.template
# Generates: install-tle.sql
```

### Running Tests
```bash
# Full test suite using Docker
make test

# This will:
# 1. Build install-tle.sql
# 2. Build metagration/test Docker image (PostgreSQL 18 + pg_tle)
# 3. Run PostgreSQL container with mounted volume
# 4. Install pg_tle extension
# 5. Install metagration TLE
# 6. Execute test/test.sql with pgTAP tests
```

### Manual Testing
```bash
# In a PostgreSQL 18 database with pg_tle:
CREATE EXTENSION pg_tle;
\i install-tle.sql
CREATE EXTENSION metagration;

# Uninstall:
DROP EXTENSION metagration CASCADE;
SELECT pgtle.uninstall_extension('metagration');
```

## Important Constraints

1. **Single Source File**: All functionality in `sql/metagration.sql` - do not split into multiple files
2. **No External Dependencies**: Pure PostgreSQL - no external libraries or languages (except build tools)
3. **Backward Compatibility**: Migration format and API must remain stable
4. **Test Coverage**: All changes must pass 100 pgTAP tests
5. **TLE Installation Required**: Must install via `pg_tle.install_extension()` - traditional `CREATE EXTENSION` loading from filesystem not supported in v2.0+

## Security Model

Metagration implements defense-in-depth security:

### search_path Protection
All functions/procedures set `search_path = metagration, pg_catalog, pg_temp` to prevent injection attacks. This is critical - do not remove these settings.

### Schema Validation
The `script_schema` column has a CHECK constraint requiring valid PostgreSQL identifiers. This prevents malicious schema injection when executing migration procedures.

### Permission Model
- All procedures use `SECURITY INVOKER` (run with caller's privileges)
- Use `metagration.setup_permissions()` to configure role-based access
- Only trusted users should have migration permissions
- Migration scripts execute arbitrary SQL by design - this requires trust

### Dynamic SQL Rules
When modifying code:
- Use `%I` for identifier quoting (schema/table/column names)
- Use `%L` for literal quoting (string values)
- Use `USING` clauses for parameterized queries
- Never use `%s` for user-controlled identifiers
- Always set `search_path` in function definitions

## Core Functionality

### Migration Script Format

Migrations are stored in `metagration.script` table:
- `name`: Unique identifier (e.g., "001_create_users")
- `script`: SQL code to execute
- `reverse`: Rollback SQL (optional)
- `requires`: Array of dependency names

### Execution Flow

1. User calls `metagration.apply()` or `metagration.apply(target_revision)`
2. System performs topological sort of unapplied scripts
3. Each script executed in transaction
4. Success/failure logged to `metagration.log`
5. Current revision tracked via `metagration.current_revision()`

### Key Functions

- `metagration.apply(integer)`: Apply migrations up to target revision
- `metagration.current_revision()`: Get current revision number
- `metagration.export()`: Export all scripts as SQL
- `metagration.rollback(integer)`: Roll back to target revision
- `metagration.plan(integer)`: Show execution plan without applying

## Testing Philosophy

- 100 pgTAP tests covering core functionality
- Tests run in Docker with PostgreSQL 18 + pg_tle
- Test data is deterministic and isolated
- Each test verifies specific behavior with clear assertions

## Making Changes

1. Edit `sql/metagration.sql` directly
2. Run `make test` to verify changes
3. Update tests if adding/changing functionality
4. Update README.md if user-facing changes
5. Rebuild TLE installer: `make tle`

## Common Tasks

### Adding a New Feature
1. Add implementation to `sql/metagration.sql`
2. Add pgTAP tests to appropriate test file
3. Run `make test` to verify
4. Update documentation

### Fixing a Bug
1. Add failing test that reproduces bug
2. Fix in `sql/metagration.sql`
3. Verify test now passes
4. Check all 100 tests still pass

### Refactoring
1. Run `make test` to establish baseline
2. Make changes to `sql/metagration.sql`
3. Run `make test` to verify no regressions
4. All tests must still pass

## Version History

- v2.0.0: TLE release for PostgreSQL 18+
- v1.0.5: Final PGXN release supporting PostgreSQL 11+
