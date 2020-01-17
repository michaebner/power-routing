/*
 |---------------------------------------------------------------------------------------------------------------------|
 | OpenStreetMap 110 kV-Routing
 | Author: Michael Ebner, 2019
 | Custom routing functions
 |---------------------------------------------------------------------------------------------------------------------|
*/

/*
 custom dijkstra many2many routing-function for points that are not part of the routing network, e.g. routing wind
 turbines to net-nodes. Look at end of file for example
 INPUT:     SQL-Text of routing-network (see http://docs.pgrouting.org/latest/en/pgr_dijkstra.html),
            Array of start-points (GEOMVAL of geom, id),
            Array of end-points (GEOMVAL of geom, id),
            Array of nodes (GEOMVAL of geom, id),
            BOOL, graph directed (TRUE) or not (FALSE)
*/

CREATE OR REPLACE FUNCTION pgr_dijkstra_many2many(sql TEXT, start_pts GEOMVAL[], end_pts GEOMVAL[],
                                                           nodes GEOMVAL[], directed BOOLEAN)
	RETURNS TABLE (
		start_id  INTEGER,
		end_id    INTEGER,
		costs     DOUBLE PRECISION,
		error_msg TEXT
	)
AS
$$
DECLARE
	counter INTEGER := 0;
BEGIN
	DROP TABLE IF EXISTS start_pt;
	CREATE TEMP TABLE start_pt AS (
		SELECT st_transform(geom, 3857) AS geom,
		       val::INT                 AS id
		  FROM (
			       SELECT (unnest(start_pts)).*) ua
	);

	CREATE INDEX ON start_pt USING gist(geom);

	RAISE NOTICE 'Start points transformed to EPSG:3857. No. of start points: %', (SELECT sum(1)
	                                                                                 FROM start_pt);

	DROP TABLE IF EXISTS end_pt;
	CREATE TEMP TABLE end_pt AS (
		SELECT st_transform(geom, 3857) AS geom,
		       val::INT                 AS id
		  FROM (
			       SELECT (unnest(end_pts)).*) ua
	);

	CREATE INDEX ON end_pt USING gist(geom);

	RAISE NOTICE 'End points transformed to EPSG:3857. No. of end points: %', (SELECT sum(1)
	                                                                             FROM end_pt);

	DROP TABLE IF EXISTS nodes_pt;
	CREATE TEMP TABLE nodes_pt AS (
		SELECT st_transform(geom, 3857) AS geom,
		       val::INT                 AS id
		  FROM (
			       SELECT (unnest(nodes)).*) ua
	);

	CREATE INDEX ON nodes_pt USING gist(geom);

	RAISE NOTICE 'Node points transformed to EPSG:3857. No. of node points: %', (SELECT sum(1)
	                                                                               FROM nodes_pt);

	-- Assignment of start and end geoms to nearest nodes of the network
	DROP TABLE IF EXISTS nodes_assignment;
	CREATE TEMP TABLE nodes_assignment AS (
		  WITH source_node AS (
			  SELECT b.id AS source_id,
			         (SELECT a.id AS source_node_id
			            FROM nodes_pt AS a
			           ORDER BY b.geom <-> a.geom
			           LIMIT 1)
				FROM start_pt AS b
		  )
			 , target_node AS (
			  SELECT b.id AS target_id,
			         (SELECT a.id AS target_node_id
			            FROM nodes_pt AS a
			           ORDER BY b.geom <-> a.geom
			           LIMIT 1)
				FROM end_pt AS b
		  )
		SELECT row_number() OVER (PARTITION BY source_target ORDER BY source_target, geom_id) AS rn,
		       *
		  FROM (SELECT source_id      AS geom_id,
		               source_node_id AS node_id,
		               's'            AS source_target
		          FROM source_node
		         UNION ALL
		        SELECT target_id      AS geom_id,
		               target_node_id AS node_id,
		               't'            AS source_target
		          FROM target_node
		         ORDER BY 3) ua
	);

	RAISE NOTICE 'Nodes assignment finished';

	DROP TABLE IF EXISTS results;
	CREATE TEMP TABLE results (
		source_id INTEGER,
		target_id INTEGER,
		tot_cost  DOUBLE PRECISION,
		err_msg   TEXT
	);

	-- routing
	WHILE counter <= (SELECT max(rn)
	                    FROM nodes_assignment
	                   WHERE source_target = 's')
		LOOP
			counter := counter + 1;
			RAISE NOTICE 'Routing start point %', counter;
			BEGIN
				-- special case: start and end-geom are at the same node
				IF (SELECT node_id
				      FROM nodes_assignment
				     WHERE source_target = 's'
				       AND rn = counter) IN (SELECT node_id
				                               FROM nodes_assignment
				                              WHERE source_target = 't') THEN
					INSERT INTO results (source_id, target_id, tot_cost)
					SELECT (SELECT geom_id
					          FROM nodes_assignment
					         WHERE source_target = 's'
					           AND rn = counter),
					       (SELECT geom_id
					          FROM nodes_assignment
					         WHERE node_id = (SELECT node_id
					                            FROM nodes_assignment
					                           WHERE source_target = 's'
					                             AND rn = counter)
					           AND source_target = 't'
					         LIMIT 1),
					       0;
					ELSE
						BEGIN
							INSERT INTO results (source_id, target_id, tot_cost)
							SELECT (SELECT geom_id
							          FROM nodes_assignment
							         WHERE source_target = 's'
							           AND rn = counter),
							       (SELECT geom_id
							          FROM nodes_assignment
							         WHERE source_target = 't'
							           AND end_vid = node_id
							         LIMIT 1),
							       agg_cost
							  FROM pgr_dijkstra(
									  sql::TEXT,
									  (SELECT node_id
									     FROM nodes_assignment
									    WHERE source_target = 's'
									      AND rn = counter),
									  ARRAY(SELECT node_id
									          FROM nodes_assignment
									         WHERE source_target = 't'), directed)
							 WHERE edge = -1
							 ORDER BY agg_cost
							 LIMIT 1;
						EXCEPTION
							WHEN OTHERS THEN
								INSERT INTO results (source_id, err_msg)
								SELECT (SELECT geom_id
								          FROM nodes_assignment
								         WHERE source_target = 's'
								           AND rn = counter),
								       SQLERRM;
								RAISE WARNING 'Routing for geom_id % failed: %', (SELECT geom_id
								                                                    FROM nodes_assignment
								                                                   WHERE source_target = 's'
								                                                     AND rn = counter), SQLERRM;
						END;
					END IF;

			END;
		END LOOP;

	RAISE NOTICE 'Routing for all points finished';

	RETURN QUERY SELECT source_id,
	                    target_id,
	                    tot_cost,
	                    err_msg
	               FROM results;

END;
$$
	LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgr_dijkstra_many2many(sql TEXT, start_pts GEOMVAL[], end_pts GEOMVAL[], nodes GEOMVAL[], directed BOOLEAN)
	IS '
 custom dijkstra many2many routing-function for points that are not part of the routing network, e.g. routing wind
 turbines to net-nodes
 INPUT:     SQL-Text of routing-network (see pgrouting.org),
            Array of start-points (GEOMVAL of geom, id),
            Array of end-points (GEOMVAL of geom, id),
            Array of nodes (GEOMVAL of geom, id),
            BOOL, graph directed (TRUE) or not (FALSE)
';

-- exemple of pgr_dijkstra_many2many
DROP TABLE IF EXISTS routing_res;
CREATE TEMP TABLE routing_res AS (
	  WITH start_pts AS (
		  SELECT (st_setsrid(st_makepoint(longitude, latitude), 4326), id)::GEOMVAL AS gval
			FROM some_table
	  )
		 , end_pts   AS (
		  SELECT (geom, uid)::GEOMVAL AS gval
			FROM some_other_table
	  )
		 , nodes     AS (
		  SELECT (the_geom, id)::GEOMVAL AS gval
			FROM gridkit_power_line_voltage_routing_network_vertices_pgr
		   WHERE part_of_network IS TRUE
	  )
	SELECT (tbl).*
	  FROM (
		       SELECT pgr_dijkstra_many2many(
				              'select id, source, target, length as cost from gridkit_power_line_voltage_routing_network where voltage != 0',
				              (SELECT array_agg(gval)
				                 FROM start_pts),
				              (SELECT array_agg(gval)
				                 FROM end_pts),
				              (SELECT array_agg(gval)
				                 FROM nodes),
				              FALSE) AS tbl) ua
	 ORDER BY 1
);