FROM postgres:14
RUN apt-get update && apt-get install -y postgresql-14-pgtap postgresql-plpython3-14
RUN mkdir "/metagration"
RUN mkdir "/archivedir"
WORKDIR "/metagration"
COPY . .
COPY metagration.sql /docker-entrypoint-initdb.d/
