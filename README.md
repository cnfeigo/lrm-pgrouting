Leaflet Routing Machine / pgRouting
=====================================

Extends [Leaflet Routing Machine](https://github.com/perliedman/leaflet-routing-machine) with support for [pgRouting](https://github.com/pgRouting/pgrouting).

Some brief instructions follow below, but the [Leaflet Routing Machine tutorial on alternative routers](http://www.liedman.net/leaflet-routing-machine/tutorials/alternative-routers/) is recommended.

## Installing

Install nodejs/iojs, clone this repository and execute:

```sh
npm install
./scripts/build.sh
```

Put the script after Leaflet and Leaflet Routing Machine has been loaded.

To use with for example Browserify:

```sh
npm install --save lrm-pgrouting
```

## Setup backend environment

### Setup Database environment

#### Setup sample database

```sh
createdb -U postgres muko
psql -U postgres -d muko -c "CREATE EXTENSION postgis;"
psql -U postgres -d muko -c "CREATE EXTENSION pgrouting;"
psql -U postgres -d muko -f data/muko_2po_4pgr.sql
```

#### Add wrapper PL/pgSQL script to the sample database

```sh
psql -U postgres -d muko -f sql/routing_via_points.sql
```

### Setup GeoServer environment

#### CORS setting (Tomcat)

1. Add following lines into `geoserver/WEB-INF/web.xml` - `<web-app>` node.
```xml
<filter>
  <filter-name>CorsFilter</filter-name>
  <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>
  <init-param>
    <param-name>cors.allowed.origins</param-name>
    <param-value>*</param-value>
  </init-param>
</filter>
<filter-mapping>
  <filter-name>CorsFilter</filter-name>
  <url-pattern>/*</url-pattern>
</filter-mapping>
```
See http://stackoverflow.com/questions/22363192/cors-tomcat-geoserver for more details.

2. Restart Tomcat service.

### Setup sample workspace/store/layer

1. Access to http://localhost:8080/geoserver.
2. Click *"Workspaces"*, then *"Add new workspace"*.
3. Fill the form with:
  * Name: `pgrouting`
  * Namespace URI: `http://pgrouting.org`
4. Press the *"Submit"* button.
5. Click *"Stores"*, then *"Add new Store"*.
6. Choose *"PostGIS"* and fill the form with:
  * Basic Store Info:
    * Workspace: `pgrouting`
    * Data Source Name: `muko`
  * Connection Parameters:
    * host: `localhost`
    * port: `5432`
    * database: `muko`
    * schema: `public`
    * user: `postgres`
    * password: ``
7. Press the *"Save"* button.
8. Click *"Layers"*, then *"Add a new resource"*.
9. Select the newly created workspace and store pair: `pgrouting:muko`
10. Click *"Configure new SQL view..."*.
11. Name the view `muko` and fill the *"SQL statements"* with:
```sql
SELECT
    seq,
    gid,
    name,
    heading,
    cost,
    geom,
    distance,
    point_type AS "pointType"
FROM
    routing.viaPoints(
        '%points%',
        'muko_2po_4pgr',
        'id',
        'geom_way',
        'osm_name',
        'source',
        'target',
        'cost',
        'reverse_cost',
        4326
    )
ORDER BY seq
```
12. In the *"SQL view parameters"*, click *"Guess parameters from SQL"*, then fill with:
  * Name: `points`
  * Default value: ``
  * Validation regular expression: `^[\d\.,\|]+$`
13. In the *"Attributes"*, click *"Refresh"*, then change `geom` column *"Type"* to `LineString` and *"SRID"* to `4326`.
14. Press the *"Save"* button.
15. In *"Edit Layer"* page, fill with:
  * Coordinate Reference Systems:
    * Declared SRS: `EPSG:4326`
    * SRS handling: `Force declared`
  * Bounding Boxes:
    * Lat/Lon Bounding Box:
      * Min X: `-180`
      * Min Y: `-90`
      * Max X: `180`
      * Max Y: `90`
16. Press the *"Save"* button.

## Using

There's a single class exported by this module, `L.Routing.PgRouting`. It implements the [`IRouter`](http://www.liedman.net/leaflet-routing-machine/api/#irouter) interface. Use it to replace Leaflet Routing Machine's default OSRM router implementation:

```javascript
var L = require('leaflet');
require('leaflet-routing-machine');
require('lrm-pgrouting'); // This will tack on the class to the L.Routing namespace

L.Routing.control({
    router: new L.Routing.PgRouting('your GeoServer WFS layer type name'),
}).addTo(map);
```

Note that you will need to pass an existing GeoServer WFS layer type name to the constructor.
