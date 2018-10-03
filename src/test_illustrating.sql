
 CREATE FUNCTION ROUND(float,int) RETURNS NUMERIC AS $$
    SELECT ROUND($1::numeric,$2);
 $$ language SQL IMMUTABLE;


DROP AGGREGATE IF EXISTS array_agg_cat(anyarray);
CREATE AGGREGATE array_agg_cat(anyarray) (
  SFUNC=array_cat,
  STYPE=anyarray,
  INITCOND='{}'
);

CREATE OR REPLACE FUNCTION ST_box2d_array(p_bbox box2d) RETURNS float[] AS $f$
  SELECT array_agg(x::float)
  FROM regexp_split_to_table(
        trim(substr( (SELECT p_bbox::text) , 5 ),')'),
        '[ ,]'
  ) t(x)
$f$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION ST_Extent_array(p_geom geometry) RETURNS float[] AS $wrap$
  -- to simplify non-aggregate queries.
  SELECT ST_box2d_array( ST_extent(p_geom) )
$wrap$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION ST_Extent_geohash(
  p_geom geometry,   -- input to get BBOX
  p_len int DEFAULT 0, -- number of digits
  p_srid int DEFAULT NULL  -- tranform in other coordinate system, when negative use to set.
) RETURNS text[] AS $f$
  SELECT  array_agg(g)
  FROM (
        SELECT ST_GeoHash(geom,p_len) g
        FROM ST_DumpPoints( ST_Envelope(CASE
            WHEN p_srid IS NULL OR p_srid=0 THEN p_geom
            WHEN p_srid<0 THEN ST_setsrid(p_geom,abs(p_srid))
            ELSE ST_Transform(p_geom,p_srid)
          END) ) t0
        LIMIT 4
  ) t
$f$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION ST_Extent_jsonb(
  -- Prefer to use to_jsonb(ST_Extent_array(geom)) or box2d().
  -- This function is only to check ST_Envelope()
  p_geom geometry,   -- input to get BBOX
  p_round_lat int DEFAULT NULL, -- decimal places to round latitude (0, 1, 2, ...)
  p_round_lon int DEFAULT NULL, -- decimal places to round longitude (0, 1, 2, ...)
  p_srid int DEFAULT NULL  -- tranform in other coordinate system
) RETURNS JSONb AS $f$
  SELECT  jsonb_build_object('minlat',u[2], 'minlon',u[1], 'maxlat',u[4], 'maxlon',u[5])
  FROM (
    SELECT array_agg_cat( array[
        CASE WHEN p_round_lon IS NULL THEN x ELSE round(x::numeric,p_round_lon)::float END,
        CASE WHEN p_round_lat IS NULL THEN y ELSE round(y::numeric,p_round_lat)::float END
    ] ) u
    FROM (
        SELECT st_x(geom) x, st_y(geom) y
        FROM ST_DumpPoints(ST_Envelope(CASE WHEN p_srid IS NULL THEN p_geom ELSE ST_Transform(p_geom,p_srid) END)) t0
        LIMIT 3
      ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;


-----

CREATE OR REPLACE FUNCTION geojson_sanitize( p_j  JSONb, p_srid int DEFAULT 4326) RETURNS geometry AS $f$
  -- as https://gis.stackexchange.com/a/60945/7505
  SELECT g FROM (
   SELECT  ST_GeomFromGeoJSON(g::text)
   FROM (
   SELECT CASE
    WHEN p_j IS NULL OR p_j='{}'::JSONb OR jsonb_typeof(p_j)!='object'
        OR NOT(p_j?'type')
        OR  (NOT(p_j?'crs') AND (p_srid<1 OR p_srid>998999) )
        OR p_j->>'type' NOT IN ('Feature', 'FeatureCollection', 'Position', 'Point',
        'MultiPoint', 'LineString', 'MultiLineString', 'Polygon',
        'MultiPolygon', 'GeometryCollection')
        THEN NULL
    WHEN NOT(p_j?'crs')  OR 'EPSG0'=p_j->'crs'->'properties'->>'name'
        THEN p_j || ('{"crs":{"type":"name","properties":{"name":"EPSG:'|| p_srid::text ||'"}}}')::jsonb
    ELSE p_j
    END
   ) t2(g)
   WHERE g IS NOT NULL
  ) t(g)
  WHERE ST_IsValid(g)
$f$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION read_geojson(
  p_path text,
  p_ext text DEFAULT '.geojson',
  p_basepath text DEFAULT '/opt/gits/city-codes/data/dump_osm/'::text,
  p_srid int DEFAULT 4326
) RETURNS geometry AS $f$
  SELECT CASE WHEN length(s)<30 THEN NULL ELSE geojson_sanitize(s::jsonb) END
  FROM  ( SELECT readfile(p_basepath||p_path||p_ext) ) t(s)
$f$ LANGUAGE SQL IMMUTABLE;

-----


CREATE OR REPLACE FUNCTION get_srname(p_srid int, p_reduce int default 0) RETURNS text AS $f$
   SELECT trim( (regexp_matches(srtext,CASE
      WHEN $2=1 THEN 'PROJCS\["[^"]*/([^"]+)"'
      WHEN $2=2 THEN 'PROJCS\["[^"]*/\s*UTM zone\s*([^"]+)"'
      ELSE 'PROJCS\["([^"]+)"' END
   ))[1] )
   FROM spatial_ref_sys
   WHERE srid=$1
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION get_utmzone(
  p_geom geometry(POINT)
) RETURNS integer AS $f$
  SELECT CASE
    WHEN p_geom IS NULL OR GeometryType(p_geom) != 'POINT' THEN NULL
    ELSE floor((ST_X(p_geom)+180.0)/6.0)::int
         + CASE WHEN ST_Y(p_geom)>0.0 THEN 32601 ELSE 32701 END
    END
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION get_utmzone_bydump(p_geom geometry) RETURNS integer[] AS $f$
  SELECT array_agg( DISTINCT get_utmzone(geom) )
  FROM ST_DumpPoints( p_geom )
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION get_utmzone_names(p_geom geometry, p_type int DEFAULT 2) RETURNS text[] AS $wrap$
  SELECT array_agg(get_srname(x,p_type)) FROM unnest(get_utmzone_bydump(p_geom)) t(x)
$wrap$ LANGUAGE SQL IMMUTABLE;

----

-- depends on io.citybr


DROP TABLE test_city;
-- CREATE TABLE IF NOT EXISTS test_city AS
CREATE TABLE test_city AS
   select *,
   round(km2_bb/km2,2) as km2_ratio,  round(sqrt(4*km2/pi()),2) diam, round(sqrt(km2_bb),2) bb_square_side,
   ST_GeoHash(CASE WHEN km2>300 THEN st_buffer(geom,-0.001) ELSE geom END) geohash_envelop,
   ST_Geohash(geom_center,12) geohash_center
from (
 SELECT *, st_area(geom,true)/1000000.0 km2,
        st_area(ST_Envelope(geom),true)/1000000.0 km2_bb,
        bbox_bounds(geom) bounds,
        ST_PointOnSurface(geom) geom_center,
        get_utmzone_bydump(geom) as utm_zone_srid
 FROM (
	 SELECT *, read_geojson(path) as geom
	 FROM (
	   select state||'/'||lib.initcap_sep("lexLabel",true) as path,*
	   from io.citybr
	 ) t
 ) t2
 WHERE  ST_IsValid(geom)
) tt
;


-- select path from  test_city where name like 'Abadia%' limit 20;
--st_astext(geom) from test_city;

--select path, utm_zone_srid, bounds from test_city;


-- select path, round(km2_bb/km2,2) as km2_ratio,  round(sqrt(4*km2/pi()),2) diam, round(sqrt(km2_bb),2) bb_square_side from   test_city;



/*
geom_bbox_max
geom_bbox_max


CREATE OR REPLACE FUNCTION bounds(

*/
