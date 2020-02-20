# Crunchy Spatial: It's PostGIS, for the Web

"Let's put that on a map!"

PostGIS has so many [cool features](https://docs.google.com/presentation/d/1a2ruZLRUQ-dH8AWv9Cz6XfPWrs-Vdz_vKQVRNMjqvc0/edit) that it is possible to do full GIS analyses without ever leaving the SQL language, but... at the end of the day, you want to get those results, show that data, on the map.

The Crunchy Data geospatial team has been thinking about how to bring PostGIS to the web, and we established some basic principles:

* Use the database, as much as possible. 
    * The database already has a user model and security model. 
    * The database can already generate output formats, like [MVT](https://postgis.doc/docs/ST_AsMVT.html), [JSON](https://www.postgresql.org/docs/current/functions-json.html) and [GeoJSON](https://postgis.doc/docs/ST_AsGeoJSON.html).
    * The database can perform complex analysis via the many many PostGIS functions.
    * The database can host units of custom behaviour via user-defined functions.
* Divide up the web application services into small chunks.
    * Vector tile serving.
    * Vector feature serving.
    * Data import.
    * Routing.
    * Geocoding.
    * Base map serving.
* Implement each service independently, using the database as the coordination point.
* Keep each service simple and small enough to qualify as a "micro-service" and assume production deployment in a managed environment like Kubernetes.

The result is a set of micro-service components that we plan on growing over time. The first two services allow us to build simple view-query-display spatial applications:

* [pg_tileserv](https://github.com/crunchydata/pg_tileserv), a vector tile server, and;
* [pg_featureserv](https://github.com/crunchydata/pg_featureserv), a vector feature server.

Because the services are so simple, wrapping them in containers for easy scale out in Kubernetes is straight forward, and allows us to build out scalable back-ends automagically.

... diagram of k8s architecture, replicated database with auto-scaling replicas, bg_bouncer mediating, tile and feature servers, also auto-scaling, and ha-proxy mediating inbound connections from react/openlayers web application ...

As we add to the collection of services in the Crunchy Spatial offering, we'll be able to add drag'n'drop import, vector base maps, routing and other useful features, all running on a standard, open k8s platform, like [OpenShift](https://openshift.com). 

Crunchy Spatial: it's PostGIS, for the web.

