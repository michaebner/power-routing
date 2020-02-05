/*
 |---------------------------------------------------------------------------------------------------------------------|
 | OpenStreetMap 110 kV-Routing
 | Author: Michael Ebner, 2019
 | Preliminary steps. Can be skipped if database and pgRouting are already set up
 |---------------------------------------------------------------------------------------------------------------------|
*/

CREATE DATABASE gridkit_power_routing;
CREATE EXTENSION postgis;
CREATE EXTENSION pgrouting;
CREATE SCHEMA gridkit;

SET SEARCH_PATH TO gridkit, public;