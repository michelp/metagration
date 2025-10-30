#!/usr/bin/env python3
"""
Build script for metagration TLE installer.
Reads sql/metagration.sql and injects it into install-tle.sql.template.
"""

import sys
from pathlib import Path

# Version for TLE
VERSION = "2.0.0"

def read_file(path: Path) -> str:
    """Read file contents as UTF-8 string."""
    try:
        return path.read_text(encoding='utf-8')
    except FileNotFoundError:
        print(f"Error: {path} not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {path}: {e}", file=sys.stderr)
        sys.exit(1)

def write_file(path: Path, content: str) -> None:
    """Write string to file as UTF-8."""
    try:
        path.write_text(content, encoding='utf-8')
        print(f"Generated: {path}")
    except Exception as e:
        print(f"Error writing {path}: {e}", file=sys.stderr)
        sys.exit(1)

def escape_sql(sql: str) -> str:
    """
    Escape SQL for use inside $_pgtle_$ dollar quotes.
    The template uses $_pgtle_$ so we don't need complex escaping,
    but we should verify the source doesn't contain $_pgtle_$.
    """
    if '$_pgtle_$' in sql:
        print("Error: Source SQL contains $_pgtle_$ which conflicts with template",
              file=sys.stderr)
        sys.exit(1)
    return sql

def build_tle():
    """Main build function."""
    # File paths
    source_sql = Path('sql/metagration.sql')
    template_file = Path('install-tle.sql.template')
    output_file = Path('install-tle.sql')

    print(f"Building TLE installer v{VERSION}")

    # Read source files
    sql_content = read_file(source_sql)
    template_content = read_file(template_file)

    # Escape and substitute
    escaped_sql = escape_sql(sql_content)
    output_content = template_content.replace('{{VERSION}}', VERSION)
    output_content = output_content.replace('{{SOURCE}}', escaped_sql)

    # Verify substitution completed
    if '{{VERSION}}' in output_content or '{{SOURCE}}' in output_content:
        print("Error: Template markers remain after substitution", file=sys.stderr)
        sys.exit(1)

    # Write output
    write_file(output_file, output_content)
    print(f"Success! Install with: psql -f {output_file}")

if __name__ == '__main__':
    build_tle()
