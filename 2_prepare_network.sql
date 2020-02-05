/*
 |---------------------------------------------------------------------------------------------------------------------|
 | OpenStreetMap 110 kV-Routing
 | Author: Michael Ebner, 2019
 | Part 2: prepare network
 |---------------------------------------------------------------------------------------------------------------------|
*/

/*
 fill base tables
 */

INSERT INTO gridkit_power_line_voltage (l_id, v_id_1, v_id_2, length_m, voltage, cables, wires, frequency, name,
                                        operator, ref, part_nr, num_objects, geom)
SELECT l_id,
       v_id_1,
       v_id_2,
       length_m,
       voltage,
       cables,
       wires,
       frequency,
       name,
       operator,
       ref,
       part_nr,
       num_objects,
       st_transform(st_geomfromewkt(wkt_srid_4326), 3857) AS geom
  FROM gridkit_heuristic_links_highvoltage;

INSERT INTO power_stations (station_id, power_name, geom)
SELECT station_id,
       power_name,
       st_buffer(area, 50) AS geom
  FROM gridkit_power_station
 WHERE power_name IN ('substation', 'sub_station', 'station')
 UNION ALL
SELECT station_id,
       power_name,
       st_buffer(area, 1) AS geom
  FROM gridkit_power_station
 WHERE power_name IN ('joint');

INSERT INTO segments (l_id, voltage, way, startpoint, endpoint, substation_id, source, target) (
	SELECT l_id,
	       voltage::INT        AS voltage,
	       geom::GEOMETRY      AS way,
	       st_startpoint(geom) AS startpoint,
	       st_endpoint(geom)   AS endpoint,
	       NULL::BIGINT        AS substation_id,
	       NULL::INT           AS source,
	       NULL::INT           AS target
	  FROM gridkit_power_line_voltage
);

/*
 identify start and endpoints of line segments and replace with centroid of the substation connecting them
 */
  WITH substations AS (
	  SELECT station_id,
	         geom,
	         st_centroid(geom) AS centroid
		FROM power_stations
  )
	 , endpoints   AS (
	  SELECT s.l_id       AS seg_id,
	         b.centroid,
	         b.station_id AS sub_id
		FROM segments AS s, substations AS b
	   WHERE st_within(s.endpoint, b.geom)
  )
	 -- replace col endpoint with centroid of substation
UPDATE segments AS s
   SET endpoint      = endpoints.centroid,
       substation_id = sub_id
  FROM endpoints
 WHERE s.l_id = endpoints.seg_id;

-- repeat procedure for startpoints
  WITH substations AS (
	  SELECT station_id,
	         geom,
	         st_centroid(geom) AS centroid
		FROM power_stations
  )
	 , startpoints AS (
	  SELECT s.l_id       AS seg_id,
	         b.centroid,
	         b.station_id AS sub_id
		FROM segments AS s, substations AS b
	   WHERE st_within(s.startpoint, b.geom)
  )
	 -- replace col startpoint with centroid of substation
UPDATE segments AS s
   SET startpoint    = startpoints.centroid,
       substation_id = sub_id
  FROM startpoints
 WHERE s.l_id = startpoints.seg_id;

-- add new startpoint to segment. BB-comparison ("=") would also do the trick, because it is just points
UPDATE segments
   SET way = st_addpoint(way, startpoint, 0)
 WHERE st_equals(st_startpoint(way), startpoint) IS FALSE;

-- add new endpoint to segment
UPDATE segments
   SET way = st_addpoint(way, endpoint, -1)
 WHERE st_equals(st_endpoint(way), endpoint) IS FALSE;


/*
 Fill source/target table
 */

INSERT INTO source_target (voltage, point)
-- all start and endpoints are gathered grouped by voltage and geometry
  WITH all_points    AS (
	  SELECT row_number() OVER () AS id,
	         *
		FROM (
			     SELECT st_startpoint(way) AS point,
			            voltage::INT
				   FROM segments
				  UNION
				 SELECT st_endpoint(way) AS point,
				        voltage::INT
				   FROM segments
				  GROUP BY point, voltage
		     ) ua)
	 ,
	 -- start/endpoints that fall within a substation are supposed to become crossings later
	 -- they will be identified by the voltage tag -9999
	  pt_substations AS (
		  SELECT a.id,
		         -9999 AS voltage
			FROM all_points              a
				     JOIN power_stations s
				          ON st_within(point, geom)
	  )
SELECT voltage,
       point
  FROM (
	       SELECT a.id,
	              CASE WHEN s.voltage IS NULL THEN a.voltage ELSE s.voltage END AS voltage,
	              a.point
			 FROM all_points                   a
				      LEFT JOIN pt_substations s
				                USING (id)) ua
 GROUP BY point,
          voltage;

/*
 copy crossings-information to segments table
 */

UPDATE segments a
   SET source = st.id
  FROM source_target st
 WHERE st_equals(a.startpoint, st.point)
   AND (a.voltage = st.voltage OR st.voltage = -9999);

UPDATE segments a
   SET target = st.id
  FROM source_target st
 WHERE st_equals(a.endpoint, st.point)
   AND (a.voltage = st.voltage OR st.voltage = -9999);

-- segments without a voltage tag will not be needed
DELETE
  FROM segments
 WHERE voltage IS NULL;

-- segment length will be used as routing costs later
UPDATE segments
   SET length = st_length(way);

INSERT INTO gridkit_power_line_voltage_routing_network (l_id, voltage, way, startpoint, endpoint, substation_id, source,
                                                        target, length)
SELECT l_id,
       voltage,
       way,
       startpoint,
       endpoint,
       substation_id,
       source,
       target,
       length
  FROM segments;


/*
 create nodes table
 */

SELECT pgr_createverticestable('gridkit_power_line_voltage_routing_network', 'way', 'source', 'target');

/*
 identify main network to prevent unconnected segments from breaking the routing
 */

-- the network geoms need to be hashed for the UNION clause in the recursive to work
-- geohash is also faster for geometry comparisons
INSERT INTO hashed_network (l_id, source, target, startpoint_hash, endpoint_hash)
SELECT l_id,
       source,
       target,
       st_geohash(st_transform(startpoint, 4326)) AS startpoint_hash,
       st_geohash(st_transform(endpoint, 4326))   AS endpoint_hash
  FROM gridkit_power_line_voltage_routing_network;

-- a starting segment of the main network (gridkit_power_line_voltage_routing_network) needs to be identified
-- and its l_id must replace the placeholder '?'
DROP TABLE IF EXISTS recursion_network;
CREATE TEMP TABLE recursion_network AS (
	  WITH RECURSIVE network AS (
		  SELECT l_id,
		         source,
		         target,
		         startpoint_hash,
		         endpoint_hash
			FROM hashed_network
		   WHERE l_id = ?
		   UNION
		  SELECT a.l_id,
		         a.source,
		         a.target,
		         a.startpoint_hash,
		         a.endpoint_hash
			FROM hashed_network AS a
				     JOIN network  b
				          ON (a.startpoint_hash = b.startpoint_hash OR
					          a.startpoint_hash = b.endpoint_hash OR
					          a.endpoint_hash = b.startpoint_hash OR
					          a.endpoint_hash = b.endpoint_hash
					          ) AND
					          (a.source = b.source OR a.source = b.target OR a.target = b.source
							          OR a.target = b.target)
	  )
	SELECT *
	  FROM network
);

/*
 update relevant tables with new information 'part_of_network'
 */

-- update network table
UPDATE gridkit_power_line_voltage_routing_network
   SET part_of_network = TRUE
 WHERE l_id IN (SELECT l_id
                  FROM recursion_network);

-- update nodes table
ALTER TABLE gridkit_power_line_voltage_routing_network_vertices_pgr
	ADD COLUMN part_of_network BOOLEAN DEFAULT FALSE;

  WITH network_segments AS (
	  SELECT source AS id
		FROM gridkit_power_line_voltage_routing_network
	   WHERE part_of_network IS TRUE
	   UNION ALL
	  SELECT target AS id
		FROM gridkit_power_line_voltage_routing_network
	   WHERE part_of_network IS TRUE
  )
UPDATE gridkit_power_line_voltage_routing_network_vertices_pgr
   SET part_of_network = TRUE
 WHERE id IN (SELECT id
                FROM network_segments);

-- update source/target table
  WITH network_segments AS (
	  SELECT source AS id
		FROM gridkit_power_line_voltage_routing_network
	   WHERE part_of_network IS TRUE
	   UNION ALL
	  SELECT target AS id
		FROM gridkit_power_line_voltage_routing_network
	   WHERE part_of_network IS TRUE
  )
UPDATE source_target
   SET part_of_network = TRUE
 WHERE id IN (SELECT id
                FROM network_segments);

-- update source/target table with information of connected voltage levels
  WITH conns AS (
	  SELECT a.id,
	         array_agg(b.voltage) AS voltages
		FROM source_target                                       a
			     JOIN gridkit_power_line_voltage_routing_network b
			          ON (a.id = b.source OR a.id = b.target)
	   WHERE a.part_of_network IS TRUE
	   GROUP BY 1
  )
UPDATE source_target a
   SET voltage_connected = conns.voltages
  FROM conns
 WHERE a.id = conns.id;

/*
 Fill nk and nuts tables with external data:

 You will need data of net-nodes to fill the table "nk". Refer to OSM to extract own net-nodes.
 You will also need NUTS-3 and NUTS-0 geometries.
 Refer to https://openenergy-platform.org/dataedit/view/boundaries/ffe_osm_nuts3 for NUTS-3 geoms.
 You can then aggregate NUTS-3 to NUTS-0
 */

INSERT INTO nk (id_region, geom_3857, geom_4326)
SELECT id_region,
       st_transform(geom_3035, 3857),
       geom_4326
  FROM MY_NET_NODES_TABLE;

INSERT INTO nuts3 (id_region_type, id_region, name, geom_4326, geom_3035, geom_3857)
SELECT 38,
       id_region,
       name,
       geom_4326,
       geom_3035,
       st_transform(geom_3035, 3857)
  FROM MY_NUTS_TABLE;