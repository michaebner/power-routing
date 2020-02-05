/*
 |---------------------------------------------------------------------------------------------------------------------|
 | OpenStreetMap 110 kV-Routing
 | Author: Michael Ebner, 2019
 | Part 3: power routing
 |---------------------------------------------------------------------------------------------------------------------|
*/

/*
 You will need data of net-nodes to fill the table "nk". Refer to OSM to extract own net-nodes.
 You will also need NUTS-3 and NUTS-0 geometries.
 Refer to https://openenergy-platform.org/dataedit/view/boundaries/ffe_osm_nuts3 for NUTS-3 geoms.
 You can then aggregate NUTS-3 to NUTS-0
 */

-- Selection of all German net-nodes and assignment to nearest node of routing network

INSERT INTO nk_de (id_region, nuts, geom_3857, node_id)
SELECT a.*,
       ua.id AS node_id
  FROM (
	       SELECT a.id_region,
	              b.id_region AS nuts,
	              a.geom_3857
			 FROM nk             a
				      JOIN nuts3 b
				           ON st_within(a.geom_4326, b.geom_4326)
			WHERE b.name LIKE 'DE%')     a
	       CROSS JOIN LATERAL (SELECT id
	                             FROM source_target b
	                            WHERE (110000 = ANY (voltage_connected) OR 220000 = ANY (voltage_connected)
			                            OR 380000 = ANY (voltage_connected))
	                              AND part_of_network IS TRUE
	                            ORDER BY a.geom_3857 <-> b.point
	                            LIMIT 1) ua;


-- Identify end points of 110 kV Network
INSERT INTO conn_pts (node_id, geom, name, id_region)
  WITH conn_pts AS (
	  SELECT ua.*
		FROM (
			     SELECT source     AS id,
			            startpoint AS geom
				   FROM gridkit_power_line_voltage_routing_network
				  WHERE voltage = 110000
				    AND part_of_network IS TRUE
				  UNION ALL
				 SELECT target   AS id,
				        endpoint AS geom
				   FROM gridkit_power_line_voltage_routing_network
				  WHERE voltage = 110000
				    AND part_of_network IS TRUE) ua
			     JOIN power_stations             s
			          ON st_within(ua.geom, s.geom)
	   WHERE power_name IN ('substation', 'sub_station', 'station')
	   GROUP BY 1, 2
	   ORDER BY 1
  )
SELECT a.id AS node_id,
       geom,
       b.name,
       b.id_region
  FROM conn_pts AS    a
	       JOIN nuts3 b
	            ON st_within(st_transform(a.geom, 3035), b.geom_3035)
 WHERE b.name LIKE 'DE%'
 ORDER BY 4;

-- The actual routing happens here
INSERT INTO conn_pts_110kv_nk (seq, path_seq, start_vid, end_vid, node, edge, cost, agg_cost, rank)
SELECT seq,
       path_seq,
       ua.start_vid,
       end_vid,
       node,
       edge,
       cost,
       agg_cost,
       rank
  FROM (
	       SELECT *,
	              rank() OVER (PARTITION BY start_vid ORDER BY agg_cost) AS rank
			 FROM (
				      SELECT *
					    FROM pgr_dijkstra(
							    'SELECT id, source, target, length AS cost FROM gridkit_power_line_voltage_routing_network
WHERE st_intersects(way, (SELECT st_transform(st_setsrid(st_geomfromtext(''POLYGON((5.43 55.63, 15.7 55.63, 15.7 47.16, 5.43 47.16, 5.43 55.63))''),
4326), 3857) AS geom)) AND voltage in (110000) and part_of_network is true'::TEXT,
							    (SELECT array_agg(node_id::INTEGER) AS nodes
							       FROM conn_pts), (SELECT array_agg(node_id::INTEGER)
							                          FROM nk_de), FALSE)
					   WHERE edge = -1) ua) ua
 WHERE rank <= 5;

-- If start and end vid are identical, they have to be added manually
INSERT INTO conn_pts_110kv_nk (seq, path_seq, start_vid, end_vid, node, edge, cost, agg_cost, rank)
SELECT 0,
       0,
       node_id,
       node_id,
       node_id,
       -1,
       0,
       0.1,
       1
  FROM conn_pts       a
	       JOIN nk_de b
	            USING (node_id);

-- Share of all network endpoints on net nodes
-- Nuts-3-value is split homogenously on all endpoints
INSERT INTO share_endpoint_nk (id_region_nk, connection_pt, name, id_region_nuts3, agg_cost, share)
SELECT id_region_nk,
       connection_pt,
       name,
       id_region_nuts3,
       agg_cost,
       ua.share_dist / sum(ua.share_dist) OVER (PARTITION BY connection_pt)
	       AS share
  FROM (
	       SELECT nk.id_region AS id_region_nk,
	              start_vid    AS connection_pt,
	              name,     -- Nuts3
	              c.id_region  AS id_region_nuts3,
	              agg_cost, -- length in m
	              greatest(0, 1 - agg_cost
			              / greatest(25000, min(agg_cost) OVER (PARTITION BY start_vid) + 0.1))
	                           AS share_dist
			 FROM conn_pts_110kv_nk a
				      JOIN nk_de    nk
				           ON a.end_vid = nk.node_id
				      JOIN conn_pts c
				           ON a.start_vid = c.node_id
			GROUP BY 1, 2, 3, 4, 5
			ORDER BY 3) ua;

-- Share of Nuts-values on net nodes
INSERT INTO share_nuts_nk (id_region_nk, id_region_nuts3, name, share_nuts_nk)
  WITH distinct_nk AS (
	  SELECT count(DISTINCT connection_pt) AS val,
	         id_region_nuts3
		FROM share_endpoint_nk
	   WHERE share != 0
	   GROUP BY 2)
SELECT *
  FROM (
	       SELECT id_region_nk,
	              id_region_nuts3,
	              name,
	              sum(share / val) AS share_nuts_nk -- so viel % der Nuts-Last gehen über diesen Anschluss an diesen Netzknoten
			 FROM share_endpoint_nk
				      JOIN distinct_nk
				           USING (id_region_nuts3)
			GROUP BY 1, 2, 3
			ORDER BY 2, 1) ua
 WHERE share_nuts_nk != 0;

-- Manually assign nuts that could not be assigned
INSERT INTO share_nuts_nk (id_region_nk, id_region_nuts3, name, share_nuts_nk)
SELECT b.id_region_nk,
       a.id_region_nuts3,
       name,
       1
  FROM (
	       SELECT id_region AS id_region_nuts3,
	              name,
	              geom_3035
			 FROM nuts3
			WHERE name LIKE 'DE%'
			  AND id_region NOT IN (
				SELECT id_region_nuts3
				  FROM share_nuts_nk
				 GROUP BY 1))            a
	       CROSS JOIN LATERAL (SELECT id_region AS id_region_nk,
	                                  geom_3035
	                             FROM nk
	                            ORDER BY a.geom_3035 <-> geom_3035
	                            LIMIT 1) b;

/*
 RESULT
 id_region_nk:      id of electrical net node
 id_region_nuts_3:  id of NUTS-3-region
 name:              NUTS-3-nomenclatur
 share_nuts_nk:     share of NUTS-3-value (consumption, generation etc.) on electrical net node. Sums up to 1 per NUTS-3
 */

SELECT *
  FROM share_nuts_nk;

/*
 Validation
 */

-- Number of NUTS-3-regions must be 402 (NUTS 2013) or 401 (NUTS 2016)
SELECT count(DISTINCT id_region_nuts3)
  FROM share_nuts_nk;


-- Summarized shares must be 1 per NUTS-3-region
SELECT id_region_nuts3,
       round(sum(share_nuts_nk), 1) AS valid
  FROM share_nuts_nk
 GROUP BY 1;

