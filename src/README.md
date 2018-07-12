## Preparation

```sh
php src/pack2sql.php
sh src/cache/makeTmp.sh
PGPASSWORD=postgres psql -h localhost -U postgres test < src/cache/makeTmp.sql
PGPASSWORD=postgres psql -h localhost -U postgres test < src/step1-lib.sql
```

## Data provenience of v1
The version 1.0 was created from more than one data source.
IBGE is authoritative but not a perfect source, and there are complements like CEP and Wikidata-ID that can also help to solve naming conflicts.

After this first load-and-review, from many sources, the maintenance is easy and can be done by hand with the collaborative spreadsheet.

### 1. Main dataset from IBGE
((merge with "old import"))

```
cd /tmp
wget ftp://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/divisao_territorial/2015/dtb_2015.zip
unzip dtb_2015.zip # will inflate to dtb_2015/RELATORIO_DTB_BRASIL_MUNICIPIO.ods, etc.
```
```sql
DROP FOREIGN TABLE IF EXISTS tmpcsv_ibge_municipios CASCADE; -- danger drop VIEWS
CREATE FOREIGN TABLE tmpcsv_ibge_municipios (
    "UF" text, "Nome_UF" text,
    "Mesorregião Geográfica" text, "Nome_Mesorregião" text,
    "Microrregião Geográfica" text, "Nome_Microrregião" text,
    "Município" text, "Código Município Completo" text,
    "Nome_Município" text
) SERVER csv_files OPTIONS (
     filename '/tmp/dtb_2015/RELATORIO_DTB_BRASIL_MUNICIPIO.csv',
     format 'csv',
     header 'true'
);

CREATE VIEW tmpvw_ibge_municipios AS
  SELECT  t.name, s.subdivision as state, t."idIBGE",
          oficial.name2lex(t.name) as "lexLabel"
  FROM (
     SELECT "Nome_Município" as name, "UF" as ufcode, "Código Município Completo" as "idIBGE"
     FROM tmpcsv_ibge_municipios
  ) t INNER JOIN tmpcsv_br_state_codes s ON s.idibge=t.ufcode
  ORDER BY 4, 2  -- lexlabel e uf
;

-- Conferindo se vazio:
SELECT state||';'||name as vazio       FROM tmpvw_ibge_municipios group by 1 having count(*)>1;
SELECT state||';'||"lexLabel" as vazio FROM tmpvw_ibge_municipios group by 1 having count(*)>1;
```

Para gravar uma primeira versão do CSV basta

```sh
PGPASSWORD=postgres psql -h localhost -U postgres obsjats -c \
    "COPY (select * from tmpvw_ibge_municipios) TO STDOUT CSV HEADER" > \
    first.csv
```

### 2. Add Wikidata-ID

For original and maintenance.

1. Get wikitext by (after edit-source interface) copy/paste
2. See other at [Wiki - Original preparation](https://github.com/datasets-br/city-codes/wiki/Original-preparation)

```sh
php src/wikitext2CSC.php < copy.wiki.txt > test.csv
```

### 3. Add CEP (postalcode_ranges)

1. Get official list (where?)
2. load and check join columns: IBGE-code or `<state,lexlabel>` as primary key. The `lexLabel` can be obtained by *name2lex(name)* funciton, but need also resolve by synonyms.
3. reformat cep-ranges as array of intervals with the format `[123 456] [888 999]`.
4. JOIN and UPDATE main table with `postalcode_ranges`.

See `CEPS_FAIXA2.csv` as first source.

## CONSOLE for maintenance

After all steps installation, run the *cosole*  with *psql*,  eg. `psql "postgresql://postgres:postgres@localhost:5432/trydatasets" -f src/io_console.sql`.

It will output the following:
```
-------------- Input/Output --------------
--- 1. Preparing... ---
...

--- 2. Configurando valores... ---
 workfolder |    citfile    |     synfile      | aux
------------+---------------+------------------+-----
 /tmp       | br-city-codes | br-city-synonyms |
...
>> Digite (ENTER ou) o nome ...:
```

## Prepare for maintenance asserts
Revisar antigo preparador de asserts e levar para o `step2-io_lib.sql`.. See [step4_asserts1.sql](step4_asserts1.sql)...


### Changing CSV by SQL
Para alterações manuais porém controladas pelo SQL. Depois de rodar o console para a carga de `citybr`,
```SQL
--- UPDATING  EXAMPLE:
UPDATE citybr SET ddd=46 WHERE "idIBGE"='4128625' AND "lexLabel"='alto.paraiso';  -- ops RO,ALTO PARAÍSO,69
UPDATE citybr SET ddd=14 WHERE "idIBGE"='3520905' AND "lexLabel"='ipaussu';  -- embratel grafou 'Ipauçu'
UPDATE citybr SET ddd=11 WHERE "idIBGE"='3515004' AND "lexLabel"='embu.artes'; -- embratel grafou só "embu"
UPDATE citybr SET ddd=67 WHERE "idIBGE"='5003900' AND "lexLabel"='figueirao'; -- nao tinha na tabela anatel
```
em seguida rodar console para export.

### Initial IBGE
old import...

```sql
-- old for first IBGE exporting
SELECT i.name, c.state, c.wdid as "wdId", i."idIBGE", oficial.name2lex(i.name) as "lexLabel",
       c.creation, c.extinction, c.postalcode_ranges as "postalCode_ranges", c.notes
FROM tmpcsv_br_city_codes c INNER JOIN tmpvw_ibge_municipios i
  ON i."idIBGE"=c.idibge
ORDER BY 5,2
;
```

-------

## Other

Use the console.

```sql
-- Para uso nos projetos CRP e CLP:
SELECT state, lexlabel, extract_common_prefix(x[1],x[2]) cep_prefix,"postalCode_ranges"
FROM (
  SELECT state, "lexLabel" lexlabel, "postalCode_ranges",
      regexp_split_to_array(  regexp_replace("postalCode_ranges",'[\[\]\-]','','g')  , ' ') x
  FROM citybr where not("postalCode_ranges" like '%] [%' or "postalCode_ranges" is null)
) t
;
--- contando que por volta de 90 cidades possuem entre um e dois dígitos removidos, todas as ~5400 podem remover 3 dígitos iniciais do cep.
-- Quanto Aos códigos de rua, a maioria ainda possue pelo menos um zero no final, logo ficamos com 4  díditos descritores de via urbana.
--- Isso também serve de referência para se criar contadores de vias urbanas, não precisam mais que 4 dígitos.
```

### Synonyms generation for multi-word names
Nomes compostos precisam de entrada de "sinônimo por redução", por exemplo *Embu das Artes* é "Embu" e *Brasilândia de Minas* é "Brasilândia".

O algorimo a seguirs se baseia na estatística geral dos nomes e na estatística local (dentro de um estado):
* *stop words*: além das preposisões, palavras utilizadas com frequência maior que cinco entre todos os 5500 nomes de municípios;
* *apelidos válidos*: palavras utilizadas uma só vez entre todos os nomes do estado do município, e que não sejam *stop words*.

Use the console.

```sql
--- ver step2-iolib.sql  VIEWs io.citybr_stop_words  e  io.citybr_new_synonym
```
