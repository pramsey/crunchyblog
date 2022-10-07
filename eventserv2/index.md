# Real-time Mapping & Geofences with Postgres and pg_eventserv

In our [last post](https://www.crunchydata.com/blog/real-time-database-events-with-pg_eventserv), we introduced [pg_eventserv](https://github.com/crunchydata/pg_eventserv), and the concept of real-time web notifications generated from database actions.

In this post, we will dive into a practical use case: displaying state, calculating events, and tracking historical location for a set of **moving objects**.

![Screenshot](moving-object.jpg)

This demonstration uses [pg_eventserv](https://github.com/crunchydata/pg_eventserv) for eventing, and [pg_featureserv](https://github.com/crunchydata/pg_featureserv) for external web API, and [OpenLayers](https://openlayers.org) as the map API, to build a small example application that shows off the common features of moving objects systems.

[Try it out!](http://s3.cleverelephant.ca/mo/moving-objects.html)

## Features

Moving objects applications can be very complex or very simple, but they usually include a few common baseline features:

* A real-time view of the state of the objects.
* Live notifications when objects enter and leave a set of "[geofences](https://en.wikipedia.org/wiki/Geo-fence)".
* Querying the history of the system, to see where objects have been, and to summarize their state (eg, "truck 513 spent 50% of its time in the yard").


## Tables

The [model](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql) has three tables:

![Tables](moving-tables.jpg)

* [objects](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L29-L36) where the current location of hte objects is stored.
* [geofences](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L68-L73) where the geofences are stored.
* [objects_history](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L68-L73) where the complete set of all object locations are stored.


## Architecture (in brief)

From the outside, the system has the following architecture:

![Architecture](moving-architecture.jpg)

Changes to objects are communicated in via a web API backed by [pg_featureserv](https://github.com/crunchydata/pg_featureserv), those changes fires a bunch of triggers that generate events that [pg_eventserv](https://github.com/crunchydata/pg_eventserv) pushes out to listening clients via WebSockets.


## Architecture (in detail)

* The user interface generates object movements, via the arrow buttons for each object. This is in lieu of a real "moving object" fleet in the real world generating timestamped GPS tracks.

* Every movement click on the UI fires a call to a web API, which is just a function published via [pg_featureserv](https://github.com/crunchydata/pg_featureserv), `object_move(object_id, direction)`.

<details><summary>postgisftw.object_move(object_id, direction)</summary>

```sql
CREATE OR REPLACE FUNCTION postgisftw.object_move(
    move_id integer, direction text)
RETURNS TABLE(id integer, geog geography)
AS $$
DECLARE
  xoff real = 0.0;
  yoff real = 0.0;
  step real = 2.0;
BEGIN

  yoff := CASE
    WHEN direction = 'up' THEN 1 * step
    WHEN direction = 'down' THEN -1 * step
    ELSE 0.0 END;

  xoff := CASE
    WHEN direction = 'left' THEN -1 * step
    WHEN direction = 'right' THEN 1 * step
    ELSE 0.0 END;

  RETURN QUERY UPDATE moving.objects mo
    SET geog = ST_Translate(mo.geog::geometry, xoff, yoff)::geography,
        ts = now()
    WHERE mo.id = move_id
    RETURNING mo.id, mo.geog;

END;
$$
LANGUAGE 'plpgsql' VOLATILE;
```

</details>

* The `object_move(object_id, direction)` function just converts the "direction" parameter into a movement vector, and `UPDATES` the relevant row of the `objects` table.

* The change to the `objects` table fires off the `objects_geofence()` trigger, which calculates the fences the object is now in.

<details><summary>objects_geofence()</summary>
```sql
CREATE FUNCTION objects_geofence() RETURNS trigger AS $$
    DECLARE
        fences_new integer[];
    BEGIN
        -- Add the current geofence state to the input
        -- tuple every time.
        SELECT coalesce(array_agg(id), ARRAY[]::integer[])
            INTO fences_new
            FROM moving.geofences
            WHERE ST_Intersects(geofences.geog, new.geog);

        RAISE DEBUG 'fences_new %', fences_new;
        -- Ensure geofence state gets saved
        NEW.fences := fences_new;
        RETURN NEW;
    END;
$$ LANGUAGE 'plpgsql';
```
</details>

* The change to the `objects` table **then** fires off the `objects_update()` trigger, which:
  * Compares the current set of geofences to the previous set, and thus detects any enter/leave events.
  * Adds the new location of the object to the `objects_history` tracking table.
  * Composes the new location and any geofence events into a JSON object and puts it into the "objects" `NOTIFY` queue using `pg_notify()`.
  
<details><summary>objects_update()</summary>
```sql
CREATE FUNCTION objects_update() RETURNS trigger AS $$
    DECLARE
        channel text := 'objects';
        fences_old integer[];
        fences_entered integer[];
        fences_left integer[];
        events_json jsonb;
        location_json jsonb;
        payload_json jsonb;
    BEGIN
        -- Place a copy of the value into the history table
        INSERT INTO moving.objects_history (id, geog, ts, props)
            VALUES (NEW.id, NEW.geog, NEW.ts, NEW.props);

        -- Clean up any nulls
        fences_old := coalesce(OLD.fences, ARRAY[]::integer[]);
        RAISE DEBUG 'fences_old %', fences_old;

        -- Compare to previous fences state
        fences_entered = NEW.fences - fences_old;
        fences_left = fences_old - NEW.fences;

        RAISE DEBUG 'fences_entered %', fences_entered;
        RAISE DEBUG 'fences_left %', fences_left;

        -- Form geofence events into JSON for notify payload
        WITH r AS (
        SELECT 'entered' AS action,
            g.id AS geofence_id,
            g.label AS geofence_label
        FROM moving.geofences g
        WHERE g.id = ANY(fences_entered)
        UNION
        SELECT 'left' AS action,
            g.id AS geofence_id,
            g.label AS geofence_label
        FROM moving.geofences g
        WHERE g.id = ANY(fences_left)
        )
        SELECT json_agg(row_to_json(r))
        INTO events_json
        FROM r;

        -- Form notify payload
        SELECT json_build_object(
            'type', 'objectchange',
            'object_id', NEW.id,
            'events', events_json,
            'location', json_build_object(
                'longitude', ST_X(NEW.geog::geometry),
                'latitude', ST_Y(NEW.geog::geometry)),
            'ts', NEW.ts,
            'color', NEW.color,
            'props', NEW.props)
        INTO payload_json;

        RAISE DEBUG '%', payload_json;

        -- Send the payload out on the channel
        PERFORM (
            SELECT pg_notify(channel, payload_json::text)
        );

        RETURN NEW;
    END;
$$ LANGUAGE 'plpgsql';
```
</details>


* [pg_eventserv](https://github.com/crunchydata/pg_eventserv) picks the event off the `NOTIFY` queue and pushes it out to all listening clients over WebSockets.
* The user interface recieves the JSON payload, parses it, and applies the new location to the appropriate object. If there is a enter/leave event on a geofence, the UI also changes the geofence outline color appropriately.

Phew! That's a lot!

* Side note, the `geofences` table also has a trigger, `layer_change()` that catches insert/update/delete events and publishes a JSON notification with `pg_notify()`. This is also published by [pg_eventserv](https://github.com/crunchydata/pg_eventserv) and when the UI receives it, it simply forces a full re-load of geofence data.

<details><summary>layer_change()</summary>
```sql
CREATE FUNCTION layer_change() RETURNS trigger AS $$
    DECLARE
        layer_change_json json;
        channel text := 'objects';
    BEGIN
        -- Tell the client what layer changed and how
        SELECT json_build_object(
            'type', 'layerchange',
            'layer', TG_TABLE_NAME::text,
            'change', TG_OP)
          INTO layer_change_json;

        RAISE DEBUG 'layer_change %', layer_change_json;
        PERFORM (
            SELECT pg_notify(channel, layer_change_json::text)
        );
        RETURN NEW;
    END;
$$ LANGUAGE 'plpgsql';
```
</details>

OK, all done.


## Trying It Out Yourself

All the code and instructions are available in the [moving objects example](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/README.md) of `pg_eventserv`.


## Conclusion

* Moving objects are a classic case of "system state stored in the database".
* PostgreSQL provides the LISTEN/NOTIFY system to update clients about real-time changes.
* The pg_eventserv service allows you to push LISTEN/NOTIFY events further out to any WebSockets client and generate a moving object map.
* Because the state is managed in the database, storing the **historical state** of the system is trivially easy.

