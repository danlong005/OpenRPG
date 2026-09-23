**FREE
// NOT is a unary operator: it binds tighter than a comparison and tighter
// than AND. On an indicator, `NOT *IN03 = *ON` is (NOT *IN03) = *ON, and
// `NOT *IN03 AND *IN04` is (NOT *IN03) AND *IN04.
DCL-S x    INT(10) INZ(5);
DCL-S done IND INZ(*OFF);

*IN03 = *OFF;
*IN04 = *ON;
IF NOT *IN03 = *ON;
  DSPLY 'RESULT:EQ=1';
ENDIF;
IF NOT *IN03 AND *IN04;
  DSPLY 'RESULT:AND=1';
ENDIF;
IF NOT (x = 0);
  DSPLY 'RESULT:PAREN=1';
ENDIF;
IF NOT done AND NOT (x > 10);
  DSPLY 'RESULT:TWO=1';
ENDIF;
*INLR = *ON;
