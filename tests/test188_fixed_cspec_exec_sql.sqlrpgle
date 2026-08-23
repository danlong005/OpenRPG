     HDFTACTGRP(*NO)
     Dconn                      200    A   VARYING
     Dnm                         50    A   VARYING
     Dtot                        10    I 0
     C                   EVAL      conn = 'Driver={SQLite3};Data' +
     C                             'base=/tmp/rpgc_test188.sqlite;'
     C/EXEC SQL
     C+ CONNECT USING :conn
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE IF EXISTS fx188
     C/END-EXEC
     C/EXEC SQL
     C+ CREATE TABLE fx188 (id INTEGER PRIMARY KEY,
     C+                     nm VARCHAR(50))
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO fx188 VALUES (1, 'Alice')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO fx188 VALUES (2, 'Bob')
     C/END-EXEC
     C/EXEC SQL
     C+ SELECT nm INTO :nm FROM fx188 WHERE id = 1
     C/END-EXEC
     C     nm            DSPLY
     C/EXEC SQL
     C+ SELECT COUNT(*) INTO :tot FROM fx188
     C/END-EXEC
     C     %CHAR(tot)    DSPLY
     C                   RETURN
