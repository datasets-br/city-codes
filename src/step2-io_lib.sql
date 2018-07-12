DROP SCHEMA IF EXISTS io CASCADE;
CREATE SCHEMA io;

--- tabelas de dados
CREATE table io.citybr (
 name text,state text,"wdId" text,"idIBGE" text,"lexLabel" text,
 creation integer, extinction integer,"postalCode_ranges" text,
 ddd integer,notes text
 ,UNIQUE (name,state)
 ,UNIQUE ("lexLabel",state)
);
CREATE table io.citybr_syn (
 synonym text, "wdId" text, cur_state text, "cur_lexLabel" text,type text, ref text, notes text,
 UNIQUE (synonym, cur_state)
 -- ,UNIQUE (synonym, cur_state, "cur_lexLabel")
 -- ,UNIQUE (synonym, "wdId")
);

------ interatividade
CREATE TABLE io.prompt(
  workfolder text,   citfile text,  synfile text, aux text
);
CREATE TABLE io.conf(
  etc text,
  c JSONb -- constants
);
INSERT INTO io.conf(etc,c) VALUES (
  '',
  '{"stop_words_threshold":2}'::JSONb
);

----------------------
----- BASIC FUNCTIONS:
CREATE FUNCTION io.getconf(text)  RETURNS text AS $f$
      SELECT c->>$1 FROM io.conf
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION io.check (text)  RETURNS boolean AS $f$
  SELECT CASE WHEN $1='-' THEN false ELSE true END
$f$ LANGUAGE sql;


------------
----- VIEWS:

CREATE VIEW io.prompt_list AS
   SELECT workfolder||'/'||citfile||'.csv' as f,  citfile as fbase,
          workfolder||'/final_'||citfile||'.csv' as ffinal,
          io.check(citfile) as useit, 'citybr' as tref
   FROM io.prompt
   UNION
   SELECT workfolder||'/'||synfile||'.csv', synfile,
          workfolder||'/final_'||synfile||'.csv',
          io.check(synfile), 'citybr_syn'
   FROM io.prompt
;

-- for EXPORT:
CREATE VIEW io.vwexp_citybr AS
  SELECT * FROM io.citybr -- or dataset.vw2_br_city_codes
  ORDER BY std_collate(name), name, state
;
CREATE VIEW io.vwexp_citybr_syn AS
  SELECT * FROM io.citybr_syn -- or dataset.vw2_br_city_synonyms
  ORDER BY std_collate(synonym,type), synonym, cur_state
;

-- for PROC:
CREATE VIEW io.citybr_stop_words AS
 SELECT unnest(parts) as name_part
 FROM (
   SELECT regexp_split_to_array(name, E'\\s+') as parts,
          "idIBGE" as ibge
   FROM io.citybr
 ) t
 GROUP BY 1
 having count(*)>io.getconf('stop_words_threshold')::int  -- THRESHOLD, popularity of the word
 ORDER BY 1
;
-- GERADOR DE APELIDOS VÁLIDOS:
CREATE VIEW io.citybr_new_synonym AS
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
  	  FROM io.citybr
  	) t
  	WHERE array_length(parts,1)>1 -- multi-word (nome composto)
  	GROUP BY 1,2
  	HAVING count(*)<2 -- to be UNIQUE (valid synonym)
  	ORDER BY 3 DESC, 1, 2
  ) tt
  WHERE name_part NOT IN (select name_part from io.citybr_stop_words)
        AND length(name_part)>2  -- THRESHOLD: 1-letter and 2-letter are ambigous
;

----------
----- LIB:

CREATE FUNCTION io.setvar (text,text)  RETURNS text AS $f$
  BEGIN
    IF $2 IS NOT NULL AND $2>'' THEN
      EXECUTE format(E'UPDATE io.prompt SET %s=\'%s\'', $1,$2);
      RETURN 'valor alterado.';
    ELSE
      RETURN 'valor mantido.';
    END IF;
  END;
$f$ LANGUAGE plpgsql;

-- --
CREATE FUNCTION io.import_export(p_mode text, p_doit text DEFAULT 'y') RETURNS text AS $f$
  DECLARE
    e record;
  BEGIN
    p_doit := substr(lower(p_doit),1,1);
    IF p_doit='s' OR p_doit='y' THEN
      FOR e IN SELECT * FROM io.prompt_list LOOP
        IF e.useit THEN
          IF p_mode='import' THEN
            EXECUTE format(E'DELETE FROM io.%s', e.tref);
            EXECUTE format(E'COPY io.%s FROM \'%s\' CSV HEADER', e.tref, e.f);
            RAISE NOTICE 'tabela io.% IMPORTADA com sucesso.', e.tref;
          ELSE
            EXECUTE format(E'COPY (SELECT * FROM io.vwexp_%s) TO \'%s\' CSV HEADER', e.tref, e.ffinal);
            RAISE NOTICE 'tabela io.% EXPORTADA com sucesso para % .', e.tref, e.ffinal;
            RAISE NOTICE '(check by "diff -w % data/%.csv")', e.ffinal, e.fbase;
          END IF;
        END IF;
      END LOOP;
      return '-- concluído --';
    ELSE
    return '... ignorando ...';
    END IF;
  END;
$f$ LANGUAGE plpgsql;

--------------
----- PROCESS:

CREATE FUNCTION io.passo2_proc(text)  RETURNS text AS $f$
  BEGIN
  CASE $1
      WHEN '0' THEN RETURN 'OK, nada';
      WHEN '1' THEN
        INSERT INTO io.citybr_syn SELECT * FROM io.citybr_new_synonym;
        RETURN 'inserindo apelidos válidos';
      ELSE RETURN 'FALHOU: valor de opçao desconhecido';
  END CASE;
  END;
$f$ LANGUAGE plpgsql;
