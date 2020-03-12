wget http://download.osgeo.org/livedvd/data/osm/Boston_MA/Boston_MA.osm.bz2
osm2pgrouting --password centos --host 127.0.0.1 --username centos --dbname routing --file Boston_MA.osm


CREATE VIEW vehicle_net AS
    SELECT gid,
        source,
        target,
        -- converting to minutes
        cost_s / 60 AS cost,
        reverse_cost_s / 60 AS reverse_cost,
        the_geom
    FROM ways JOIN configuration AS c
    USING (tag_id)
    WHERE  c.tag_value NOT IN ('steps','footway','path');

    