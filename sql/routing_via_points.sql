DROP SCHEMA IF EXISTS routing CASCADE;

CREATE SCHEMA routing;

-- DROP TYPE routing.edge_result;
CREATE TYPE routing.edge_result AS (
    gid         integer,
    pos         double precision,
    pointGeom   geometry
);

-- DROP TYPE routing.route_result;
CREATE TYPE routing.route_result AS (
    gid         integer,
    geom        geometry,
    name        text,
    node        integer,
    cost        double precision,
    source      integer,
    target      integer,
    flipGeom    geometry
);

-- DROP FUNCTION routing.findNearestEdge(double precision, double precision, boolean, varchar, varchar, varchar, integer);
-- Example:
-- SELECT routing.findNearestEdge(135.702857, 34.944479, false, 'muko_2po_4pgr');
CREATE OR REPLACE FUNCTION routing.findNearestEdge(
        IN x double precision,
        IN y double precision,
        IN snap_to_node boolean DEFAULT false,
        IN tbl varchar DEFAULT 'osm_2po_4pgr'::varchar,
        IN gid_col varchar DEFAULT 'id'::varchar,
        IN geom_col varchar DEFAULT 'geom_way'::varchar,
        IN srid integer DEFAULT 4326
    )
    RETURNS routing.edge_result AS
$BODY$
DECLARE
    point   geometry;
    dist    double precision;
    res     routing.edge_result;
BEGIN
    -- Create point geometry
    EXECUTE 'SELECT ST_GeomFromText(''POINT(' || x || ' ' || y ||')'', ' || srid || ')'
        INTO point;
    
    -- Find nearest edge
    EXECUTE 'SELECT
                ' || quote_ident(gid_col) || ' AS gid,
                ST_Distance(' || quote_ident(geom_col) || ', $1) AS dist,
                ST_Line_Locate_Point(' || quote_ident(geom_col) || ', $1) AS pos
            FROM
                ' || quote_ident(tbl) || '
            ORDER BY dist ASC LIMIT 1'
--         INTO gid, dist, pos USING point;
        INTO res.gid, dist, res.pos USING point;
    
    -- Adjust position
    IF snap_to_node THEN
        IF res.pos < 0.5 THEN
            res.pos := 0.0;
        ELSE
            res.pos := 1.0;
        END IF;
    END IF;
    
    -- Get nearest point geometry
    EXECUTE 'SELECT
                ST_Line_Interpolate_Point(' || quote_ident(geom_col) || ', $1) AS pointGeom
            FROM
                ' || quote_ident(tbl) || '
            WHERE
                ' || quote_ident(gid_col) || ' = $2'
        INTO res.pointGeom USING res.pos, res.gid;
    RETURN res;
END;
$BODY$
LANGUAGE 'plpgsql' VOLATILE STRICT;

--
-- DROP FUNCTION routing.viaPoints(text, varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, integer);
-- Example:
-- SELECT routing.viaPoints('135.702857,34.944479|135.703476,34.944530', 'muko_2po_4pgr');
-- SELECT routing.viaPoints('135.70285,34.944481|135.702972,34.944916|135.703506,34.94453', 'muko_2po_4pgr');
CREATE OR REPLACE FUNCTION routing.viaPoints(
        IN points text,
        IN tbl varchar DEFAULT 'osm_2po_4pgr'::varchar,
        IN gid_col varchar DEFAULT 'id'::varchar,
        IN geom_col varchar DEFAULT 'geom_way'::varchar,
        IN name_col varchar DEFAULT 'osm_name'::varchar,
        IN source_col varchar DEFAULT 'source'::varchar,
        IN target_col varchar DEFAULT 'target'::varchar,
        IN cost_col varchar DEFAULT 'cost'::varchar,
        IN reverse_cost_col varchar DEFAULT 'reverse_cost'::varchar,
        IN srid integer DEFAULT 4326,
        OUT seq integer,
        OUT gid integer,
        OUT name text,
        OUT heading double precision,
        OUT cost double precision,
        OUT geom geometry,
        OUT distance double precision,
        OUT point_type smallint -- 0:none, 1:edge start node is source(origin) point, 2:edge end node is target(destination) point,
                                -- 4:edge start node is intermediate point, 8:edge end node is intermediate point
    )
    RETURNS SETOF record AS
$BODY$
DECLARE
    pointStrArray   text[];
    pointCount      integer;
    i               integer;
    coordStrArray   text[];
    pointArray      double precision[][];
    x               double precision;
    y               double precision;
    edgeRecord      routing.edge_result;
    edgeRecords     routing.edge_result[];
    routeRecord     routing.route_result;
    routeRecords    routing.route_result[];
    routeCount      integer;
    j               integer;
BEGIN
    -- Check points param length
    IF length(points) < 7 THEN
        --RAISE EXCEPTION 'points parameter is not specified or too short';
        RETURN;
    END IF;
    -- Split points to array(string)
    EXECUTE 'SELECT regexp_split_to_array($1, ''\|'')'
        INTO pointStrArray USING points;
    pointCount := array_length(pointStrArray, 1);
    -- Check pointStrArray length
    IF pointCount < 2 THEN
        --RAISE EXCEPTION 'via points length should be >= 2';
        RETURN;
    END IF;
    
    pointArray := array[]::double precision[];
    FOR i IN 1 .. pointCount
    LOOP
        EXECUTE 'SELECT regexp_split_to_array($1, '','')'
            INTO coordStrArray USING pointStrArray[i];
        --RAISE NOTICE 'str:% coordStrArray:%', pointStrArray[i], array_length(coordStrArray, 1);
        IF array_length(coordStrArray, 1) != 2 THEN
            --RAISE EXCEPTION 'points[%] coordinate length is not 2 (x, y)', i;
            RETURN;
        ELSE
            x := cast(coordStrArray[1] AS double precision);
            y := cast(coordStrArray[2] AS double precision);
            pointArray := pointArray || array[[x, y]];
        END IF;
    END LOOP;
    --RAISE NOTICE 'pointArray:%', pointArray;
    
    -- Find nearest edges
    edgeRecords := array[]::routing.edge_result[];
    FOR i IN 1 .. pointCount
    LOOP
        EXECUTE 'SELECT * FROM routing.findNearestEdge($1, $2,
                    false,
                    ''' || quote_ident(tbl) || ''',
                    ''' || quote_ident(gid_col) || ''',
                    ''' || quote_ident(geom_col) || ''',
                    ' || srid || ')'
            INTO edgeRecord USING pointArray[i][1], pointArray[i][2];
        --RAISE NOTICE 'edgeRecord:%', edgeRecord;
        edgeRecords := edgeRecords || edgeRecord;
    END LOOP;
    --RAISE NOTICE 'edgeRecords:%', edgeRecords;
    
    seq := 0;
    FOR i IN 1 .. pointCount-1
    LOOP
        routeRecords := array[]::routing.route_result[];
        FOR routeRecord IN EXECUTE '
                SELECT
                    edge.' || quote_ident(gid_col) || '::integer AS gid,
                    edge.' || quote_ident(geom_col) ||' AS geom,
                    edge.' || quote_ident(name_col) || ' AS name,
                    result.id1 AS node,
                    result.cost AS cost,
                    edge.' || quote_ident(source_col) || '::integer AS source,
                    edge.' || quote_ident(target_col) || '::integer AS target,
                    ST_Reverse(edge.' || quote_ident(geom_col) || ') AS flip_geom
                FROM
                    pgr_trsp(''
                        SELECT
                            ' || quote_ident(gid_col) || ' AS id,
                            ' || quote_ident(source_col) || '::integer AS source,
                            ' || quote_ident(target_col) || '::integer AS target,
                            ' || quote_ident(cost_col) || '::double precision AS cost,
                            ' || quote_ident(reverse_cost_col) || '::double precision AS reverse_cost
                        FROM
                            ' || quote_ident(tbl) || ''',
                        $1, $2, $3, $4, true, true) AS result,
                    ' || quote_ident(tbl) || ' AS edge
                WHERE
                    result.id2 = ' || quote_ident(gid_col) || '
                ORDER BY result.seq'
            USING edgeRecords[i].gid, edgeRecords[i].pos, edgeRecords[i+1].gid, edgeRecords[i+1].pos
        LOOP
            routeRecords := routeRecords || routeRecord;
        END LOOP;
        --RAISE NOTICE 'routeRecords:%', routeRecords;
        
        routeCount := array_length(routeRecords, 1);
        -- Check result count for safety
        IF routeCount = 0 THEN
            --RAISE EXCEPTION 'There is no route between (edge:%, pos:%) - (edge:%, pos:%)',
            --    edgeRecords[i].gid, edgeRecords[i].pos, edgeRecords[i+1].gid, edgeRecords[i+1].pos;
            RETURN;
        END IF;
        
        IF edgeRecords[i].gid = edgeRecords[i+1].gid AND array_length(routeRecords, 1) = 1 THEN
            -- Same edge case
            point_type := 0;
            IF i = 1 THEN
                point_type := point_type + 1;
            ELSE
                point_type := point_type + 4;
            END IF;
            IF i = pointCount - 1 THEN
                point_type := point_type + 2;
            ELSE
                point_type := point_type + 8;
            END IF;
            IF edgeRecords[i].pos < edgeRecords[i+1].pos THEN
                geom := ST_Line_Substring(routeRecords[1].geom, edgeRecords[i].pos, edgeRecords[i+1].pos);
            ELSE
                geom := ST_Line_Substring(ST_Reverse(routeRecords[1].geom), 1.0 - edgeRecords[i].pos, 1.0 - edgeRecords[i+1].pos);
            END IF;
            -- Calculate heading (simplified)
            EXECUTE 'SELECT degrees( ST_Azimuth( 
                    ST_StartPoint(''' || geom::text || '''),
                    ST_EndPoint(''' || geom::text || ''') ) )' 
                INTO heading;
            seq     := seq + 1;
            gid     := routeRecords[1].gid;
            name    := routeRecords[1].name;
            cost    := routeRecords[1].cost;
            distance:= ST_Length(ST_Transform(geom, 3857));
            RETURN NEXT;
        ELSE
            -- Loop
            FOR j IN 1 .. routeCount
            LOOP
                point_type := 0;
                IF j = 1 AND routeRecords[j].node = -1 THEN
                    IF i = 1 THEN
                        point_type := point_type + 1;
                    ELSE
                        point_type := point_type + 4;
                    END IF;
                    IF j < routeCount THEN
                        IF routeRecords[j].target = routeRecords[j+1].node THEN
                            geom := ST_Line_Substring(routeRecords[j].geom, edgeRecords[i].pos, 1.0);
                        ELSEIF routeRecords[j].source = routeRecords[j+1].node THEN
                            geom := ST_LineSubstring(ST_Reverse(routeRecords[j].geom), 1.0 - edgeRecords[i].pos, 1.0);
                        END IF;
                    ELSE
                        --RAISE EXCEPTION 'Unexpected case1 (edge:%, pos:%) - (edge:%, pos:%)',
                        --    edgeRecords[i].gid, edgeRecords[i].pos, edgeRecords[i+1].gid, edgeRecords[i+1].pos;
                        RETURN;
                    END IF;
                ELSEIF j = routeCount AND (routeRecords[j].gid = -1 OR routeRecords[j].gid = edgeRecords[i+1].gid) THEN
                    IF routeRecords[j].gid != -1 THEN
                        IF i = pointCount - 1 THEN
                            point_type := point_type + 2;
                        ELSE
                            point_type := point_type + 8;
                        END IF;
                        IF routeRecords[j].source = routeRecords[j].node THEN
                            geom := ST_Line_Substring(routeRecords[j].geom, 0.0, edgeRecords[i+1].pos);
                        ELSEIF routeRecords[j].target = routeRecords[j].node THEN
                            geom := St_Line_Substring(ST_Reverse(routeRecords[j].geom), 0.0, 1.0 - edgeRecords[i+1].pos);
                        END IF;
                    ELSE
                        CONTINUE;
                    END IF;
                ELSE
                    IF routeRecords[j].source = routeRecords[j].node THEN
                        geom := routeRecords[j].geom;
                    ELSEIF routeRecords[j].target = routeRecords[j].node THEN
                        geom := ST_Reverse(routeRecords[j].geom);
                    END IF;
                    IF j < routeCount AND routeRecords[j+1].gid = -1 THEN
                        IF j + 1 = routeCount THEN
                            point_type := point_type + 2;
                        ELSE
                            point_type := point_type + 8;
                        END IF;
                    END IF;
                END IF;
                -- Calculate heading (simplified)
                EXECUTE 'SELECT degrees( ST_Azimuth( 
                        ST_StartPoint(''' || geom::text || '''),
                        ST_EndPoint(''' || geom::text || ''') ) )' 
                    INTO heading;
                seq     := seq + 1;
                gid     := routeRecords[j].gid;
                name    := routeRecords[j].name;
                cost    := routeRecords[j].cost;
                distance:= ST_Length(ST_Transform(geom, 3857));
                RETURN NEXT;
            END LOOP;
        END IF;
    END LOOP;
    RETURN;
END;
$BODY$
LANGUAGE 'plpgsql' VOLATILE STRICT;