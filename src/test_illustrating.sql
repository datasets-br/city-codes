
 CREATE FUNCTION ROUND(float,int) RETURNS NUMERIC AS $$
    SELECT ROUND($1::numeric,$2);
 $$ language SQL IMMUTABLE;


DROP AGGREGATE IF EXISTS array_agg_cat(anyarray);
CREATE AGGREGATE array_agg_cat(anyarray) (
  SFUNC=array_cat,
  STYPE=anyarray,
  INITCOND='{}'
);


CREATE OR REPLACE FUNCTION bbox_bounds(p_geom geometry) RETURNS float[] AS $f$
  -- see illustration at CLP project
  SELECT  jsonb_build_object('minlat',u[2], 'minlon',u[2], 'maxlat',u[4], 'maxlon',u[5])
  FROM (
    SELECT array_agg_cat( array[st_x(geom),st_y(geom)] ) u
    FROM ST_DumpPoints( ST_Envelope(p_geom) )
  ) t
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


----

-- depends on io.citybr


DROP TABLE test_city;
-- CREATE TABLE IF NOT EXISTS test_city AS
CREATE TABLE test_city AS
   select *, 
   round(km2_bb/km2,2) as km2_ratio,  round(sqrt(4*km2/pi()),2) diam, round(sqrt(km2_bb),2) bb_square_side
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
