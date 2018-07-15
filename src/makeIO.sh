cp  data/*.csv data/dump_etc/*.csv /tmp
psql "postgresql://postgres:postgres@localhost:5432/trydatasets" < src/step1-lib.sql
psql "postgresql://postgres:postgres@localhost:5432/trydatasets" < src/step2-io_lib.sql

psql "postgresql://postgres:postgres@localhost:5432/trydatasets" < src/io_console.sql
