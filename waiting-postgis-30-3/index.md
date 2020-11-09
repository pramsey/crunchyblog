# Waiting for PostGIS 3: ST_AsMVT Performance

Vector tiles are the [new hotness](https://info.crunchydata.com/blog/dynamic-vector-tiles-from-postgis), allowing large amounts of dynamic data to be sent for rendering right on web clients and mobile devices, and making very beautiful and highly interactive maps possible.

<video loop><source src="vector-map.mp4" type="video/mp4">Your browser does not support the video tag.</video> 

Since the introduction of [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html), people have been generating their tiles directly in the database more and more, and as a result wanting tile generation to go faster and faster.

Every tile generation query has to carry out the following steps:

* Gather all the relevant rows for the tile
* Simplify the data appropriately to match the resolulution of the tile
* Clip the data to the bounds of the tile
* Encode the data into the [MVT protobuf format](https://github.com/mapbox/vector-tile-spec/tree/master/2.1)

For PostGIS 3.0, performance of tile generation has been vastly improved.

* First, the clipping process has been sped up and made more reliable by integrating the [wagyu clipping algorithm](https://github.com/mapbox/wagyu) directly into PostGIS. This has sped up clipping of polygons in particular, and reduced instances of invalid output geometries. 

* Second, the simplification and precision reduction steps have been streamlined, to avoid unnecessary copying and work on simple cases like points and short lines. This has sped up handling of simple points and lines.

* Finally, [ST_AsMVT()](https://postgis.net/docs/ST_AsMVT.html) aggregate itself has been made parallelizeable, so that all the work above can be parcelled out to multiple CPUs, dramatically speeding up generation of tiles with lots of input geometry.

PostGIS vector tile support has gotten so good that even projects with massive tile generation requirements, like the [OpenMapTiles](https://openmaptiles.org/) project, have standardized their tiling on PostGIS.