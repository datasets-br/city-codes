-- -- -- -- --
-- !CONSOLE DO city-codes!
-- @use psql -f io_console.sql
-- @see psql "postgresql://postgres:postgres@localhost:5432/trydatasets" -f src/io_console.sql
-- -- -- -- --

\echo '-------------- Input/Output --------------'
\echo '--- 1. Preparing... ---'
\set ON_ERROR_STOP on
\echo '... se der algum erro, rode todos os "step*.sql" denovo. '
DELETE FROM io.prompt;
INSERT INTO io.prompt VALUES ('/tmp','br-city-codes','br-city-synonyms','');

\echo
\echo '--- 2. Configurando valores... ---'

SELECT * FROM io.prompt;
\prompt '>> Digite (ENTER ou) o nome da pasta "workfolder" caso não seja o apresentado: ' my
SELECT io.setvar('workfolder', :'my');
\prompt '>> Nome do "citfile" ou - para não usar: ' my
SELECT io.setvar('citfile', :'my');
\prompt '>> Nome do "synfile" ou - para não usar: ' my
SELECT io.setvar('synfile', :'my');
\echo 'Nomes configurados:'
SELECT * FROM io.prompt_list;

\echo
\echo '--- 3. Importando... ---'
SELECT  io.import_export('import');

\echo
\echo '--- 4. Processamento ---'
\echo 'proc 1 - refresh dos APELIDOS VÁLIDOS'
\echo 'proc 2 - ...'
\echo 'proc 3'
\prompt '>> Fazer algum processamento? (0 ou o numero): ' my
SELECT io.passo2_proc(:'my') as _processando_;

\echo
\echo '--- 5. Exportação ---'
\prompt '>> Exportar as tabelas processadas? (s/n) ' my
SELECT  io.import_export('export',:'my');
