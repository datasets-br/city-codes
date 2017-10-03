

CREATE EXTENSION IF NOT EXISTS file_fdw;
CREATE SERVER csv_files FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE tmpcsv_lexml_loc (
  about text, prefLabel text, altLabel text, broader text, facetaAcronimo text, faceta text
) SERVER csv_files OPTIONS (
     filename '/tmp/localidade-v1.csv',
       format 'csv',
       header 'true'
);

CREATE FOREIGN TABLE tmpcsv_cities_wiki (
  state text, name text, wdid text
) SERVER csv_files OPTIONS (
     filename '/tmp/cities_from_wiki.csv',
       format 'csv',
       header 'true'
);


CREATE FOREIGN TABLE tmpcsv_state_codes (
-- From https://github.com/datasets-br/state-codes/blob/master/kx_csv2foreign_tables.sql 
	subdivision text,
	name_prefix text,
	name text,
	id int,
	idIBGE int,
	place_id int,
	wdId text,
	lexLabel text,
	creation int,
	extinction int,
	category text,
	timeZone text,
	utcOffset int,
	utcOffset_DST int,
	postalCode_ranges text,
	notes text
)   SERVER csv_files OPTIONS ( 
     filename '/tmp/br-state-codes.csv', --change
       format 'csv', 
       header 'true'
);



CREATE FOREIGN TABLE tmpcsv_ibge_cities (
-- From https://ww2.ibge.gov.br/home/geociencias/geografia/redes_fluxos/gestao_do_territorio_2014/base.shtm
-- ftp://geoftp.ibge.gov.br/organizacao_do_territorio/redes_e_fluxos_geograficos/gestao_do_territorio/bases_de_dados/ods/Base_de_dados_dos_municipios.ods
--  Editar planilha deletando demais colunas.
	UF text,
	CodUF text,
	Codmun text,
	NomeMunic text,
	VAR03 text
)   SERVER csv_files OPTIONS ( 
     filename '/tmp/ibge_municipios.csv', --change
       format 'csv', 
       header 'true'
);

SELECT s.subdivision, c.nomemunic , c.Codmun, oficial.name2lex(c.nomemunic) as xx
FROM tmpcsv_ibge_cities c INNER JOIN tmpcsv_state_codes s ON s.idIBGE=c.CodUF::int;

--
-- Preparo das fontes de dados:
--   php src/wikitext2CSV.php < ../br-cities.wiki.txt > /tmp/cities_from_wiki.csv
--   wget -c -O /tmp/localidade-v1.csv https://github.com/okfn-brasil/lexml-vocabulary/raw/master/data/localidade-v1.csv
--   wget -c -O /tmp/br-state-codes.csv https://github.com/datasets-br/state-codes/raw/master/data/br-state-codes.csv




CREATE VIEW tmpcsv_cities_wiki_lex AS
  SELECT c.*, concat('br;', s.lexlabel, ';', oficial.name2lex(c.name)) as lexlabel
  FROM tmpcsv_cities_wiki c INNER JOIN tmpcsv_state_codes s ON s.subdivision=c.state
;

-- bug report:
CREATE VIEW tmpcsv_cities_wiki_difflexv1 AS  -- differences from lexml_v1
SELECT * FROM tmpcsv_cities_wiki_lex WHERE lexlabel NOT IN (
  SELECT w.lexlabel  from tmpcsv_lexml_loc l INNER JOIN tmpcsv_cities_wiki_lex w ON w.lexlabel=l.about; 
);

-- prepare:
CREATE VIEW tmpcsv_cities_wiki_full AS
    SELECT name, state, wdid as "wdId", base36_encode(oficial.br_city_id_gap(name)*(row_number() OVER ()),4) as "idSeq", 
           oficial.name2lex(name) as "lexLabel",
           NULL::int AS creation, NULL::int AS extinction, NULL::text AS "postalCode_ranges", NULL::text AS notes 
    FROM tmpcsv_cities_wiki 
    ORDER BY name
;
-- Simulating ideal idSeq for firsts, base36_encode(oficial.br_city_id_gap(name)*(row_number() OVER ()),3) as "idSeq"  


COPY (
  SELECT f.name, f.state, f."wdId", c.Codmun AS "idIBGE", f."lexLabel",
       f.creation, f.extinction, f."postalCode_ranges", f.notes
  FROM (tmpcsv_ibge_cities c INNER JOIN tmpcsv_state_codes s ON s.idIBGE=c.CodUF::int) 
     LEFT JOIN tmpcsv_cities_wiki_full f ON f.state=s.subdivision AND oficial.name2lex(c.nomemunic)=f."lexLabel"
) TO '/tmp/br-cities.csv' DELIMITER ',' CSV HEADER;


