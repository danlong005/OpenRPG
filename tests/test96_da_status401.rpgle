**FREE
// Test 96: Data area status 401 - data area not found
DCL-S missing CHAR(10) DTAARA('NOSUCHDA96');

IN missing;
IF %STATUS() = 401;
  DSPLY 'STATUS 401 OK';
ELSE;
  DSPLY 'STATUS 401 FAIL';
ENDIF;

*INLR = *ON;
