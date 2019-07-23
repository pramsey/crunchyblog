# Waiting for PostGIS 3: ST_AsGeoJSON(record)

With PostGIS 3.0, it is now possible to generate GeoJSON features directly without any intermediate code, using the new `ST_AsGeoJSON(record)`` function.

The [GeoJSON format](https://tools.ietf.org/html/rfc7946) is a common transport format, between servers and web clients, and even between components of processing chains. Being able to create useful GeoJSON is important for integrating different parts in a modern geoprocessing application.

PostGIS has had an `ST_AsGeoJSON(geometry)` for forever, but it does slightly less than most users really need: it takes in a PostGIS geometry, and outputs a GeoJSON "[geometry object](https://tools.ietf.org/html/rfc7946#section-3.1)".

The GeoJSON geometry object is just the shape of the feature, it doesn't include any of the other information about the feature that might be included in the table or query. As a result, developers have spent a lot of time writing boiler-plate code to wrap the results of `ST_AsGeoJSON(geometry)`` up with the columns of a result tuple to create GeoJSON "[feature objects](https://tools.ietf.org/html/rfc7946#section-3.2)".

The `ST_AsGeoJSON(record)`` function looks at the input tuple, and takes the first column of type geometry to convert into a GeoJSON geometry. The rest of the columns are added to the GeoJSON features in the properties member.

```sql
SELECT ST_AsGeoJSON(subq.*) AS geojson 
FROM ( 
  SELECT ST_Centroid(geom), type, admin 
  FROM countries 
  WHERE name = 'Canada' 
) AS subq
```
```json
{"type": "Feature", 
 "geometry": { 
    "type":"Point", 
    "coordinates":[-98.2939042718784,61.3764628013483] 
  }, 
  "properties": { 
    "type": "Sovereign country", 
    "admin": "Canada" 
  } 
}
```
Using GeoJSON output it's easy to stream features directly from the database into an [OpenLayers](https://openlayers.org/en/latest/examples/geojson.html) or [Leaflet](https://leafletjs.com/examples/geojson/) web map, or to consume them with [ogr2ogr](https://openlayers.org/en/latest/examples/geojson.html) for conversion to other geospatial formats.