**FREE
// Test 98: Data area status 413 - cannot write to data area
// (Test runner creates a read-only file with chmod 444 before running this)
DCL-S da CHAR(10) DTAARA('RPGCT98DA');

da = 'TEST DATA ';
OUT da;
IF %STATUS() = 413;
  DSPLY 'STATUS 413 OK';
ELSE;
  DSPLY 'STATUS 413 FAIL';
ENDIF;

*INLR = *ON;
