CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE SCHEMA IF NOT EXISTS lib;

/**
 * Transforms a string into InitCap of each part, using separator as reference.
 * Example: 'hello my.best-friend' with ' -' sep will be 'Hello My.best-Friend'.
 * No other change in the string. Uses '_*reserv__' as reserved word.
 * Se also ltxtquery() for @ comparing.
 */
CREATE FUNCTION lib.initcap_sep(text,text DEFAULT '\s\.:;,',boolean DEFAULT false) RETURNS text AS $f$
  SELECT array_to_string(array_agg(initcap(x)),'')
  FROM regexp_split_to_table(
     regexp_replace($1, '(['||$2||']+)', CASE WHEN $3 THEN '_*reserv__' ELSE '_*reserv__\1' END,'g'),
     '_\*reserv__'
  ) t(x)
$f$ language SQL IMMUTABLE;

CREATE FUNCTION lib.initcap_sep(text,boolean,text DEFAULT '\s\.:;,') RETURNS text AS $wrap$
  SELECT lib.initcap_sep($1,$3,$2)
$wrap$ language SQL IMMUTABLE;

CREATE or replace FUNCTION read_geojson(
  p_path text,
  p_ext text DEFAULT '.geojson',
  p_basepath text DEFAULT '/opt/gits/city-codes/data/dump_osm/'
) RETURNS text AS $f$
   -- WHEN s='file not found' NULL
  SELECT CASE WHEN length(s)<30 THEN NULL ELSE  s END
  FROM  ( SELECT readfile(p_basepath||p_path||p_ext) ) t(s)
$f$ language SQL IMMUTABLE;


-- See issue #11
-- ORDER BY std_collate(name), name, state
CREATE or replace FUNCTION std_collate(
  -- ver
   p_name text, p_syn_type text DEFAULT NULL
) RETURNS text AS $f$
    SELECT CASE
     WHEN $2 IS NULL THEN '0'
     WHEN substr($2,1,11)='alt canonic' OR substr($2,1,11)='alt oficial' THEN '1'
     WHEN substr($2,1,3)='err' THEN '8'
     ELSE '5'
   END ||  regexp_replace(p_name, E'[ \'\-]', '0', 'g')
$f$ language SQL IMMUTABLE;

CREATE or replace FUNCTION cepmask_fromrange(p_x1 text, p_x2 text) RETURNS text AS $f$
  SELECT CASE
    WHEN dif='' THEN rpad(pfx, 8, '.') -- 1668 cases
    WHEN dif='4999' THEN rpad(pfx_h, 7, '.') --  1522 cases
    WHEN dif='1999' THEN rpad(pfx, 8, '.') -- 706
    WHEN dif='2999' THEN rpad(pfx, 8, '.') -- 487
    WHEN dif='19999' THEN rpad(pfx, 8, '.') -- 261
    WHEN dif='8' THEN rpad(pfx, 8, '.') -- 111
    WHEN dif='29999' THEN rpad(pfx, 8, '.') -- 86
  END
  FROM (
    SELECT prefix, length(prefix), regexp_replace((p_x2::bigint - p_x1::bigint)::text, '^9+', '', 'g'), prefix||'#'
    FROM ( SELECT extract_common_prefix(p_x1,p_x2) ) t(prefix)
  ) t(pfx,pfx_len,dif,pfx_h)
$f$ language SQL IMMUTABLE;


CREATE or replace FUNCTION extract_common_prefix(text,text) RETURNS text AS $f$
-- usada para capturar prefixos de intervamos de CEP, e outros.
DECLARE
  i int;
  l1 int;
  l2 int;
  x text;
BEGIN
  l1 :=length($1);
  l2 :=length($2);
  FOR i IN REVERSE (CASE WHEN l1>l2 THEN l2 ELSE l1 END)..1
  LOOP
    x := substr($1,1,i);
    IF x=substr($2,1,i) THEN return x; END IF;
  END LOOP;
  RETURN '';
END;
$f$ LANGUAGE plpgsql;


-- -- -- -- -- --
-- Normalize and convert to integer-ranges, for postalCode_ranges.
-- See section "Preparation" at README.

CREATE or replace FUNCTION csvranges_to_int4ranges(
  p_range text
) RETURNS int4range[] AS $f$
   SELECT ('{'||
      regexp_replace( translate($1,' -',',') , '\[(\d+),(\d+)\]', '"[\1,\2]"', 'g')
   || '}')::int4range[];
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION int4ranges_to_csvranges(
  p_range int4range[]
) RETURNS text AS $f$
   SELECT translate($1::text,',{}"',' ');
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- -- -- --
-- EXTRAS from https://github.com/datasets-br/diariosOficiais/blob/master/src/step1_strut.sql


CREATE or replace FUNCTION name2lex(
  p_name text,
  p_normalize boolean DEFAULT true
) RETURNS text AS $f$
   SELECT trim(replace(
	   regexp_replace(
	     CASE WHEN p_normalize THEN unaccent(lower($1)) ELSE $1 END,
	     E' d[aeo] | d[oa]s | com | para |^d[aeo] | [aeo]s | [aeo] |d\'|[\-\' ]', -- | / .+
	     '.',
	     'g'
	   ),
	   '..',
           '.'
       ),'.')
$f$ LANGUAGE SQL IMMUTABLE;


/**
 * Base36 integer conversion.
 * @see https://gist.github.com/btbytes/7159902
 */
CREATE or replace FUNCTION base36_encode(IN digits bigint, IN min_width int = 0) RETURNS varchar AS $$
DECLARE
    chars char[];
    ret varchar;
    val bigint;
BEGIN
    chars := array['0','1','2','3','4','5','6','7','8','9',
      'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z'
    ];
    val := digits;
    ret := '';
    IF val < 0 THEN
        val := val * -1;
    END IF;
    WHILE val != 0 LOOP
        ret := chars[(val % 36)+1] || ret;
        val := val / 36;
    END LOOP;

    IF min_width > 0 AND char_length(ret) < min_width THEN
        ret := lpad(ret, min_width, '0');
    END IF;

    RETURN ret;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE or replace FUNCTION br_city_id_gap(text) RETURNS int AS $f$
-- Gap maximo de 10 conforme convenção códigos IBGE, e em função do nome da cidade. Avaliação de balanço inspirada pela raiz quadrada:
-- SELECT json_build_object(i,s) from (select substr(unaccent(name),1,1) as i, count(*) as n, sqrt(count(*))::int as s
--    from tmpcsv_cities_wiki group by 1 order by 2 desc) t;

	SELECT CASE WHEN jgap->ini IS NULL THEN 3 ELSE (jgap->>ini)::int END
	FROM
	(SELECT upper(substr(unaccent($1),1,1)) as ini) t1,
	(SELECT '{"S":10,"C":10,"P":9,"A":8,"M":8,"I":8,"B":8,"T":6,"J":6,"R":6,"N":6,"G":6,"L":6,"F":4,"V":4,"D":4,"E":4,"O":4,"U":4}'::JSON as jgap) t2;
$f$ LANGUAGE SQL IMMUTABLE;
