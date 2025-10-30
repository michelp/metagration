# Metagration 2.0.0 - TLE Release

**Release Date:** 2025-10-30

## Breaking Changes

Metagration is now distributed as a Trusted Language Extension (TLE) for PostgreSQL 18+. This is a **breaking change** from the v1.x PGXN extension.

### Migration Path

**From 1.x to 2.0:**

1. Export your existing migrations (optional, if you want SQL backup):
   ```sql
   SELECT metagration.export() \g export.sql
   ```

2. Drop the old extension:
   ```sql
   DROP EXTENSION metagration CASCADE;
   ```

3. Install pg_tle and metagration 2.0:
   ```sql
   CREATE EXTENSION pg_tle;
   \i install-tle.sql
   CREATE EXTENSION metagration;
   ```

4. Your migration data in `metagration.script` and `metagration.log` tables is preserved if you didn't use CASCADE.

## New Features

- **No Superuser Required**: TLE installs without superuser privileges
- **Cloud-Friendly**: Works in managed PostgreSQL environments (AWS RDS, Azure, GCP CloudSQL) that support pg_tle
- **Simpler Build**: Python-based build system replaces PGXS complexity
- **PostgreSQL 18**: Built for latest PostgreSQL version

## What's Changed

- Requires PostgreSQL 18+ (was 11+)
- Requires pg_tle extension
- Installed via `pgtle.install_extension()` not filesystem loading
- Build with `make tle` not `make install`
- Removed PGXN/PGXS infrastructure

## What's Unchanged

- All metagration functionality identical
- Migration script format unchanged
- API functions/procedures unchanged
- Test suite unchanged (same pgTAP tests)
- `sql/metagration.sql` remains single source of truth

## Files Changed

### Added
- `install-tle.sql.template` - TLE installation template
- `build-tle.py` - Build script
- `docs/plans/` - Design documentation

### Modified
- `Makefile` - Simplified to TLE build targets
- `Dockerfile` - PostgreSQL 18 + pg_tle
- `test.sh` - TLE installation workflow
- `README.md` - TLE installation instructions
- `CLAUDE.md` - Updated architecture docs
- `.gitignore` - Generated files

### Removed
- `META.json` - PGXN metadata

## Upgrade Considerations

- **Testing**: Thoroughly test in staging before production upgrade
- **Managed Databases**: Verify your cloud provider supports pg_tle
- **Automation**: Update deployment scripts for TLE installation
- **CI/CD**: Update pipelines to use `make tle` and new Dockerfile

## Technical Details

Version 2.0.0 maintains 100% API compatibility with 1.x at the SQL level. The only changes are installation mechanism and PostgreSQL version requirements.
