# Waiting for PostGIS 3: Hilbert Geometry Sorting

With the release of PostGIS 3.0, queries that `ORDER BY` geometry columns will return rows using a [Hilbert curve](https://en.wikipedia.org/wiki/Hilbert_curve) ordering, and do so about twice as fast.

Whuuuut!?!

The history of "ordering by geometry" in PostGIS is mostly pretty bad. Up until version 2.4 (2017), if you did `ORDER BY` on a geometry column, your rows would be returned using the ordering of the minimum X coordinate value in the geometry. 

One of the things users expect of "ordering" is that items that are "close" to each other in the ordered list should also be "close" to each other in the domain of the values. For example, in a set of sales orders ordered by price, rows next to each other have similar prices.

To visualize what geometry ordering looks like, I started with a field of 10,000 random points.

```sql
CREATE SEQUENCE points_seq;

CREATE TABLE points AS
SELECT 
  (ST_Dump(
    ST_GeneratePoints(
        ST_MakeEnvelope(-10000,-10000,10000,10000,3857),
        10000)
    )).geom AS geom,
  nextval('points_seq') AS pk;
```

![Ten thousand random points](img/pts.png "10,000 Random Points")

Now select from the table, and use [ST_MakeLine()](https://postgis.net/docs/ST_MakeLine.html) to join them up in the desired order. Here's the original ordering, prior to version 2.4.

```sql
SELECT ST_MakeLine(geom ORDER BY ST_X(geom)) AS geom
FROM points;
```

![Random Points in XMin Order](img/xmin.png)

Each point in the ordering is close in the X coordinate, but since the Y coordinate can be anything, there's not much spatial coherence to the ordered set. A better spatial ordering will keep points that are near in space also near in the set.

For 2.4 we got a little clever. Instead of sorting by the minimum X coordinate, we took the center of the geomery bounds, and created a [Morton curve](https://en.wikipedia.org/wiki/Z-order_curve) out of the X and Y coordinates. Morton keys just involve interleaving the bits of the values on the two axes, which is a relatively cheap operation. 

The result is **way more spatially coherent**.

![Random Points in Morton Order](img/morton.png)

For 3.0, we have replaced the Morton curve with a [Hilbert curve](https://en.wikipedia.org/wiki/Hilbert_curve). The Hilbert curve is slightly more expensive to calculate, but we offset that by stripping out some [wasted cycles](https://trac.osgeo.org/postgis/ticket/3883) in other parts of the old implementation, and the new code is now faster, and also even more spatially coherent.

```sql
SELECT ST_MakeLine(geom ORDER BY geom) AS geom
FROM points;
```

![Random Points in Hilbert Order](img/hilbert.png)

PostGIS 3.0 will be released some time this fall, hopefully before the final release of PostgreSQL 12.
