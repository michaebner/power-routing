# Power-routing
A collection of SQL scripts implementing PostGIS and pgRouting for the routing on power grids.

This set of SQL files will help you implement a database, set up PostGIS and pgRouting (if install packages are provided) as well as all relevant tables for the power routing. If you provide data of electrical net-nodes and NUTS-3-geometries (you can find a download link in script 1_prepare_tables.sql) script 3 will lead you through the process of how the NUTS-regions can be assigned to the electrical net nodes taking into account the actual 110 kV transmission grid topology.

Script 4 provides custom SQL routing functions like a Dijkstra Many to Many function that takes a set of GEOMVALs as input and output and will find the shortest path of each start to each end point.

If you have any questions or find any bugs, don't hesitate to contact me at mebner@ffe.de
