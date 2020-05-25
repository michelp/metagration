FROM postgres:12
RUN apt-get update && apt-get install -y postgresql-12-pgtap postgresql-plpython3-12 zile vim
RUN mkdir "/metagration"
RUN mkdir "/archivedir"
WORKDIR "/metagration"
COPY . .
COPY metagration.sql /docker-entrypoint-initdb.d/
