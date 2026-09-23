**FREE

// Test 109: SQL indicator variables — NULL insertion and NULL detection

DCL-S connStr  VARCHAR(200);
DCL-S empId    INT(10);
DCL-S empName  VARCHAR(50);
DCL-S empNote  VARCHAR(100);
DCL-S nameInd  INT(5);
DCL-S noteInd  INT(5);

// Cursor FETCH with indicator variables
DCL-S done IND;

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test109.sqlite;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE ind109 (
  id   INTEGER PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  note VARCHAR(100)
);

// Insert row 1: non-null name, NULL note (indicator = -1)
empId   = 1;
empName = 'Alice';
noteInd = -1;
empNote = 'ignored';
EXEC SQL INSERT INTO ind109 (id, name, note)
  VALUES(:empId, :empName, :empNote :noteInd);

// Insert row 2: non-null name, non-null note (indicator = 0)
empId   = 2;
empName = 'Bob';
noteInd = 0;
empNote = 'Manager';
EXEC SQL INSERT INTO ind109 (id, name, note)
  VALUES(:empId, :empName, :empNote :noteInd);

// SELECT INTO with indicator — row 1 (note is NULL)
EXEC SQL SELECT name, note INTO :empName :nameInd, :empNote :noteInd
  FROM ind109 WHERE id = 1;
DSPLY 'name=' + empName + ' nameInd=' + %CHAR(nameInd);
DSPLY 'noteInd=' + %CHAR(noteInd);

// SELECT INTO with indicator — row 2 (note is not NULL)
EXEC SQL SELECT name, note INTO :empName :nameInd, :empNote :noteInd
  FROM ind109 WHERE id = 2;
DSPLY 'name=' + empName + ' noteInd=' + %CHAR(noteInd);
DSPLY 'note=' + empNote;

done = *OFF;
EXEC SQL DECLARE C1 CURSOR FOR
  SELECT name, note FROM ind109 ORDER BY id;
EXEC SQL OPEN C1;
EXEC SQL FETCH C1 INTO :empName :nameInd, :empNote :noteInd;
DOW SQLCOD = 0;
  IF noteInd < 0;
    DSPLY 'Fetch: ' + empName + ' note=NULL';
  ELSE;
    DSPLY 'Fetch: ' + empName + ' note=' + empNote;
  ENDIF;
  EXEC SQL FETCH C1 INTO :empName :nameInd, :empNote :noteInd;
ENDDO;
EXEC SQL CLOSE C1;

EXEC SQL COMMIT;
EXEC SQL DROP TABLE ind109;
EXEC SQL DISCONNECT;

*INLR = *ON;
RETURN;
