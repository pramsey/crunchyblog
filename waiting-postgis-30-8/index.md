# Waiting for PostGIS 3: GEOS 3.8

While PostGIS includes lots of algorithms and functionality we have built ourselves, it also adds geospatial smarts to PostgreSQL by linking in specialized libraries to handle particular problems:

* [Proj](https://proj.org) for coordinate reference support;
* [GDAL](https://gdal.org) for raster functions and formats;
* [GEOS](https://trac.osgeo.org/geos) for computational geometry (basic operations);
* [CGAL](https://www.cgal.org/) for **more** computational geometry (3D operations); and
* for format support, libxml2, libjsonc, libprotobuf-c 

Many of the standard geometry processing functions in PostGIS are actually evaluated inside the GEOS library, so updates in GEOS are very important to PostGIS -- they add new functionality or smooth the behaviour of existing functions.

Functions backed by GEOS include:

* [ST_Intersection(geometry, geometry)](https://postgis.net/docs/ST_Intersection.html) => geometry
* [ST_Union(geometry, geometry)](https://postgis.net/docs/ST_Union.html) => geometry
* [ST_Difference(geometry, geometry)](https://postgis.net/docs/ST_Difference.html) => geometry
* [ST_Buffer(geometry, radius)](https://postgis.net/docs/ST_Buffer.html) => geometry

These functions are all "overlay operation" functions -- they take in geometry arguments and construct new geometries for output. Under the covers is an operation called an "overlay", which combines all the edges of the inputs into a graph and then extracts new outputs from that graph.

While the "overlay operations" in GEOS are very reliable, they are not **100%** reliable. When operations fail, the library throws the dreaded `TopologyException`, which indicates the graph is in an inconsistent and unusable state.

Because there are a lot of PostGIS users and they manage a lot of data, there are a non-zero number of cases that cause `TopologyExceptions`, and [upset users](http://kelsocartography.com/blog/?p=4240). We would like take that number **down to zero**.

With luck, GEOS 3.8 will succeed in finally bringing fully robust overlay operations to the open source community. The developer behind the GEOS algorithms, Martin Davis, [recently joined Crunchy Data](http://blog.cleverelephant.ca/2019/02/dr-jts-crunchy.html), and has spent this summer working on a new overlay engine. 

Overlay failures are caused when intersections between edges result in inconsistencies in the overlay graph. Even using double precision numbers, systems have only [51 bits of precision](https://en.wikipedia.org/wiki/Double-precision_floating-point_format) to represent coordinates, and that fixed precision can result in graphs that don't correctly reflect their inputs. 

The solution is building a system that can operate on any fixed precision and retain valid geometry. As an example, here the new engine builds valid representations of Europe at any precision, even ludicrously coarse ones.

![europe at different precisions](img/eu.gif)

In practice, the engine will be used with a tolerance that is close to double precision, but still provides enough slack to handle tricky cases in ways that users find visually "acceptable". Initially the new functionality should slot under the existing PostGIS functions without change, but in the future we will be able to expose knobs to allow users to explicitly set the precision domain they want to work in.

GEOS 3.8 may not be released in time for PostGIS 3, but it will be a close thing. In addition to the new overlay engine, a lot of work has been done making the code base cleaner, using more "modern" C++ idioms, and porting forward new fixes to existing algorithms.





