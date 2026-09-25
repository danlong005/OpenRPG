**FREE
// An IBM i object name is at most 10 characters, so IBM i rejects a data
// area named with more (RNF0653).
DCL-S da CHAR(10) DTAARA('CONFIGAREA1');
IN da;
DSPLY da;
*INLR = *ON;
