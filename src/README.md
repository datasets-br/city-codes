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


### Inport CSV
```SQL
create table citybr (
 name text,state text,"wdId" text,"idIBGE" text,"lexLabel" text,
 creation integer, extinction integer,"postalCode_ranges" text,
 ddd integer,notes text
);
COPY citybr FROM '/tmp/br-city-codes.csv' CSV HEADER;

--- UPDATING  EXAMPLE:
UPDATE citybr SET ddd=46 WHERE "idIBGE"='4128625' AND "lexLabel"='alto.paraiso';  -- ops RO,ALTO PARAÍSO,69
UPDATE citybr SET ddd=14 WHERE "idIBGE"='3520905' AND "lexLabel"='ipaussu';  -- embratel grafou 'Ipauçu'
UPDATE citybr SET ddd=11 WHERE "idIBGE"='3515004' AND "lexLabel"='embu.artes'; -- embratel grafou só "embu"
UPDATE citybr SET ddd=67 WHERE "idIBGE"='5003900' AND "lexLabel"='figueirao'; -- nao tinha na tabela anatel

create table citybr_syn (
 synonym text, "wdId" text, cur_state text, "cur_lexLabel" text,type text, ref text, notes text
);
COPY citybr_syn FROM '/tmp/br-city-synonyms.csv' CSV HEADER;
```

### Export SQL2CSV
```sql
-- exporting LIXO
SELECT i.name, c.state, c.wdid as "wdId", i."idIBGE", oficial.name2lex(i.name) as "lexLabel",
       c.creation, c.extinction, c.postalcode_ranges as "postalCode_ranges", c.notes
FROM tmpcsv_br_city_codes c INNER JOIN tmpvw_ibge_municipios i
  ON i."idIBGE"=c.idibge
ORDER BY 5,2
;

--- correct sort BOM
COPY (
  SELECT *
  FROM dataset.vw2_br_city_codes
  ORDER BY std_collate(name), name, state
) TO '/tmp/test.csv' CSV HEADER;


---BOM
COPY (
  SELECT *
  FROM citybr_syn
  ORDER BY std_collate(synonym,type), synonym, cur_state
) TO '/tmp/syn_test.csv' CSV HEADER;
```

-------

## Other

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

### Synonyms standard sort
```sql
COPY (
  SELECT *
  FROM dataset.vw2_br_city_synonyms
  ORDER BY std_collate(synonym,type), synonym, cur_state
) TO '/tmp/br-city-synonyms.csv' CSV HEADER;
```

### Synonyms generation for multi-word names
Nomes compostos precisam de entrada de "sinônimo por redução", por exemplo *Embu das Artes* é "Embu" e *Brasilândia de Minas* é "Brasilândia".

O algorimo a seguirs se baseia na estatística geral dos nomes e na estatística local (dentro de um estado):
* *stop words*: além das preposisões, palavras utilizadas com frequência maior que cinco entre todos os 5500 nomes de municípios;
* *apelidos válidos*: palavras utilizadas uma só vez entre todos os nomes do estado do município, e que não sejam *stop words*.


```sql
CREATE VIEW citybr_stop_words AS
 SELECT unnest(parts) as name_part
 FROM (
   SELECT regexp_split_to_array(name, E'\\s+') as parts,
          "idIBGE" as ibge
   FROM citybr
 ) t
 GROUP BY 1
 having count(*)>2  -- THRESHOLD, popularity of the word
 ORDER BY 1
;

-- GERADOR DE APELIDOS VÁLIDOS:
SELECT name_part as synonym, "wdId", cur_state, "cur_lexLabel",
       'alt orto auto'::text as type, 'auto_nick'::text as ref, '(testing)'::text as notes
FROM (
	SELECT unnest(parts) as name_part,   --1
         state,    --2
         count(*) as n,                --3
         max("idIBGE") as "idIBGE",    --4
         max("wdId") as "wdId",
         max(state) as cur_state,
         max("lexLabel") as "cur_lexLabel",
         max(name) as debug
	FROM (
	  SELECT regexp_split_to_array(
		    regexp_replace( name, E' d[aeo] | d[oa]s | com | para |^d[aeo] | [aeo]s | [aeo] ', ' ', 'g' ),
		    E'\\s+'
		 ) as parts, name, "wdId","lexLabel",
		 "idIBGE", state
	  FROM citybr
	) t
	WHERE array_length(parts,1)>1 -- multi-word (nome composto)
	GROUP BY 1,2
	HAVING count(*)<2  -- to be UNIQUE (valid synonym)
	ORDER BY 3 DESC, 1, 2
) tt
WHERE name_part NOT IN (select name_part from citybr_stop_words)
      AND length(name_part)>2  -- THRESHOLD: 1-letter and 2-letter are ambigous  
;

```
