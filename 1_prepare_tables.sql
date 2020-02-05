/*
 |---------------------------------------------------------------------------------------------------------------------|
 | OpenStreetMap 110 kV-Routing
 | Author: Michael Ebner, 2019
 | Part 1: Prepare Tables
 |---------------------------------------------------------------------------------------------------------------------|
*/

/*
 Prerequisits: successful GridKit power grid extract
 you will at least need the tables "gridkit_heuristic_links_highvoltage" and "gridkit_power_station"
 For information about GridKit see https://github.com/bdw/GridKit
 */

-- base power grid table
DROP TABLE IF EXISTS gridkit_power_line_voltage;
CREATE TABLE gridkit_power_line_voltage (
	id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	l_id        INTEGER,
	v_id_1      INTEGER,
	v_id_2      INTEGER,
	length_m    DOUBLE PRECISION,
	voltage     TEXT,
	cables      TEXT,
	wires       TEXT,
	frequency   TEXT,
	name        TEXT,
	operator    TEXT,
	ref         TEXT,
	part_nr     INTEGER,
	num_objects INTEGER,
	geom        GEOMETRY(linestring, 3857)
);

CREATE INDEX ON gridkit_power_line_voltage USING gist(geom);

-- base substation table
DROP TABLE IF EXISTS power_stations;
CREATE TABLE power_stations (
	id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	station_id INTEGER,
	power_name TEXT,
	geom       GEOMETRY(polygon, 3857)
);

CREATE INDEX ON power_stations USING gist(geom);

-- segments table for spatial adjustments
DROP TABLE IF EXISTS segments;
CREATE TABLE segments (
	id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	l_id          INTEGER,
	voltage       INTEGER,
	way           GEOMETRY(linestring, 3857),
	startpoint    GEOMETRY(point, 3857),
	endpoint      GEOMETRY(point, 3857),
	substation_id BIGINT,
	source        INTEGER,
	target        INTEGER,
	length        DOUBLE PRECISION
);

CREATE INDEX ON segments USING gist(way);
CREATE INDEX ON segments USING gist(startpoint);
CREATE INDEX ON segments USING gist(endpoint);

-- source target table necessary for pgRouting
DROP TABLE IF EXISTS source_target;
CREATE TABLE source_target (
	id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	voltage           INTEGER,
	point             GEOMETRY(point, 3857),
	part_of_network   BOOLEAN DEFAULT FALSE,
	voltage_connected INTEGER[]
);

CREATE INDEX ON source_target USING gist(point);

-- final routing table
DROP TABLE IF EXISTS gridkit_power_line_voltage_routing_network;
CREATE TABLE gridkit_power_line_voltage_routing_network (
	id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	l_id            INTEGER,
	voltage         INTEGER,
	way             GEOMETRY(linestring, 3857),
	startpoint      GEOMETRY(point, 3857),
	endpoint        GEOMETRY(point, 3857),
	substation_id   BIGINT,
	source          INTEGER,
	target          INTEGER,
	length          DOUBLE PRECISION,
	part_of_network BOOLEAN DEFAULT FALSE
);

CREATE INDEX ON gridkit_power_line_voltage_routing_network USING gist(way);
CREATE INDEX ON gridkit_power_line_voltage_routing_network USING gist(startpoint);
CREATE INDEX ON gridkit_power_line_voltage_routing_network USING gist(endpoint);

-- the network table for recursive network identification needs geohashes
DROP TABLE IF EXISTS hashed_network;
CREATE TABLE hashed_network (
	id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	l_id            INTEGER,
	source          INTEGER,
	target          INTEGER,
	startpoint_hash TEXT,
	endpoint_hash   TEXT
);

CREATE INDEX ON hashed_network(startpoint_hash);
CREATE INDEX ON hashed_network(endpoint_hash);

/*
 tables necessary for assignment of NUTS-3 to net-nodes
 */

DROP TABLE IF EXISTS nk;
CREATE TABLE nk (
	id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	id_region INTEGER,
	nuts      INTEGER,
	geom_3857 GEOMETRY(POINT, 3857),
	geom_4326 GEOMETRY(POINT, 4326),
	node_id   BIGINT
);

CREATE INDEX ON nk USING gist(geom_3857);
CREATE INDEX ON nk USING gist(geom_4326);

DROP TABLE IF EXISTS nuts3;
CREATE TABLE nuts3 (
	id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	id_region_type INTEGER,
	id_region      INTEGER,
	name           VARCHAR(5),
	geom_4326      GEOMETRY(GEOMETRY, 4326),
	geom_3035      GEOMETRY(GEOMETRY, 3035),
	geom_3857      GEOMETRY(GEOMETRY, 3857)
);

CREATE INDEX ON nuts3 USING gist(geom_4326);
CREATE INDEX ON nuts3 USING gist(geom_3035);
CREATE INDEX ON nuts3 USING gist(geom_3857);

/*
 Tables for routing results
 */

-- Table for German net nodes with assigned nodes of routing network
DROP TABLE IF EXISTS nk_de;
CREATE TABLE nk_de (
	id_region INTEGER,
	nuts      INTEGER,
	geom_3857 GEOMETRY(geometry, 3857),
	node_id   INTEGER
);

CREATE INDEX ON nk_de USING gist(geom_3857);

DROP TABLE IF EXISTS conn_pts;
CREATE TABLE conn_pts (
	id        INTEGER GENERATED ALWAYS AS IDENTITY,
	node_id   INTEGER,
	geom      GEOMETRY(geometry, 3857),
	name      VARCHAR(5),
	id_region INTEGER
);

-- Start_vids are the endpoints of the network, end_vids are the network nodes of the net-nodes
DROP TABLE IF EXISTS conn_pts_110kv_nk;
CREATE TABLE conn_pts_110kv_nk (
	seq       INTEGER,
	path_seq  INTEGER,
	start_vid BIGINT,
	end_vid   BIGINT,
	node      BIGINT,
	edge      BIGINT,
	cost      DOUBLE PRECISION,
	agg_cost  DOUBLE PRECISION,
	rank      BIGINT
);

-- Intermediate results table
DROP TABLE IF EXISTS share_endpoint_nk;
CREATE TABLE share_endpoint_nk (
	id_region_nk    INTEGER,
	connection_pt   INTEGER,
	name            VARCHAR(5),
	id_region_nuts3 INTEGER,
	agg_cost        DOUBLE PRECISION,
	share           DOUBLE PRECISION
);

-- final results table
DROP TABLE IF EXISTS share_nuts_nk;
CREATE TABLE share_nuts_nk (
	id_region_nk    INTEGER,
	id_region_nuts3 INTEGER,
	name            VARCHAR(5),
	share_nuts_nk   DOUBLE PRECISION
);
