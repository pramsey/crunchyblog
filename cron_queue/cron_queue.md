
# Running an Async Web Query Queue with Procedures and pg_cron

The number of cool things you can do with the [http extension](https://github.com/pramsey/pgsql-http) is large, but putting those things into production raises an important problem.

**The amount of time an HTTP request takes, 100s of miliseconds, is 10- to 20-times longer that the amount of time a normal database query takes.**

This means that potentially an HTTP call could jam up a query for a long time. I recently ran an HTTP function in an update against a relatively small 1000 record table.

The query took 5 minutes to run, and during that time the table was locked to other access, since the update touched every row.

This was fine for me on my developer database on my laptop. In a production system, it would **not be fine**.

## Geocoding, For Example

A really common table layout in a spatially enabled enterprise system is a table of addresses with an associated location for each address.

```sql
CREATE EXTENSION postgis;

CREATE TABLE addresses (
  pk serial PRIMARY KEY,
  address text,
  city text,
  geom geometry(Point, 4326),
  geocode jsonb
);

CREATE INDEX addresses_geom_x 
  ON addresses USING GIST (geom);

INSERT INTO addresses (address, city)
  VALUES ('1650 Chandler Avenue', 'Victoria'),
         ('122 Simcoe Street', 'Victoria');
```

New addresses get inserted without known locations. The system needs to call an external geocoding service to get locations.

```sql
SELECT * FROM addresses;
```
```
 pk |       address        |   city   | geom | geocode 
----+----------------------+----------+------+---------
  8 | 1650 Chandler Avenue | Victoria |      | 
  9 | 122 Simcoe Street    | Victoria |      | 
```

When a new address is inserted into the system, it would be great to geocode it. A trigger would make a lot of sense, but a trigger will run in the same transaction as the insert. So the insert will block until the geocode call is complete. **That could take a while.** If the system is under load, inserts will pile up, all waiting for their geocodes.

## Procedures to the Rescue

A better performing approach would be to insert the address right away, and then **come back later and geocode any rows that have a NULL geometry**.

The key to such a system is being able to work through all the rows that need to be geocoded, **without locking** those rows for the duration. Fortunately, there is a PostgresSQL feature that does what we want, the [PROCEDURE](https://www.postgresql.org/docs/current/sql-createprocedure.html)

Unlike **functions**, which wrap their contents in a single, atomic transaction, **procedures** allow you to apply multiple commits while the procedure runs. This makes them perfect for long-running batch jobs, like our geocoding problem. 

```sql
CREATE PROCEDURE process_address_geocodes()
LANGUAGE plpgsql
AS $$
DECLARE
  pk_list BIGINT[];
  pk BIGINT;
BEGIN
    
  SELECT array_agg(addresses.pk)
    INTO pk_list
    FROM addresses
    WHERE geocode IS NULL;
 
  IF pk_list IS NOT NULL THEN
    FOREACH pk IN ARRAY pk_list LOOP
      PERFORM addresses_geocode(pk);
      COMMIT;
    END LOOP;
  END IF;

END;
$$;

```

The important thing is to break the work up so it is done one row at a time. Rather than running a single `UPDATE` to the table, we find all the rows that need geocoding, and loop through them, one row at a time, committed our work after each row.

## Geocoding Function

The `addresses_geocode(pk)` function takes in a row primary key and then geocodes the address using the [Google Maps Geocoding API](https://developers.google.com/maps/documentation/geocoding/overview). Taking in the primary key, instead of the address string, allows us to call the function one-at-a-time on each row in our working set of rows.

The function:

* reads the Google API key from the environment
* reads the address string for the row
* sends the geocode request to Google using the [http](https://github.com/pramsey/pgsql-http) extension
* checks the validity of the response
* updates the row

Each time through the function is atomic, so the controlling procedure can commit the result as soon as the function is complete. 

<details><summary>Geocoding function addresses_geocode(pk)</summary>

```sql
--
-- Take a primary key for a row, get the address string
-- for that row, geocode it, and update the geometry
-- and geocode columns with the results.
--
CREATE FUNCTION addresses_geocode(geocode_pk bigint)
RETURNS boolean
LANGUAGE 'plpgsql'
AS $$
DECLARE
  js jsonb;
  full_address text;
  res http_response;
  api_key text;
  api_uri text;
  uri text := 'https://maps.googleapis.com/maps/api/geocode/json';
  lat float8;
  lng float8;

BEGIN

  -- Fetch API key from environment
  api_key := current_setting('gmaps.api_key', true);

  IF api_key IS NULL THEN
      RAISE EXCEPTION 'addresses_geocode: the ''gmaps.api_key'' is not currently set';
  END IF;

  -- Read the address string to geocode
  SELECT concat_ws(', ', address, city) 
    INTO full_address
    FROM addresses 
    WHERE pk = geocode_pk
    LIMIT 1;

  -- No row, no work to do
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Prepare query URI
  js := jsonb_build_object(
          'address', full_address,
          'key', api_key
        );
  uri := uri || '?' || urlencode(js);

  -- Execute the HTTP request
  RAISE DEBUG 'addresses_geocode: uri [pk=%] %', geocode_pk, uri;
  res := http_get(uri);

  -- For any bad response, exit here, leaving all
  -- entries NULL
  IF res.status != 200 THEN
    RETURN false;
  END IF;

  -- Parse the geocode
  js := res.content::jsonb;

  -- Save the json geocode response
  RAISE DEBUG 'addresses_geocode: saved geocode result [pk=%]', geocode_pk;
  UPDATE addresses 
    SET geocode = js 
    WHERE pk = geocode_pk;

  -- For any non-usable geocode, exit here, 
  -- leaving the geometry NULL
  IF js->>'status' != 'OK' OR js->'results'->>0 IS NULL THEN
    RETURN false;
  END IF;

  -- For any non-usable coordinates, exit here      
  lat := js->'results'->0->'geometry'->'location'->>'lat';
  lng := js->'results'->0->'geometry'->'location'->>'lng';
  IF lat IS NULL OR lng IS NULL THEN
    RETURN false;
  END IF;

  -- Save the geocode result as a geometry
  RAISE DEBUG 'addresses_geocode: got POINT(%, %) [pk=%]', lng, lat, geocode_pk;
  UPDATE addresses 
    SET geom = ST_Point(lng, lat, 4326)
    WHERE pk = geocode_pk;

  -- Done
  RETURN true;

END;
$$;
```

</details>

## Deploy with pg_cron

We have all the parts of a geocoding engine:

* a **function** to geocode a row; and, 
* a **procedure** that finds rows that need geocoding. 

What we need now is a way to run that procedure regularly, and fortunately there is a very standard way to do that in PostgreSQL: [pg_cron](https://github.com/citusdata/pg_cron).

If you install and enable `pg_cron` in the usual way, in the `postgres` database, new jobs must be added from inside the `postgres` database, using the `cron.schedule_in_database()` function to target other databases.

```sql
-- Schedule our procedure in the "geocode_example_db" database
SELECT cron.schedule_in_database(
  'geocode-process',                 -- job name
  '15 seconds',                      -- job frequency
  'CALL process_address_geocodes()', -- sql to run
  'geocode_example_db'               -- database to run in
  ));
```

Wait, **15 seconds** frequency? What if a process takes more than 15 seconds, won't we end up with a stampeding herd of procedure calls? Fortunately no, `pg_cron` is smart enough to check and defer if a job is already in process. So there's no major downside to calling the procudure fairly frequently.

## Conclusion

* HTTP and AI and BI rollup calls can run for a "long time" relative to desired database query run-times
* PostgreSQL `PROCEDURE` calls can be used to wrap up a collection of long running functions, putting each into an individual transaction to lower locking issues
* `pg_cron` can be used to deploy those long running procedures, to keep the database up-to-date while keeping load and locking levels reasonable

