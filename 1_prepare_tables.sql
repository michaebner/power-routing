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
	station_id INTEGER,
	power_name TEXT,
	geom       GEOMETRY(polygon, 3857)
);

CREATE INDEX ON power_stations USING gist(geom);

-- segments table for spatial adjustments
DROP TABLE IF EXISTS segments;
CREATE TABLE segments (
	id            INTEGER GENERATED ALWAYS AS IDENTITY,
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
	id                INTEGER GENERATED ALWAYS AS IDENTITY,
	voltage           INTEGER,
	point             GEOMETRY(point, 3857),
	part_of_network   BOOLEAN DEFAULT FALSE,
	voltage_connected INTEGER[]
);

CREATE INDEX ON source_target USING gist(point);

-- final routing table
DROP TABLE IF EXISTS gridkit_power_line_voltage_routing_network;
CREATE TABLE gridkit_power_line_voltage_routing_network (
	id              INTEGER GENERATED ALWAYS AS IDENTITY,
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
/*
 die Datensätze braucht man:
 Netzknoten
 Nuts3 (openData)
 Nuts0 (openData)

*/

drop table IF EXISTS nk;
 create table nk
(
	id_region integer,
	nuts integer,
	geom_3857 geometry,
	node_id bigint
);

create index nk_56_geom_3857_idx
	on nk (geom_3857);

