# Waiting for PostGIS 3.1: GEOS 3.9

While we talk about "PostGIS" like it's one thing, it's actually the collection of a number of specialized geospatial libraries, along with a bunch of code of its own.

* PostGIS provides core functionality
  * bindings to PostgreSQL, the types and indexes, 
  * format reading and writing
  * basic algorithms like distance and area
  * performance tricks like caching
  * simple geometry manipulations (add a point, dump rings, etc)
  * algorithms that don't exist in the other libraries
* Proj provides coordinate system transformations
* GDAL provides raster algorithms and format supports
* GEOS provides computational geometry algorithms
  * geometry relationships, like "intersects", "touches" and "relate"
  * geometry operations, like "intersection", "union"
  * basic algorithms, like "triangulate"

The algorithms in GEOS are actually a port to C++ of algoriths in the JTS Java library. The ecosystem of projects that depend on GEOS or JTS or one of the other language ports of GEOS is very large.

![GEOS/JTS Ecosystem](img/geos-jts.png "GEOS/JTS Ecosystem")

## Overlay NG

Over the past 12 months, the geospatial team at Crunchy Data has invested heavily in JTS/GEOS development, overhauling the overlay engine that backs the **Intersection**, **Union**, **Difference** and ***SymDifference** functions in all the projects that depend on the library.

![Intersection](img/intersection.png "Intersection")![Union](img/union.png "Union")

The new overlay engine, "[Overlay NG](https://lin-ear-th-inking.blogspot.com/2020/05/jts-overlay-next-generation.html)", promises to be more reliable, and hopefully also faster for most common cases.

One use of overlay code is chopping large objects up, to find the places they have in common. This query summarizes climate zones (**bec**) by watershed (**wsa**).

```sql
SELECT 
    Sum(ST_Area(ST_Intersection(b.geom, w.geom))) AS area_zone, 
    w.wsd_id, 
    b.zone
FROM bec b
JOIN wsa w
ON ST_Intersects(b.geom, w.geom)
WHERE w.nwwtrshdcd like '128-835500-%'
GROUP BY 2, 3
```

![Summarization](img/bec-wsa.png "Summarization")

The new implementation for this query runs about **2 times** faster than the original. Even better, when run on a larger area with more data, the origin implementation fails, it's not possible to get a result out. The new implementation completes.

Another common use over overlay code is melting together areas that share an attribute. This query takes (almost) every watershed on Vancouver Island and melts them together.

```sql
SELECT ST_Union(geom)
FROM wsa
WHERE nwwtrshdcd like '920-%'
   OR nwwtrshdcd like '930-%'
```

At the start, there are 1384 watershed polygons.

![Vancouver Island watersheds](img/vi-wsd.png "Vancouver Island watersheds")

At the end there is just one.

![Vancouver Island](img/vi.png "Vancouver Island")

The new implementation takes about 50% longer currently, but it is more robust and less likely to fail than the original. 

## Fixed Precision Overlay

The way Overlay NG ensures robust results, is by falling back to more and more reliable noding approaches. "Noding" refers to how new vertices are introduced into geometries during the overlay process.

* Initially a naive "floating point" noding is used, that just uses double precision coordinates. This works most of the time, but occasionally fails when noding "almost parallel" edges.
* On failure, a "snapping" noding is used, which nudges nearby edges and nodes together within a tolerance. That works most of the time, but occasional fails.
* Finally, a "fixed precision" routing nudges **all** of the coordinates in both geometries into a fixed space, where edge collapses can be handled deterministically. This is the lowest performance approach, but it very very rarely occurs.

Sometimes, end users actually **prefer** to have their geometry forced into a fixed precision grid, and for overlay to use a fixed precision. For those users, with PostGIS 3.1 and GEOS 3.9 there are some new parameters in the intersection/union/difference functions.

* [ST_Intersection(geometry geomA, geometry geomB,float8 gridSize)](https://postgis.net/docs/manual-dev/ST_Intersection.html)
* [ST_Union(geometry geomA, geometry geomB, float8 gridSize)](https://postgis.net/docs/manual-dev/ST_Union.html)
* [ST_Difference(geometry geomA, geometry geomB, float8 gridSize)](https://postgis.net/docs/manual-dev/ST_Difference.html)

![Precision reduction](img/eu_precision_reduce.gif "Precision reduction")

The new "gridSize" parameter determines the size of the grid to snap to when generating new outputs. This can be used both to generate new geometries, and also to precision reduce existing geometries, just be unioning a geometry with an empty geometry.

## Inscribed Circle

As always, there are a few random algorithmic treats in each new GEOS release. For 3.9, there is the "inscribed circle", which finds the large circle that can be fit inside a polygon (or any other boundary).

![Vancouver Island inscribed circle](img/inscribed-circle.png "Vancouver Island inscribed circle")

In addition to making a nice picture, the inscribed circle functions as a measure of the "wideness" of a polygon, so it can be used for things like analyzing river polygons to determine the widest point.

