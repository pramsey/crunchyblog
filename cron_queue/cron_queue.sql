
CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS addresses;
CREATE TABLE addresses (
  pk serial PRIMARY KEY,
  address text,
  city text,
  geom geometry(Point, 4326),
  geocode jsonb
);

CREATE INDEX addresses_geom_x ON addresses USING GIST (geom);

INSERT INTO addresses (address, city)
  VALUES ('1650 Chandler Avenue', 'Victoria'),
         ('122 Simcoe Street', 'Victoria');


-- procedure
-- collect the pk of all ids with null geom
-- loop through that list and call geocode(pk)
-- geocode(pk) use http to call google api

SET gmaps.api_key = 'AIzaSyAZNxVr6T9KH_yTS7s8e1xQ1DzqxR4xn9c';
ALTER DATABASE http SET gmaps.api_key = 'AIzaSyAZNxVr6T9KH_yTS7s8e1xQ1DzqxR4xn9c';

--
-- Take a primary key for a row, get the address string
-- for that row, geocode it, and update the geometry
-- and geocode columns with the results.
--
DROP FUNCTION IF EXISTS addresses_geocode;
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

DROP PROCEDURE process_address_geocodes;
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


-- SET client_min_messages = debug;
-- SELECT * FROM addresses;
-- SELECT addresses_geocode(1);
-- CALL address_geocode_batch();

--SELECT cron.schedule_in_database('process-geocodes', '15 seconds', 'CALL process_address_geocodes()', 'http');
