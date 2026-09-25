**FREE
// Test 93: Named data area. The name is quoted: unquoted, DTAARA(x) names a
// variable that holds the data area's name, as on IBM i.
DCL-S MyConfig CHAR(50) DTAARA('RPGCTEST93');

MyConfig = 'VERSION=1.0                                       ';
OUT MyConfig;
MyConfig = '';
IN MyConfig;

IF %SUBST(MyConfig: 1: 9) = 'VERSION=1';
  DSPLY 'NAMED DA OK';
ELSE;
  DSPLY 'NAMED DA FAIL';
ENDIF;

UNLOCK MyConfig;
*INLR = *ON;
