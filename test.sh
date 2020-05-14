#!/bin/bash

DB_HOST="metagration-test-db"
DB_NAME="postgres"
SU="postgres"
EXEC="docker exec $DB_HOST"

echo destroying test container and image
docker rm --force "$DB_HOST"

set -e

echo building test image
docker build . -t metagration/test

echo running test container
docker run -e POSTGRES_HOST_AUTH_METHOD=trust -d \
       -v `pwd`:/metagration                     \
       --name "$DB_HOST"                         \
       metagration/test                          # \
       # -c 'wal_level=logical'                    \
       # -c 'archive_mode=on'                      \
       # -c "archive_command='test ! -f /archivedir/%f && cp %p /archivedir/%f'"

echo waiting for database to accept connections
until
    $EXEC \
	    psql -o /dev/null -t -q -U "$SU" \
        -c 'select pg_sleep(1)' \
	    2>/dev/null;
do sleep 1;
done

echo running tests
$EXEC psql -U "$SU" -f /metagration/test.sql

# docker rmi metagration/test
