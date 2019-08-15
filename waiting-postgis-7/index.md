# Waiting for PostGIS 3: Parallelism in PostGIS

Parallel query has been a part of PostgreSQL since 2016 with the release of version 9.6 and in theory PostGIS should have been benefiting from parallelism ever since.

In practice, the complex nature of PostGIS has meant that **very few queries would parallelize** under normal operating configurations -- they could only be forced to parallelize using [oddball configurations](http://blog.cleverelephant.ca/2016/03/parallel-postgis.html). 

With PostgreSQL 12 and PostGIS 3, parallel query plans will be generated and executed far more often, because of changes to both pieces of software:

* PostgreSQL 12 includes a [new API](https://github.com/postgres/postgres/blob/fe9b7b2fe5973309c0a5f7d9240dde91aeeb94aa/src/include/nodes/supportnodes.h) that allows extensions to modify query plans and add index clauses. This has allowed PostGIS to remove a large number of inlined SQL functions that were previously acting as optimization barriers to the planner.
* PostGIS 3 has taken advantage of the removal of the SQL inlines to re-cost all the spatial functions with much higher costs. The combination of function inlining and high costs used to cause the planner to make poor decisions, but with the updates in PostgreSQL that can now be avoided.

Increasing the costs of PostGIS functions has allowed us to encourage the PostgreSQL planner to be more aggressive in choosing parallel plans. 

PostGIS spatial functions are far more computationally expensive than most PostgreSQL functions. An area computation involves lots of math involving every point in a polygon. An intersection or reprojection or buffer can involve even more. Because of this, many PostGIS queries are bottlenecked on CPU, not on I/O, and are in an excellent position to take advantage of parallel execution.

One of the functions that benefits from parallelism is the popular [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) aggregate function. When there are enough input rows, the aggregate will fan out and parallelize, which is great since [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) calls usually wrap a call to the expensive geometry processing function, [ST_AsMVTGeom()](https://postgis.net/docs/ST_AsMVTGeom.html).

![Tile 1/0/0](img/tile100.png)

Using the Natural Earth [Admin 1](https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-1-states-provinces/) layer of states and provinces as an input, I ran a small performance test, building a vector tile for zoom level one. 

![parallel MVT tile performance](img/graph.png)

Spatial query performance appears to scale about the same as non-spatial as the [number of cores increases](https://blog.rustprooflabs.com/2018/02/pg10_parallel_queries), taking 30-50% less time with each doubling of processors, so not quite linearly.

Join, aggregates and scans all benefit from parallel planning, though since the gains are sublinear [there's a limit](http://blog.cleverelephant.ca/2019/06/parallel-postgis-4b.html) to how much performance you can extract from an operation by throwing more processors at at.  Also, operations that do a large amount of computation within a single function call, like [ST_ClusterKMeans](https://postgis.net/docs/ST_ClusterKMeans.html), do not automatically parallelize: the system can only parallelize the calling of functions multiple times, not the internal workings of single functions.


