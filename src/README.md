## Preparation

```sh
php src/pack2sql.php
sh src/cache/makeTmp.sh
PGPASSWORD=postgres psql -h localhost -U postgres test < src/cache/makeTmp.sql
PGPASSWORD=postgres psql -h localhost -U postgres test < src/step01-lib.sql
```

## Get main dataset from IBGE

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

CREATE VIEW vw_ibge_municipios AS
  SELECT  t.name, s.subdivision as state, NULL::text as "wdId", t."idIBGE", oficial.name2lex(t.name) as "lexLabel"
  FROM (
     SELECT "Nome_Município" as name, "UF" as ufcode, "Código Município Completo" as "idIBGE"
     FROM tmpcsv_ibge_municipios
  ) t INNER JOIN tmpcsv_br_state_codes s ON s.idibge=t.ufcode
;
```

## Original and check Wikidata

1. Get wikitext by (after edit-source interface) copy/paste 
2. See other at [Wiki - Original preparation](https://github.com/datasets-br/city-codes/wiki/Original-preparation)

```sh
php src/wikitext2CSC.php < copy.wiki.txt > test.csv
```


