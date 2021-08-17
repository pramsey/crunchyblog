# Waiting for PostGIS 3.2: Secure cloud raster access

Raster data access from the spatial database is an important feature, and the coming release of PostGIS will make remote access more practical, by allowing access to private cloud storage.

Previous versions could access rasters in public buckets, which is fine for writing [blog posts](https://blog.crunchydata.com/blog/postgis-raster-and-crunchy-bridge), but in the real world people frequently store their data in private buckets, so we clearly needed the ability to add security tokens to our raster access.

## Raster in the database? or raster via the database?

Putting rasters in a database is not necessarily a good idea: 

* they take up a lot of space; 
* they don't fit the relational model very well; 
* they are generally static and non-transactional; 
* when they are updated they are updated in bulk.

However, **accessing** rasters **from** a database is a powerful tool:

* rasters provide lots of contextual information (weather, modelling outputs, gradient surfaces);
* rasters can model continuous data in a way points, lines and polygons cannot;
* raster access via SQL abstracts away format and language differences in the same way that vector access does.

PostGIS has long supported both models, raster **in** the database, and raster **from** the database. Raster **in** the database is called "in-db" and raster **from** the database is called "out-db".

## Filesystem vs cloud

The "out-db" model was built before the advent of cloud storage, and the expectation was that external rasters would reside on a file system to which the postgres system would have read/write access. In order to abstract away issues of file format, the "out-db" model did not access files directly, but instead used the [GDAL](https://gdal.org) raster format access library. 

With the rise of cloud storage options, the GDAL library began adding support for reading and writing from cloud objects via HTTP. This sounds amazingly inefficient, and while it is surely slower than direct file-system access, the combination of HTTP support for direct byte-range access and very fast network speed inside cloud data centers makes it practical -- if your processing system is running on a cloud compute node in the same data center as your object is stored, performance can be perfectly reasonable.

The improved capability of GDAL to access cloud rasters has meant that the original PostGIS "out-db" model has transparently been upgraded from a "local filesystem" model to a "cloud access" model, with almost no effort on our part. Instead of accessing "out-db" files with a file-system path, we access cloud files with a URL, and GDAL does the rest.

## Tile sizes and out-db

The raster model in PostGIS initially was built for in-db work, and has a key assumption that raster data will be broken up into relatively small chunks. This makes sense on a number of levels, since small chunks will join more efficiently to (similarly small) vector objects, and small chunks will stay within the PostgreSQL page size, which is also more efficient.

For out-db work, the core model of chopping up inputs into smaller chunks still applies, but the most efficient chunking size is no longer dictated by the internal PostgreSQL page size, instead it is driven by the internal tiling of the external raster.

In our blog post on [contouring using raster](https://blog.crunchydata.com/blog/waiting-for-postgis-3.2-st_contour-and-st_setz) we deliberately loaded our raster tables of elevation using a tile size that matched the internal tiling of the remote raster.

## Out-db rasters

A given raster file will be chunked into a collection of smaller raster objects in the database, what is in those rasters, given that the actual data lives remotely?

You can see the contents by using some of the raster metadata functions.

```
SELECT (ST_Metadata(rast)).* 
FROM dem 
WHERE rid = 1;

-[ RECORD 1 ]----------------------
upperleftx | -123.00013888888888
upperlefty | 50.00013888888889
width      | 512
height     | 512
scalex     | 0.0002777777777777778
scaley     | -0.0002777777777777778
skewx      | 0
skewy      | 0
srid       | 4326
numbands   | 1
```

The basic raster metadata provides the geometry of the tile: where it is in space (upperleft), what its pixel size is (scale), how large it is (width/height) and the spatial reference system. This tile is an elevation tile with just one band.

```
SELECT (st_bandmetadata(rast)).* 
FROM dem 
WHERE rid = 1;

-[ RECORD 1 ]-+------------------------
pixeltype     | 16BSI
nodatavalue   | -32768
isoutdb       | t
path          | /vsicurl/https://opentopography.s3.sdsc.edu/raster/SRTM_GL1/SRTM_GL1_srtm/N49W123.tif
outdbbandnum  | 1
filesize      | 18519816
filetimestamp | 1610506326
```

The band metadata is very interesting! It includes the external reference location of the file, the band number in that file to read from, the pixel type, and even a time stamp.

The path is the most interesting. This is the "file name" that GDAL will read to access the data. If the file were just a sitting on a local file system, the path would be as simple as `/RTM_GL1_srtm/N49W123.tif`. 

Since the file is remote, we flag the fact that we want GDAL to access it with a "[virtual file system](https://gdal.org/user/virtual_file_systems.html)", particularly the HTTP vir the HTTP access method, `/vsicurl/`.

In addition to plain HTTP access, GDAL provides custom [virtual network file systems](https://gdal.org/user/virtual_file_systems.html#network-based-file-systems) for a wide variety of cloud providers: 

* AWS S3
* Google Cloud Storage
* Azure 
* Alibaba OSS
* OpenStack Swift
* Hadoop HDFS

Using these file systems is as simple as changing the `vsicurl` in an access URL to `vsis3`, except for one quirk: where to put the authentication information needed to access private objects?

## Security and GDAL network virtual file systems

With PostGIS 3.2, it is possible to [pass virtual file system parameters to GDAL](http://postgis.net/docs/manual-dev/using_raster_dataman.html#RT_Cloud_Rasters) using the `postgis.gdal_vsi_options` local variable. 

The option can be set in a configuration file, but for security reasons, it is best to set the value at run-time in your session, or even better within a single transactional context.

When loading data into a secured bucket, you will need to supply credentials. The GDAL configuration options `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` can be supplied as environment variables in the raster loading script (assuming your raw file is already uploaded to `/vsis3/your.bucket.com/your_file.tif`:

```
AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx \
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
raster2pgsql \
  -s 4326 \
  -t 512x512 \
  -I \
  -R \
  /vsis3/your.bucket.com/your_file.tif \
  your_table \
  | psql your_db
```

Once loaded into the database, you can only access the rasters if your session has the same GDAL configuration options set, in the `postgis.gdal_vsi_options` variable.

```sql
SET postgis.gdal_vsi_options = 'AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

SELECT rast FROM mytable LIMIT 1;
```

Note that the multiple options are set by providing space-separate "key=value" pairs. 

Each different GDAL cloud filesystem has different configuration options for security, so check out [the documentation](http://postgis.net/docs/manual-dev/using_raster_dataman.html#RT_Cloud_Rasters) for the service you are using.

Using `SET` to put the authentication tokens into your connection means they will be around until you disconnect. For situations where you are connecting via a pool, like pgbouncer, you may want to minimize the amount of time the tokens are available by using `SET LOCAL` within a transaction:

```sql
BEGIN;
SET LOCAL postgis.gdal_vsi_options = 'AWS_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
SHOW postgis.gdal_vsi_options;
SELECT rast FROM mytable LIMIT 1;
COMMIT;
SHOW postgis.gdal_vsi_options;
```

Using `SET LOCAL` the `postgis.gdal_vsi_options` value only persists for the life of the transaction and then reverts to its pre-transaction state. 

## Conclusions

* The PostGIS "out-db" raster capability can support remote rasters in the cloud, as well as local rasters on the file-system.
* The GDAL "[virtual file system](https://gdal.org/user/virtual_file_systems.html#network-based-file-systems)" feature has support for numerous cloud storage providers.
* PostGIS 3.2 raster now has support for [extra cloud provider functionality](http://postgis.net/docs/manual-dev/using_raster_dataman.html#RT_Cloud_Rasters, including authentication, via the `postgis.gdal_vsi_options` value. 





