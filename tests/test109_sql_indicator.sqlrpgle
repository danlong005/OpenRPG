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

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test109.sqlite;';
// OpenRPG connects by ODBC connection string; an IBM i job is already connected.
/IF DEFINED(*OPENRPG)
EXEC SQL CONNECT USING :connStr;
/ENDIF

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
dspLine = ('name=' + empName + ' nameInd=' + %CHAR(nameInd));
DSPLY dspLine;
DSPLY ('noteInd=' + %CHAR(noteInd));

// SELECT INTO with indicator — row 2 (note is not NULL)
EXEC SQL SELECT name, note INTO :empName :nameInd, :empNote :noteInd
  FROM ind109 WHERE id = 2;
dspLine = ('name=' + empName + ' noteInd=' + %CHAR(noteInd));
DSPLY dspLine;
dspLine = ('note=' + empNote);
DSPLY dspLine;

done = *OFF;
EXEC SQL DECLARE C1 CURSOR FOR
  SELECT name, note FROM ind109 ORDER BY id;
EXEC SQL OPEN C1;
EXEC SQL FETCH C1 INTO :empName :nameInd, :empNote :noteInd;
DOW SQLCOD = 0;
  IF noteInd < 0;
    dspLine = ('Fetch: ' + empName + ' note=NULL');
    DSPLY dspLine;
  ELSE;
    dspLine = ('Fetch: ' + empName + ' note=' + empNote);
    DSPLY dspLine;
  ENDIF;
  EXEC SQL FETCH C1 INTO :empName :nameInd, :empNote :noteInd;
ENDDO;
EXEC SQL CLOSE C1;

EXEC SQL COMMIT;
EXEC SQL DROP TABLE ind109;
/IF DEFINED(*OPENRPG)
EXEC SQL DISCONNECT;
/ENDIF

*INLR = *ON;
RETURN;
