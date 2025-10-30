#!/bin/bash
# Test script for metagration TLE
# NOTE: This script requires install-tle.sql - run 'make test' instead of './test.sh' directly

DB_HOST="metagration-test-db"
DB_NAME="postgres"
SU="postgres"
EXEC="docker exec $DB_HOST"

echo "Destroying test container"
docker rm --force "$DB_HOST" 2>/dev/null || true

set -e

echo "Building test image"
docker build . -t metagration/test

echo "Running test container"
docker run -e POSTGRES_HOST_AUTH_METHOD=trust -d \
       -v "$(pwd)":/metagration \
       --name "$DB_HOST" \
       metagration/test

echo "Waiting for database to accept connections"
until
    $EXEC \
        psql -o /dev/null -t -q -U "$SU" \
        -c 'select pg_sleep(1)' \
        2>/dev/null;
do sleep 1;
done

echo "Installing pg_tle extension"
$EXEC psql -U "$SU" -d "$DB_NAME" -c "CREATE EXTENSION pg_tle;"

echo "Installing metagration TLE"
$EXEC psql -U "$SU" -d "$DB_NAME" -f /metagration/install-tle.sql

echo "Creating metagration extension"
$EXEC psql -U "$SU" -d "$DB_NAME" -c "CREATE EXTENSION metagration;"

echo "Running tests"
$EXEC psql -U "$SU" -d "$DB_NAME" -f /metagration/test/test.sql

echo "All tests passed!"
