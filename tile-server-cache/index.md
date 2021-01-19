# Production PostGIS Vector Tiles: Caching

Building maps that use dynamic tiles from the database is a lot of fun: you get the freshest data, you don't have to think about generating a static tile set, and you can do it with very minimal middleware, using [pg_tileserv](https://info.crunchydata.com/blog/crunchy-spatial-tile-serving).

However, the day comes when it's time to move your application from development to production, what kinds of things should you be thinking about?

Let's start with **load**. A public-facing site has potentially unconstrained load. PostGIS is [fast at generating vector tiles](https://rmr.ninja/2020-11-19-waiting-for-postgis-3-1-mvt/), 

<img src="https://docs.google.com/drawings/d/e/2PACX-1vThk5xK5zEfmipUZNk1JHA3tpd667YRCudmL5qTNsKPZY3RQsIsw-veGm2JR1P3fY2p1rRITrcL6Ta0/pub?w=676&h=210" />

One way to deal with load is to scale out horizontally, using something like the [postgres operator](https://github.com/CrunchyData/postgres-operator) to control auto-scaling. But that is kind of a blunt instrument.

<img src="https://docs.google.com/drawings/d/e/2PACX-1vTkpaK1rsgbFQcFYmPd_thXwifkwlmIBH2AVJO_uLYsSo8fOHL0JgGwvixThNuwCddZrDX03sLwYBbw/pub?w=682&h=277" />

A far better way to insulate from load is with a caching layer. While building tiles from the database offers access to the freshest data, applications rarely need completely live date. One minute, five minute, even thirty minutes or a day old data can be suitable depending on the use case.

<img src="https://docs.google.com/drawings/d/e/2PACX-1vRjpBEKkpw2F1BgxTk34MqT9obfLVmq9xh9-kAOdjxPG7IolOclY0SkfPebZsGroHPdLwZLUSHmiIq0/pub?w=827&h=211" />

A simple, standard HTTP proxy cache is the simplest solution, here's an example using just containers and docker compose the places a proxy cache between a dynamic tile service and the public web.

I used [Docker Compose](https://docs.docker.com/compose/) to hook together the community [pg_tileserv](https://github.com/crunchydata/pg_tileserv) container with the community varnish container to create a cached tile service, here's the annotated file.

First some boiler plate and a definition for the internal network the two containers will communicate over.

```
version: '3.3'

networks:
  webapp:
```

The services section has two entries. The first entry configures the varnish service, accepting connections on port 80 for tiles and 6081 for admin requests. 

Note the "time to live" for cache entries is set to 600 seconds, five minutes. The "backend" points to the "tileserv" service, on the usual unsecured port.

```
services:
  web:
    image: eeacms/varnish
    ports:
      - "80:6081"
    environment:
      BACKENDS_PROBE_INTERVAL: "15s"
      BACKENDS_PROBE_TIMEOUT: "5s"
      BACKENDS_PROBE_WINDOW: "3"
      BACKENDS: "tileserv:7800"
      DNS_ENABLED: "false"
      DASHBOARD_USER: "admin"
      DASHBOARD_PASSWORD: "admin1234"
      DASHBOARD_SERVERS: "web"
      PARAM_VALUE: "-p default_ttl=600"
    networks:
      - webapp
    depends_on:
      - tileserv
```

The second service entry is for the tile server, it's got one port range, and binds to the same network as the cache. Because pg_tileserv is set up with out-of-the-box defaults, we only need to provide a `DATABASE_URL` to hook it up to the source database, which in this case is an instance on the [Crunchy Bridge](https://www.crunchydata.com/products/crunchy-bridge/) DBaaS.

```
  tileserv:
    image: pramsey/pg_tileserv
    ports:
      - "7800:7800"
    networks:
      - webapp
    environment:
      - DATABASE_URL=postgres://postgres:password@p.uniquehosthash.db.postgresbridge.com:5432/postgres
```

Does it work! Yes, it does. Point your browser at the cache and simultaneously watch the logs on your tile server. After a quick run of populating the common tiles, you'll find your tile server gets quiet, as the cache takes over the load.

<blockquote class="twitter-tweet"><p lang="en" dir="ltr">This <a href="https://twitter.com/MapScaping?ref_src=twsrc%5Etfw">@mapscaping</a> interview with <a href="https://twitter.com/pwramsey?ref_src=twsrc%5Etfw">@pwramsey</a> about pg_tileserv was really useful. Best info? Adding a cache with 60s expiry reduced compute almost to zero (in a previous situation). Thanks, <a href="https://twitter.com/bogind2?ref_src=twsrc%5Etfw">@bogind2</a>! <a href="https://t.co/rzyU3DOHdD">https://t.co/rzyU3DOHdD</a></p>&mdash; Tom Chadwin (@tomchadwin) <a href="https://twitter.com/tomchadwin/status/1351512779245674496?ref_src=twsrc%5Etfw">January 19, 2021</a></blockquote> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script> 

If your scale is too high for a single cache server like varnish, consider adding yet another caching layer, by putting a [content delivery network](https://en.wikipedia.org/wiki/Content_delivery_network) (CDN) in front of your services.






Dynamic Vector Tiles from PostGIS

One of the most popular features of PostGIS 2.5 was the introduction of the "vector tile" output format, via the [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) function.

Vector tiles are a transport format for efficiently sending map data from a server to a client for rendering. The [vector tile specification](https://docs.mapbox.com/vector-tiles/specification/) describes how raw data are quantized to a grid and then compressed using delta-encoding to make a very small package.

Prior to [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html), if you wanted to produce vector tiles from PostGIS you would use a rendering program ([MapServer](https://mapserver.org), [GeoServer](htts://geoserver.org), or [Mapnik](htts://mapnik.org)) to read the raw data from the database, and process it into tiles.

## Minimal Tile Architecture

With [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) it is now possible to move all that processing into the database, which opens up the possibility for very lightweight tile services that do little more than convert map tile requests into SQL for the database engine to execute.

![architecture](img/architecture.png)

There are already several examples of such light-weight services.

* [Dirt-Simple PostGIS HTTP API](https://github.com/tobinbradley/dirt-simple-postgis-http-api)
* [Postile](https://github.com/Oslandia/postile)
* [Martin](https://github.com/urbica/martin)

However, for learning purposes, here's a short example that builds up a tile server and map client from scratch. 

* [Minimal MVT Server](https://github.com/pramsey/minimal-mvt)

This minimal tile server is in Python, but there's no reason you couldn't execute one in any language you like: it just has to be able to connect to PostgreSQL, and run as an HTTP service.

## What are Tiles

A digital map is theoretically capable of viewing data at any scale, and for any region of interest. Map tiling is a way of constraining the digital mapping problem, just a little, to vastly increase the speed and efficiency of map display. 

* Instead of supporting any scale, a tiled map only provides a limited collection of scales, where each scale is a factor of two more detailed than the previous one.
* Instead of rendering data for any region of interest, a tiled map only renders it over a fixed grid within the scale, and composes arbitrary regions by displaying appropriate collections of tiles.

![map tiles](img/tilePyramid.jpg)

Most tile maps divide the world by starting with a single tile that encompasses the entire world, and calls that "zoom level 0". From there, each succeeding "zoom level" increases the number of tiles by a factor of 4 (twice as many vertically and twice and many horizontally).

## Tile Coordinates

Any tiles in a tiled map can be addressed by referencing the zoom level it is on, and its position horizontally and vertically in the tile grid.  The commonly used "XYZ" addressing scheme counts from zero, with the origin at the top left.

This example is for zoom level 2 (`2^zoom = 4` tiles per size).

![tile coorinates](img/tileCoordinates.png)

The web addresses of tiles in the "XYZ" scheme embed the "zoom", "x" and "y" coordinates into a web address: `http://server/{z}/{x}/{y}.format`

For example, you can see the tile that encompasses Australia  (zoom=2, x=3, y=2) in the tilesets of a number of map providers:

* https://tile.openstreetmap.org/2/3/2.png
* http://a.basemaps.cartocdn.com/light_all/2/3/2.png
* http://a.tile.stamen.com/toner/2/3/2.png

## ST_AsMVTGeom() and ST_AsMVT()

Building a map tile involves feeding data through not one, but two PostGIS functions: 

* [ST_AsMVTGeom()](https://postgis.net/docs/ST_AsMVTGeom.html)
* [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html)

Vector features in a MVT map tile are highly processed, and the [ST_AsMVTGeom()](https://postgis.net/docs/ST_AsMVTGeom.html) performs that processing:

* clip the features to the tile boundary;
* translate from cartesian coordinates (relative to geography) to image coordinates (relative to top left of image); 
* remove extra vertices that will not be visible at tile resolution; and,
* quantize coordinates from double precision to the tile resolution in integers.

So any query to generate MVT tiles will involve a call to [ST_AsMVTGeom()](https://postgis.net/docs/ST_AsMVTGeom.html) to condition the data first, something like:

```sql
SELECT ST_AsMVTGeom(geom) AS geom, column1, column2
FROM myTable
```

The MVT format can encode both geometry and attribute information, in fact that is one of the things that makes it so useful: client-side interactions can be much richer when both attributes and shapes are available on the client. 

In order to create tiles with geometry and attributes, [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) function takes in a record type. So SQL calls that create tiles end up looking like this:

```sql
SELECT ST_AsMVT(mvtgeom.*)
FROM (
  SELECT ST_AsMVTGeom(geom) AS geom, column1, column2
  FROM myTable
) mvtgeom
```

We'll see this pattern again as we build out the SQL queries generated by the tile server.

## Tile Server

The job of our [minimal web tile server](https://github.com/pramsey/minimal-mvt/blob/master/minimal-mvt.py) is to convert from tile coordinates, to a SQL query that creates an equivalent vector tile.

First the [pathToTile](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L36-L45) function strips out the x, y and z components from the request.

![architecture](img/pathToTile.png)

Then [tileIsValid](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L48-L60) confirms that the values make sense. Each zoom level can only have tile coordinates between `0` and `2^zoom - 1` so we check that values are in range.

![architecture](img/tileIsValid.png)

"XYZ" tile maps are usually in a projection called "[spherical mercator](https://epsg.io/3857)" that has the nice property of forming a neat square, about 40M meters on a side, over (most of) the earth at zoom level zero. 

![architecture](img/tileToEnv.png)

From that square starting point, [tileToEnvelope](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L48-L60) subdivides it to to find the size of a tile at the requested zoom level, and then the coordinates of the tile in the mercator projection.

![architecture](img/tileToEnv2.png)

Now we can start constructing the SQL to generate the MVT format tile. First with [envelopeToBoundsSQL](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L84-L91) converts our envelope in python into SQL that will generate an equivalent envelope in the database we can use to query and clip the raw data.

![architecture](img/boundsToSql.png)

With the bounds SQL we are now ready to calculate the full MVT-generating SQL statement in [envelopeToSQL](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L94-L116):

```sql
WITH 
bounds AS (
    SELECT {env} AS geom, 
           {env}::box2d AS b2d
),
mvtgeom AS (
    SELECT ST_AsMVTGeom(ST_Transform(t.{geomColumn}, 3857), bounds.b2d) AS geom, 
           {attrColumns}
    FROM {table} t, bounds
    WHERE ST_Intersects(t.{geomColumn}, ST_Transform(bounds.geom, {srid}))
) 
SELECT ST_AsMVT(mvtgeom.*) FROM mvtgeom
```

And finally run the SQL against the database in [sqlToPbf](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L119-L137) and return the MVT as a byte array.

That's it! The main HTTP [do_GET](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/minimal-mvt.py#L140-L159) callback for the script just runs those functions in order and sends the result back.

```python
    # Handle HTTP GET requests
    def do_GET(self):

        tile = self.pathToTile(self.path)
        if not (tile and self.tileIsValid(tile)):
            self.send_error(400, "invalid tile path: %s" % (self.path))
            return

        env = self.tileToEnvelope(tile)
        sql = self.envelopeToSQL(env)
        pbf = self.sqlToPbf(sql)

        self.log_message("path: %s\ntile: %s\n env: %s" % (self.path, tile, env))
        self.log_message("sql: %s" % (sql))
        
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-type", "application/vnd.mapbox-vector-tile")
        self.end_headers()
        self.wfile.write(pbf)
```

Now we have a python client we can run that will convert HTTP tile requests into MVT-tile responses directly from the database.

```
http://localhost:8080/4/3/4.mvt
```

## Map Client

Now that tiles are published, we can add our live tile layer to any web map that supports MVT format. Two of the most popular are

* [OpenLayers](https://openlayers.org), and
* [Mapbox GL JS](https://docs.mapbox.com/mapbox-gl-js/overview/).

Map clients convert the state of a map windows into HTTP requests for tiles to fill up a map window. If you've used a modern web map, like Google Maps, you've used a standard web map -- they all work the same way.

![architecture](img/openlayers.png)

### OpenLayers

The [OpenLayers](https://openlayers.org) map client has been built out using the [NPM](https://www.npmjs.com/) module system, and can be installed into an NPM development environment as easily as:

```
npm install ol
```

The [example OpenLayers map for this post](https://github.com/pramsey/minimal-mvt/tree/master/map-openlayers) combines a standard raster base layer with an [active layer](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/map-openlayers/index.js#L13-L25) from a PostgreSQL database accessed via our tile server.

```js
var vtLayer = new VectorTileLayer({
  declutter: false,
  source: new VectorTileSource({
    format: new MVT(),
    url: 'http://localhost:8080/{z}/{x}/{y}.pbf'
  }),
  style: new Style({
      stroke: new Stroke({
        color: 'red',
        width: 1
      })
  })
});
```

### Mapbox GL JS

The [Mapbox GL JS](https://docs.mapbox.com/mapbox-gl-js/overview/) is more tightly bound to the Mapbox ecosystem, but can be run without using Mapbox services or a Mapbox API key.

The [example Mapbox map for this post](https://github.com/pramsey/minimal-mvt/blob/8b736e342ada89c5c2c9b1c77bfcbcfde7aa8d82/map-mapboxgl/index.html#L35-L40) can be run directly without any special development steps. The main challenge in composing a map with Mapbox GL JS is understanding the [style language](https://docs.mapbox.com/mapbox-gl-js/style-spec) that is used to specify both map composition and the styling of vector data in the map.




