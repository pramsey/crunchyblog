DROP TABLE IF EXISTS geonames;
CREATE TABLE geonames (
geonameid integer,
name text,
asciiname text,
alternatenames text,
latitude float8,
longitude float8,
fclass char,
fcode text,
country text,
cc2 text,
admin1 text,
admin2 text,
admin3 text,
admin4 text,
population bigint,
elevation integer,
dem text,
timezone text,
modification date,
geom geometry(point, 5070) 
	GENERATED ALWAYS AS 
		(ST_Transform(ST_Point(longitude, latitude, 4326),5070)) STORED
);

\copy geonames FROM 'US.txt' WITH (FORMAT CSV, DELIMITER E'\t', HEADER false)

CREATE INDEX geonames_geom_x ON geonames USING GIST (geom);

DROP TABLE IF EXISTS geonames_stm;
CREATE TABLE geonames_stm AS 
SELECT ST_ClusterDBScan(geom, 5000, 5) OVER (PARTITION BY admin1) AS cluster, * FROM geonames WHERE fcode = 'STM';


DROP TABLE IF EXISTS geonames_sch;
CREATE TABLE geonames_sch AS 
SELECT ST_ClusterDBScan(geom, 2000, 5) OVER (PARTITION BY admin1) AS cluster, * FROM geonames WHERE fcode = 'SCH';


SELECT DISTINCT cluster FROM geonames_stm;