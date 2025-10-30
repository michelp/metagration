FROM postgres:18

# Install build dependencies for pg_tle
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    postgresql-server-dev-18 \
    flex \
    bison \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone and install pg_tle (pinned to stable v1.5.2 for PostgreSQL 18)
RUN cd /tmp && \
    git clone --branch v1.5.2 --depth 1 https://github.com/aws/pg_tle.git && \
    cd pg_tle && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pg_tle

# Verify pg_tle installation
RUN test -f /usr/share/postgresql/18/extension/pg_tle.control || \
    (echo "ERROR: pg_tle installation failed - pg_tle.control not found" && exit 1)

# Configure pg_tle to be preloaded
RUN echo "shared_preload_libraries = 'pg_tle'" >> /usr/share/postgresql/postgresql.conf.sample

# Install pgTAP for testing
RUN cd /tmp && \
    git clone https://github.com/theory/pgtap.git && \
    cd pgtap && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pgtap

# Volume mounting strategy:
# - Standard postgres image uses /docker-entrypoint-initdb.d/ for initialization scripts
# - Our test.sh will mount the metagration source into the container for testing
