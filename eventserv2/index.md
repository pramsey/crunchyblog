# Moving Object Map with pg_eventserv

In our [last post](), we introduced [pg_eventserv](https://github.com/crunchydata/pg_eventserv), and the concept of real-time web notifications generated from database actions.

In this post, we will dive into a practical use case: displaying state, calculating events, and tracking historical location for a set of **moving objects**.

![Screenshot](moving-object.jpg)

This demonstration uses [pg_eventserv](https://github.com/crunchydata/pg_eventserv) for eventing, and [pg_featureserv](https://github.com/crunchydata/pg_featureserv) for external web API, and [OpenLayers](https://openlayers.org) as the map API, to build a small example application that shows off the common features of moving objects systems.

[Try it out!](http://bl.ocks.org/pramsey/raw/7f12f0de2419a94a6c258f5daecf176f?raw=true)

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
* Every movement click on the UI fires a call to a web API, which is just a function published via [pg_featureserv](https://github.com/crunchydata/pg_featureserv), [object_move(object_id, direction)](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L266-L294).
* The [object_move(object_id, direction)](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L266-L294) function just converts the "direction" parameter into a movement vector, and `UPDATES` the relevant row of the `objects` table.
* The change to the `objects` table fires off the [objects_geofence()](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L92-L108) trigger, which calculates the fences the object is now in.
* The change to the `objects` table **then** fires off the [objects_update()](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L127-L192) trigger, which:
  * Compares the current set of geofences to the previous set, and thus detects any enter/leave events.
  * Adds the new location of the object to the `objects_history` tracking table.
  * Composes the new location and any geofence events into a JSON object and puts it into the "objects" `NOTIFY` queue using `pg_notify()`.
* [pg_eventserv](https://github.com/crunchydata/pg_eventserv) picks the event off the `NOTIFY` queue and pushes it out to all listening clients over WebSockets.
* The user interface recieves the JSON payload, parses it, and applies the new location to the appropriate object. If there is a enter/leave event on a geofence, the UI also changes the geofence outline color appropriately.

Phew! That's a lot!

* Side note, the `geofences` table also has a trigger, [layer_change()](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql#L209-L227) that catches insert/update/delete events and publishes a JSON notification with `pg_notify()`. This is also published by [pg_eventserv](https://github.com/crunchydata/pg_eventserv) and when the UI receives it, it simply forces a full re-load of geofence data.

OK, all done.


## Trying It Out

All the code and files are available in the [examples directory](https://github.com/CrunchyData/pg_eventserv/tree/main/examples/moving-objects) of `pg_eventserv`.

You can run the database in [Crunchy Bridge](https://crunchybridge.com/) and the services using [Container Apps](https://docs.crunchybridge.com/container-apps/) in Crunchy Bridge.

### Load Database

First, load up the [moving-objects.sql](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.sql) file in your database. This creates all the tables and triggers to keep the model up-to-date. A good practice is to use the `application` user instead of the `postgres` user as the owner for the tables and triggers. That way you can connect the services using a lower-priv database user.

### Start Services

Now, start up the services as container apps! (This you will have to do as the `postgres` user.)

This starts up `pg_featureserv`:

```
SELECT run_container('
    -dt 
    -p 5437:9000/tcp 
    --log-driver k8s-file 
    --log-opt max-size=1mb 
    -e DATABASE_URL="postgres://application:xxxxxxxxxx@p.xxxxxxxxxx.db.postgresbridge.com:5432/dbname" 
    -e PGFS_SERVER_HTTPPORT=9000  
    -e PGFS_PAGING_LIMITDEFAULT=10000 
    -e PGFS_PAGING_LIMITMAX=10000 
    docker.io/pramsey/pg_featureserv:latest
    ');
```

The newlines in the example above have to be stripped out before running the SQL command.

This starts up `pg_eventserv`:

```
SELECT run_container('
    -dt 
    -p 5438:7700/tcp
    --log-driver k8s-file 
    --log-opt max-size=1mb 
    -e DATABASE_URL="postgres://application:xxxxxxxx@p.xxxxxxxx.db.postgresbridge.com:5432/dbname" 
    -e ES_HTTPPORT=7700 
    docker.io/pramsey/pg_eventserv:latest
');
```

Now you should be up and running! You can also just download the binaries of the two services directly and run them locally and use the default `localhost` addresses. 


### Modify Map Client

The [map client JavaScript](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.js) needs to be modified to point at your new servers, on their ports!

Find the following variables and edit them to point to your services.

The event server web socket host:

```
var wsHost = "ws://yourhostname:5438";
```

Note that the port is not the default service port, but the port the container is running at on Crunchy Bridge.

The feature server HTTP host:

```
var fsHost = "http://yourhostname:5437";
```

If you are running the services locally, you can just leave the example code as is.


### Try it!

Open up the [HTML page](https://github.com/CrunchyData/pg_eventserv/blob/main/examples/moving-objects/moving-objects.html), and you should see the working map!


## Conclusion
