**FREE
// Test 92: Data areas — *LDA read/write round-trip
DCL-S LdaData CHAR(20) DTAARA(*LDA);

// Write something to *LDA
LdaData = 'HELLO DATA AREA     ';
OUT LdaData;

// Clear local variable
LdaData = '';

// Read it back
IN LdaData;

IF %TRIM(LdaData) = 'HELLO DATA AREA';
  DSPLY 'LDA ROUNDTRIP OK';
ELSE;
  DSPLY 'LDA ROUNDTRIP FAIL';
ENDIF;

// No UNLOCK: the local data area is never locked (IBM: RNF7091)
*INLR = *ON;
