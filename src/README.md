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

## Prepare for maintenance
...  See [step4_asserts1.sql](step4_asserts1.sql)...


-------

## Other

```sql
-- exporting
SELECT i.name, c.state, c.wdid as "wdId", i."idIBGE", oficial.name2lex(i.name) as "lexLabel", 
       c.creation, c.extinction, c.postalcode_ranges as "postalCode_ranges", c.notes
FROM tmpcsv_br_city_codes c INNER JOIN tmpvw_ibge_municipios i
  ON i."idIBGE"=c.idibge
ORDER BY 5,2
;
```
