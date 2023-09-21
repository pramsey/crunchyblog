

# Remote Access Anything from Postgres

In my [last blog post](), I showed four ways to access a remotely hosted CSV file from inside PostgreSQL:

* Using the `COPY` command with the `PROGRAM` option,
* Using the [http extension](https://github.com/pramsey/pgsql-http/) and some post-processing, 
* Using a PL/Python function, and
* Using the [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) foreign data wrapper.

In this post, we are going to explore [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) a little more deeply.


## So Many Formats

The [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) extension gets its magical format access powers by linking to the [GDAL](htts://gdal.org) library. 

[GDAL](htts://gdal.org) is a widely used library in the geospatial world, but as is frequently the case the needs of geospatial users have a large overlap with the needs of everyone else. 

GDAL is an abstraction layer that allows programs to access [dozens of formats and services](https://gdal.org/drivers/vector/index.html) using a single API. 

The GDAL abstraction is that a "connection" might contain multiple "layers", and "layers" consist of "records" each of which is made up of multiple typed columns. The column types are things like "integer", "string", "float" and "date". 

Does this sound familiar? The GDAL API is describing a database, with a connection to the service, and tables available within. The PostgreSQL FDW abstraction also has a "server" and "tables" and manages access to "rows" (aka "tuples") with typed columns.



## Connecting

Turning on [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) in [Crunchy Bridge](https://crunchybridge.com) is easy, just run:

```sql
CREATE EXTENSION ogr_fdw;
```

The tricky part of using [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) is figuring out the connection string for your data. I like to do this outside the database, using the `ogrinfo` tool, rather than trying to debug the correct string inside the database. You can get `ogrinfo` by [downloading a build of GDAL](https://gdal.org/download.html) for your workstation.


## "Virtual File Systems"

Having a lot of formats is GDAL's first super power. The second is the concept of the "[virtual file system](https://gdal.org/user/virtual_file_systems.html)". Virtual file systems allow you to access files and directory structures that are not necessarily local to your copy of GDAL, while retaining the semantics of local access.

We will be using the `/vsicurl/` virtual file system, which allows access to remote resources via URL. (The "curl" part is a reference to the popular [curl library](https://curl.se/libcurl/) used by GDAL in the implementation of the feature.)

Note some of the other virtual file systems available:

* `vsizip` for reading out of zip files
* `vsis3` for reading from AWS S3 buckets with many options
* `vsihdfs` for reading from HadoopFS

Also note that you can combine systems! So it's possible to read the contents of a remote zip file in an S3 bucket, directly, by combining the `vsis3` and `vsizip` systems.


## Google Sheets CSV

In our [last blog](https://gdal.org/download.html), we connected to a live Google Sheet, and pulled the data directly into the database via a CSV URL, the FDW setup looked like this:

```sql
CREATE SERVER myserver
  FOREIGN DATA WRAPPER ogr_fdw
  OPTIONS (
    datasource 'CSV:/vsicurl/https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections&/popn',
    format 'CSV');

CREATE SCHEMA fdw_csv;

IMPORT FOREIGN SCHEMA ogr_all
  FROM SERVER myserver
  INTO fdw_csv;

SELECT * FROM fdw_csv.popn;
```
```
 fid | year | n18_to_19 |  total  
-----+------+-----------+---------
   1 | 2024 | 120107    | 5485084
   2 | 2025 | 123484    | 5563798
   3 | 2026 | 128627    | 5641925
   4 | 2027 | 132540    | 5719109
   5 | 2028 | 134067    | 5796302
...
```


## S3 XLSX File

GDAL can read other tabular formats too, and other cloud storage systems. Passing data between systems via [S3](https://aws.amazon.com/s3/) is pretty common, and you can use the [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) to pull those files too.

I have put a sample file at curl http://s3.cleverelephant.ca/SampleData.xlsx. The bucket is 's3.cleverelephant.ca' and the object is 'SampleData.xlsx'.

The `/vsis3/` driver has a [huge number of possible configuration options](https://gdal.org/user/virtual_file_systems.html#vsis3-aws-s3-files), and we need two of them for this example: one to turn off request signing since it is a public bucket, and one to specify the AWS region.

```
AWS_NO_SIGN_REQUEST=YES AWS_REGION=us-west-2 ogrinfo /vsis3/s3.cleverelephant.ca/SampleData.xlsx

INFO: Open of `/vsis3/s3.cleverelephant.ca/SampleData.xlsx'
      using driver `XLSX' successful.
1: Instructions (None)
2: SalesOrders (None)
3: MyLinks (None)
```

The SQL to set up the FDW is the usual.

```sql
CREATE SERVER s3_server
  FOREIGN DATA WRAPPER ogr_fdw
  OPTIONS (
    datasource '/vsis3/s3.cleverelephant.ca/SampleData.xlsx',
    config_options 'AWS_NO_SIGN_REQUEST=YES AWS_REGION=us-west-2',
    format 'XLSX');

CREATE SCHEMA IF NOT EXISTS fdw_s3;

IMPORT FOREIGN SCHEMA ogr_all
  FROM SERVER s3_server
  INTO fdw_s3;

SELECT * FROM fdw_s3.salesorders
WHERE region = 'East';
```
```
 fid | orderdate  | region |  rep   |  item   | units | unit_cost |  total  
-----+------------+--------+--------+---------+-------+-----------+---------
   2 | 2021-01-06 | East   | Jones  | Pencil  |    95 |      1.99 |  189.05
   7 | 2021-04-01 | East   | Jones  | Binder  |    60 |      4.99 |   299.4
  11 | 2021-06-08 | East   | Jones  | Binder  |    60 |      8.99 |   539.4
...
```


## HTTP SQLite File

GDAL isn't restricted just to spreadsheet style files, it can also read into more complex files, like SQLite database files.

For example, there is a SQLite example file at https://www.sqlitetutorial.net/wp-content/uploads/2018/03/chinook.zip 

Note that the file is both **remote** and **zipped**. Fortunately, in addition to `/vsicurl/` for the HTTP request, GDAL also provides us with `/vsizip/` to treat a zip file as a virtual directory. 

We can test our access as usual with `ogrinfo`, combining the `/vsicurl/` and `/vsizip/` virtual file systems. 

```
ogrinfo /vsizip/vsicurl/https://www.sqlitetutorial.net/wp-content/uploads/2018/03/chinook.zip/chinook.db

INFO: Open of `/vsizip/vsicurl/https://www.sqlitetutorial.net/wp-content/uploads/2018/03/chinook.zip/chinook.db'
      using driver `SQLite' successful.
1: albums (None)
2: artists (None)
3: customers (None)
4: employees (None)
5: genres (None)
6: invoice_items (None)
7: invoices (None)
8: media_types (None)
9: playlist_track (None)
10: playlists (None)
11: sqlite_sequence (None) [private]
12: sqlite_stat1 (None) [private]
13: tracks (None)
```

Now we set up the FDW, using that same GDAL connection string.

```sql
CREATE SERVER sqlite_server
  FOREIGN DATA WRAPPER ogr_fdw
  OPTIONS (
    datasource '/vsizip/vsicurl/https://www.sqlitetutorial.net/wp-content/uploads/2018/03/chinook.zip/chinook.db',
    format 'SQLite');

CREATE SCHEMA IF NOT EXISTS fdw_sqlite;

IMPORT FOREIGN SCHEMA ogr_all
  FROM SERVER sqlite_server
  INTO fdw_sqlite;

SELECT * 
FROM fdw_sqlite.albums 
WHERE title ~ '^Ar';
```
```
 fid |                       title                        | artistid 
-----+----------------------------------------------------+----------
 120 | Are You Experienced?                               |       94
 168 | Arquivo II                                         |      113
 169 | Arquivo Os Paralamas Do Sucesso                    |      113
 319 | Armada: Music from the Courts of England and Spain |      251
```

## Conclusions

* The [ogr_fdw](https://github.com/pramsey/pgsql-ogr-fdw/) extension provides flexible access to remote data in [dozens of formats]((https://gdal.org/drivers/vector/index.html).
* When using FDW for real-time access it is frequently wise to place a `MATERIALIZED VIEW` between your queries and the FDW, to avoid network latency.




