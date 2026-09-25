**FREE
// Host variables filled by SELECT INTO and FETCH fit their declarations.
//
// A host variable received the column value exactly as the driver returned
// it: a CHAR(10) host variable holding 'Bob' was three bytes long, and a
// PACKED(7:2) one receiving 12.345 held 12.345. On IBM i the host variable
// is the declared field, so it holds 'Bob' plus seven blanks and 12.34.
DCL-S connStr VARCHAR(200);
DCL-S name    CHAR(10);
DCL-S amt     PACKED(7:2);

DCL-DS row QUALIFIED;
  name CHAR(8);
  amt  PACKED(7:1);
END-DS;

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test237.sqlite;';
// OpenRPG connects by ODBC connection string; an IBM i job is already connected.
/IF DEFINED(*OPENRPG)
EXEC SQL CONNECT USING :connStr;
/ENDIF
EXEC SQL DROP TABLE IF EXISTS fit237;
EXEC SQL CREATE TABLE fit237 (id INTEGER PRIMARY KEY, name VARCHAR(20), amt REAL);
EXEC SQL INSERT INTO fit237 VALUES(1, 'Bob', 12.345);
EXEC SQL INSERT INTO fit237 VALUES(2, 'A LONGER NAME', 7.89);

EXEC SQL SELECT name, amt INTO :name, :amt FROM fit237 WHERE id = 1;
DSPLY ('RESULT:SELNAME=[' + name + '] ' + %CHAR(%LEN(name)));
DSPLY ('RESULT:SELAMT=' + %CHAR(amt));

EXEC SQL DECLARE c237 CURSOR FOR SELECT name, amt FROM fit237 WHERE id = 2;
EXEC SQL OPEN c237;
EXEC SQL FETCH c237 INTO :row;
EXEC SQL CLOSE c237;
DSPLY ('RESULT:FETCH=[' + row.name + '] ' + %CHAR(row.amt));

EXEC SQL DROP TABLE fit237;
*INLR = *ON;
