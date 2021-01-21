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

<blockquote class="twitter-tweet"><p lang="en" dir="ltr">This <a href="https://twitter.com/MapScaping?ref_src=twsrc%5Etfw">@mapscaping</a> interview with <a href="https://twitter.com/pwramsey?ref_src=twsrc%5Etfw">@pwramsey</a> about pg_tileserv was really useful. Best info? Adding a cache with 60s expiry reduced compute almost to zero (in a previous situation). Thanks, <a href="https://twitter.com/bogind2?ref_src=twsrc%5Etfw">@bogind2</a>! <a href="https://t.co/rzyU3DOHdD">https://t.co/rzyU3DOHdD</a></p>&mdash; Tom Chadwin (@tomchadwin) <a href="https://twitter.com/tomchadwin/status/1351512779245674496?ref_src=twsrc%5Etfw">January 19, 2021</a></blockquote><script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script> 

If your scale is too high for a single cache server like varnish, consider adding yet another caching layer, by putting a [content delivery network](https://en.wikipedia.org/wiki/Content_delivery_network) (CDN) in front of your services.


