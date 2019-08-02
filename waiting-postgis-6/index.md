# Waiting for PostGIS 3: ST_Transform() and Proj6

Where are you? Go ahead and figure out your answer, I'll wait.

No matter what your answer, whether you said "sitting in my office chair" or "500 meters south-west of city hall" or "48.43° north by 123.36° west", you expressed your location relative to something else, whether that thing was your office layout, your city, or [Greenwich](https://en.wikipedia.org/wiki/Prime_meridian_(Greenwich)).

A geospatial database like PostGIS has to have able to convert between these different reference frames, known as "coordinate reference systems". The math for these conversions and the definition of the standards needed to align them all is called "[geodesy](https://en.wikipedia.org/wiki/Geodesy)", a field with sufficient depth and detail that you can make a [career out of it](https://oceanservice.noaa.gov/facts/geodesist.html).

![geographic crs](img/earthCRS.png)

Fortunately for users of PostGIS, most of the complexity of geodesy is hidden under the covers, and all you need to know is that different common coordinate reference systems are described in the [`spatial_ref_sys`](https://postgis.net/docs/using_postgis_dbmanagement.html#spatial_ref_sys) table, so making conversions between reference system involves knowing just two numbers: the `srid` (spatial reference id) of your source reference system, and the `srid` of your target system.

For example, to convert (and display) a point from the local [British Columbia Albers](http://epsg.io/3005) coordinate reference system to [geographic coordinates relative to the North American datum (NAD83)](http://epsg.io/4269), the following SQL is used:

```sql
SELECT ST_AsText(
    ST_Transform(
        ST_SetSRID('POINT(1195736 383004)'::geometry, 3005),
        4269)
    )
```

```
                 st_astext                 
-------------------------------------------
 POINT(-123.360004575121 48.4299914959586)
```

PostGIS makes use of the [Proj](https://proj.org/) library for coordinate reference system conversions, and PostGIS 3 will support the latest Proj release, version 6. 

Proj 6 includes support for time-dependent [datums](https://www.icsm.gov.au/education/fundamentals-mapping/datums/datums-explained-more-detail) and for direct conversion between datums. What does that mean? Well, one of the problems with the earth is that things move. And by things, I mean the ground itself, the very things we measure location relative to.

![Highway fault](img/highwayFault.jpg)

As location measurement becomes more accurate, and expectations for accuracy grow, reference shifts that were previously dealt with every 50 years have to be corrected closer to real time.

* North America had two datums set in the twentieth century, [NAD 27](https://en.wikipedia.org/wiki/North_American_Datum#North_American_Datum_of_1927) and [NAD 83](https://en.wikipedia.org/wiki/North_American_Datum#North_American_Datum_of_1983). In 2022, North America will get new datums, fixed to the [tectonic plates](https://www.ngs.noaa.gov/datums/newdatums/naming-convention.shtml) that make up the continent, and updated regularly to account for continental drift.
* Australia is on fast moving plates move about 7cm per year, and will [modernize its datums in 2020](https://www.ga.gov.au/scientific-topics/positioning-navigation/datum-modernisation). 7cm/year is not much, but that means that a coordinate captured to centimeter accuracy will be almost a meter out of place in a decade. For an autonomous done navigating an urban area, that could be the difference between an uneventful trip and a crash.

Being able to accurately convert between local reference frames, like continental datums where static data are captured, to [global frames](https://en.wikipedia.org/wiki/World_Geodetic_System) like those used by the GPS/GLONASS/Galileo systems is critical for accurate and safe geo-spatial calculations. 

![Local vs global datum](img/earthCenteredDatum.png)

Proj 6 combines updates to handle the new frames, along with computational improvements to make conversions between frames more accurate. Older versions used a "hub and spoke" system for conversions between systems: all conversions had [WGS84](https://en.wikipedia.org/wiki/World_Geodetic_System) as a "neutral" frame in the middle. 

A side effect of using WGS84 as a pivot system was increased error, because no conversion between refrences systems is error free: a convertion from one frame to another would accrue the error associated with **two conversions**, instead of one. Additionally, local geodesy agencies--like NOAA in the USA and GeoScience Australia--published very accurate direct transforms between historical datums, like NAD27 and NAD83, but old versions of Proj relied on hard-coded hacks to enable direct transforms. Proj 6 automatically finds and uses direct system-to-system transforms where they exist, for the most accurate possible transformation.

