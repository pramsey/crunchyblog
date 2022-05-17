# Instant Heatmap with pg_featureserv

The [pg_featureserv](https://github.com/crunchydata/pg_featureserv) micro-service is a thin middleware that binds tables and functions in a PostgreSQL database to a JSON collections API, accessible over HTTP. 

## Application

The application uses PostgreSQL to store and search 2.2M geographic names in the USA. Type in the search box and the auto-fill form will find candidate words. Select a word, and the database will perform a full-text search for all the names that match your work, and return the result to the map. The map displays the result using a heat map.

<img src="img/heatmap.gif" width="100%" />

More names closer together will get more vibrant colors, so you can see name density. Try some regional names: **bayou**, **swamp**, **cherokee**, **baptist**, **cougar**. **[Try it for yourself](http://s3.cleverelephant.ca/geonames-lookup.html)**.


## Architecture

Using [pg_featureserv](https://github.com/crunchydata/pg_featureserv) to build a demonstration application is pretty easy all you need is:

* PostgreSQL running somewhere
* `pg_featureserv` running somewhere
* A web page hosted somewhere.

What, "running somewhere" is doing a lot of work here! Is there any way to do this without become a specialist in managing database and container ops?

Yes, we can do all the heavy lifting with [Crunchy Bridge](https://crunchybridge.com)! 

* Crunchy Bridge hosts the database.
* [Crunchy Bridge container apps](https://docs.crunchybridge.com/container-apps/) host the `pg_featureserv` microservice and a `varnish` web cache.
* Static web page goes anywhere that can hold a static web page (S3 in this case).

<img src="img/architecture.jpg" style="max-width: 600px" />

## Prepare the Data

We will build a small web application that can visualize the location of named places in the United States. This is far more interesting than it sounds, because named places carry a lot of **local history and context** with them, and that context shows up in maps!

Start by downloading the US named places.

```bash
wget https://download.geonames.org/export/dump/US.zip
unzip US.zip
```

For added security, we will connect our `pg_featureserv` microservice using an application account, and make a separate database for the application.

```sql
-- as postgres
CREATE DATABASE geonames WITH OWNER = application;
```

Then create a table to receive the data and load it up.

<details><summary>Create Table and Copy</summary>

```sql
CREATE TABLE geonames (
    geonameid      integer primary key,
    name           text,
    asciiname      text,
    alternatenames text,
    latitude       float8,
    longitude      float8,
    featureclass   text,
    featurecode    text,
    countrycode    text,
    countrycode2   text,
    admin1         text,
    admin2         text,
    admin3         text,
    admin4         text,
    population     bigint,
    elevation      integer,
    dem            integer,
    timezone       text,
    modified       date
);

\copy geonames FROM 'US.txt' WITH (
    FORMAT csv, 
    DELIMITER E'\t', 
    HEADER false, 
    ENCODING utf8)

```

</details>


## Create Indexes

There are 2.2M named places in the database, and we want to very quickly find names that match our query word. Often the named are multi-word ("Gold River", "West Gold Hills") and we will be searching with just one word. This is where full-text search indexing comes in handy.

Full-text indexes can only be built on a `tsvector` type. We can either add a new `tsvector` column to our table, and then populate it, or save a little space and just build a functional index on the `tsvector` construction function.

```sql
CREATE INDEX geonames_name_x 
   ON geonames 
   USING GIN (to_tsvector('english', name))
```

The drop-down form fill needs a list of unique name components, preferably in order of frequency, so "interesting" ones appear at the top of the list. We build that by stripping down and aggregating all the names in the table.

```sql
CREATE TABLE geonames_stats AS 
    SELECT 
      count(*) AS ndoc, 
      unnest(regexp_split_to_array(lower(trim(name)), E'[^a-zA-Z]')) AS word 
    FROM geonames GROUP BY 2;

CREATE INDEX geonames_stats_word_x ON geonames_stats (word text_pattern_ops);
```


## Create Functions to Publish

The web map application needs an HTTP API to connect to, this is where `pg_featureserv` comes in. We will create two functions: 

* One to drive the dropdown form field, which takes the characters currently typed and finds all matching words.
* One to drive the map, which takes in the query word and returns all matching place names.

The magic power of `pg_featureserv` is in the ability to publish [user defined functions](https://access.crunchydata.com/documentation/pg_featureserv/latest/usage/functions/). 

**Any function defined in the `postgisftw` schema will be published as a web end point.**

<details><summary>Define a function to populate the dropdown form field.</summary>

```sql
CREATE SCHEMA postgisftw;

DROP FUNCTION IF EXISTS postgisftw.geonames_stats_query;

CREATE FUNCTION postgisftw.geonames_stats_query(
    q text DEFAULT 'bea')
RETURNS TABLE(value text, ndoc bigint)
AS $$
BEGIN
    RETURN QUERY
        SELECT g.word as value, g.ndoc
        FROM geonames_stats g
        WHERE g.word LIKE q || '%'
        ORDER BY g.ndoc DESC
        LIMIT 15;
END;
$$
LANGUAGE 'plpgsql'
PARALLEL SAFE
STABLE
STRICT;
```

</details>

<details><summary>Define a function to query for place names.</summary>

```sql
DROP FUNCTION IF EXISTS postgisftw.geonames_query;

CREATE FUNCTION postgisftw.geonames_query(q text DEFAULT 'beach')
RETURNS TABLE(name text, featureclass text, longitude float8, latitude float8)
AS $$
BEGIN
    RETURN QUERY
        SELECT 
            g.name, 
            g.featureclass, 
            g.longitude,
            g.latitude
        FROM geonames g
        WHERE to_tsvector('english', g.name) @@ plainto_tsquery('english', q)
        ORDER BY md5(g.name)
        LIMIT 10000;
END;
$$
LANGUAGE 'plpgsql'
PARALLEL SAFE
STABLE
STRICT;
```

</details>

## Run the Microservices

Our architecture uses two microservices: `pg_featureserv` to publish the database functions as web services; and `varnish` to protect the feature service from excessive load if the application gets a lot of traffic.

<img src="img/architecture.jpg" style="max-width: 600px" />

These services are run as [Crunchy Bridge Container Apps](https://docs.crunchybridge.com/container-apps/) using an extension called `pgpodman`.

```sql
CREATE EXTENSION pgpodman;
```

Once the extension is enabled, the containers can be turned on. This involves some magic strings, primarily the DNS name of the database host, which is available in the connection strings, and also in the container apps user interface.

Run the `pg_featureserv` container.

```sql
SELECT run_container('
    -dt -p 5442:9000/tcp 
    --log-driver k8s-file 
    --log-opt max-size=1mb 
    -e DATABASE_URL="postgres://application:password@p.xxxxxxxxxxxx.db.postgresbridge.com:5432/geonames" 
    -e PGFS_SERVER_HTTPPORT=9000  
    -e PGFS_PAGING_LIMITDEFAULT=10000 
    -e PGFS_PAGING_LIMITMAX=10000 
    docker.io/pramsey/pg_featureserv:latest');
```

(Newlines are inserted into this example so you can see how the parameters are passed to the container. Environment variables to configure the service are passed in with `-e`.)

Run the `varnish` container.

```sql
SELECT run_container('
    -dt -p 5435:6081/tcp 
    --log-driver k8s-file 
    --log-opt max-size=1mb 
    -e BACKENDS=p.fhlzf432a5gmvaj456jql4a4di.db.postgresbridge.com:5442 
    -e DNS_ENABLED=false 
    -e COOKIES=true 
    -e PARAM_VALUE="-p default_ttl=3600" 
    docker.io/eeacms/varnish:latest');
```

The `varnish` container is the "outward facing" service, so web requests should come into port 5435, where they will be passed to the varnish process inside the container on port 6081. Then `varnish` will call out to its `BACKEND` host (`pg_featureserv`) this time on port 5442, which in turn is proxied into port 9000 inside the container.

### Try it Manually

Once the services are running, you can hit them manually from the outside.

```bash
http://hostname:5435/functions/geonames_query/items.json?q=cougar
http://hostname:5435/functions/geonames_stats_query/items.json?q=cougar
```










