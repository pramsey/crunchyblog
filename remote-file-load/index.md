
# Holy Sheet! Remote Access CSV Files from Postgres

An extremely common problem in fast-moving data architectures is providing a way to feed ad hoc user into into an existing analytical data system. 

Do you have time to whip up a web app? No! You have a database to feed, and events are spiraling out of control... what to do?

How about a Google Sheet? The data layout is obvious, you can even enforce things like data types and required columns using locking and protecting, and unlike an Excel or LibreOffice document, it's always online, so you can hook the data into your system directly.

## Access Sheets Data Remotely

You can pull data in CSV format from a (public) Google Sheets workbook just by plugging the sheet ID into a magic access URL. 

The URL format looks like this:

```
https://docs.google.com/spreadsheets/d/{sheetId}/gviz/tq?tqx=out:csv&sheet={sheetName}
```

The `sheetId` you can pull out of the URL at the top of your browser. The `sheetName` is at the bottom of the page. You can read one sheet at a time out of a Sheets workbook.

This example sheet has 22 rows of population projection data in it.

```
curl "https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections"

"Year","18 to 19","Total"
"2024","120107","5485084"
"2025","123484","5563798"
"2026","128627","5641925"
"2027","132540","5719109"
"2028","134067","5796302"
...
```

## Remote Access with COPY

The following examples all use the [Crunchy Bridge](https://crunchybridge.com/) database-as-a-service. Not all services will support these methods. 

To use the `COPY` command for remote loading you will first need to create a table to load the data into. Our table structure is just three integer columns.

```sql
CREATE TABLE popn_copy (
year integer,
age_18_to_19 integer,
all_ages integer
);
```

We are going to use the `PROGRAM` option of copy to fire up the `curl` utility and pull the CSV data from Google, then stream that into the default PostgreSQL CSV reader.

In order to use `COPY` with the `PROGRAM` option you must be logged in as the `postgres` superuser.

```sql
COPY popn_copy FROM PROGRAM 
'curl "https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections"'
WITH ( 
 FORMAT csv,
 HEADER true,
 ENCODING utf8
 );
```

Just like that, 22 rows loaded! 

```sql
SELECT Count(*) FROM popn_copy;
```

The `COPY` approach is really the simplest one available, and to refresh your data, you can just run a scheduled `TRUNCATE` and then re-run the `COPY`.

However, it does have the disadvantage of requiring a superuser login.


## Remote Access with HTTP

The [http extension](https://github.com/pramsey/pgsql-http) for PostgreSQL allows users to run web requests and fetch data from any URL. Sounds like exactly what we need!

You can check if you have the extension by querying the `pg_available_extensions` table.

```sql
SELECT * 
  FROM pg_available_extensions 
  WHERE name = 'http';
```

```
name              | http
default_version   | 1.5
installed_version | 
comment           | HTTP client for PostgreSQL, allows web page retrieval inside the database.
```

If you have it, enable the `http` extension, and create a target table:

```sql
CREATE EXTENSION http;

CREATE TABLE popn_http (
year integer,
age_18_to_19 integer,
all_ages integer
);
```

If we use the `http_get()` function, we can pull the content from the remote URL in one step.

```sql
SELECT content AS row 
FROM http_get('https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections')
```

What we get back is all the data, but in **one big string**. We would **prefer** 22 rows of data. Fortunately, PostgreSQL string processing can help us condition the data before inserting it into our table.

First, cut the string up using new-line characters as a delimiter.

```sql
SELECT unnest(string_to_array(content, E'\n')) AS row 
FROM http_get('https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections')
```

Now we have 23 rows (22 data rows and one header row), which we can parse the numeric pieces out of using `regexp_match()`:

```sql
INSERT INTO popn_http
WITH rows AS (
  SELECT unnest(string_to_array(content, E'\n')) AS row 
  FROM http_get('https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections')
),
cols AS (
  SELECT regexp_match(row, '"([0-9]+)","([0-9]+)","([0-9]+)"') AS col FROM rows
)
SELECT col[1]::integer AS year, 
       col[2]::integer AS age_18_to_19, 
       col[3]::integer AS all_ages 
  FROM cols
 WHERE col[1] IS NOT NULL
```

Whenever you want to refresh, just `TRUNCATE` the table and re-run the population query. Unlike the `COPY` method, this doesn't require super-user access to implement.


## Remote Access with FDW

Our last remote access trick uses a "[foreign data wrapper](https://www.postgresql.org/docs/current/ddl-foreign-data.html)", specifically the [OGR FDW](https://github.com/pramsey/pgsql-ogr-fdw/) which exposes the multi-format access capabilities of the [GDAL](https://gdal.org) library to PostgreSQL.

While this example shows CSV file reading, the [OGR FDW](https://github.com/pramsey/pgsql-ogr-fdw/) extension can be used to access a [huge number of different formats](https://gdal.org/drivers/vector/index.html), both local and remote. 

The hardest part of using the OGR FDW driver is figuring out the correct server string to use in setting up the connection. It is best to start by [downloading a copy of GDAL](https://gdal.org/download.html) to your workstation and trying out various options using the `ogrinfo` tool.

With some trial and error, I found that a working URL involved:

* using the `vsicurl` remote access driver (check out the other "[virtual file system](https://gdal.org/user/virtual_file_systems.html)" drivers provided to get a feel for just how flexible GDAL is for remote data access), 
* prepending `CSV` to hint to GDAL what format driver to use, and
* appending `&/popn` to the URL to trick GDAL into using "popn" as the layer name instead of something much less attractive.

The result can connect to the remote source and understand the CSV file contents.

```
ogrinfo CSV:"/vsicurl/https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections&/popn" 

INFO: Open of `CSV:/vsicurl/https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections&/popn'
      using driver `CSV' successful.
1: popn (None)
```

For most sources, like remote databases and so on, the URL will be a lot simpler and obvious. Even a remote CSV file will usually be easier, because it will have a CSV file name at the end of the URL, which GDAL uses to hint the correct driver.

```
CREATE SERVER myserver
  FOREIGN DATA WRAPPER ogr_fdw
  OPTIONS (
    datasource 'CSV:/vsicurl/https://docs.google.com/spreadsheets/d/1pBbCabAK6u6EIuyu_2XUul4Yxvf2w_Od6QYC_yEc4q4/gviz/tq?tqx=out:csv&sheet=Population_projections&/popn',
    format 'CSV');
```

Now that we have a "server", we can import the one layer that exists in that server. 

If our server was something more sophisticated, like a database, there could potentially be multiple tables that would be imported using this method.

```sql
CREATE SCHEMA fdw;

IMPORT FOREIGN SCHEMA ogr_all
	FROM SERVER myserver
	INTO fdw;

SELECT * FROM fdw.popn;
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

We have data! Unfortunately, since it is coming from a text csv file, without any column type mapping, we need to do a little bit of type coersion to get a clean table of integers.

```sql
CREATE MATERIALIZED VIEW popn_fdw AS 
  SELECT year::integer      AS year, 
         n18_to_19::integer AS age_18_to_19, 
         total::integer     AS all_ages
  FROM fdw.popn;
```

Using a materialized view keeps our database from constantly hitting the remote table every time we access the FDW table. Since we have a materialized view, the refresh method is a little prettier than truncating and reloading, though it is effectively the same thing: just refresh the view.

```sql
REFRESH MATERIALIZED VIEW popn_fdw;
```

As with the `http` approach and unlike using `COPY`, the FDW approach does not require a superuser to do the refresh step.

## Conclusions

* There are lots of ways to access remote data! 
  * Using `COPY` with `PROGRAM` is simple but requires superuser powers and only reads CSV.
  * Using the `http` extension is simple to get data but requires parsing it yourself on the database side.
  * Using the `ogr_fdw` extension involves some fiddly setup but is nice and clean once it is up and running. It can also read vastly more different file formats and data services.


