**FREE
// *INLR is an indicator. Setting it does not end the program: the
// calculations run on, and the program ends where the mainline does.
DCL-S n INT(10);

IF NOT *INLR;
  DSPLY 'LR starts off';
ENDIF;
*INLR = *ON;
DSPLY 'still running after LR';
IF *INLR;
  n = 1;
ENDIF;
*INLR = *OFF;
*INLR = (n = 1);
DSPLY %CHAR(n);
IF *INLR;
  DSPLY 'LR set from an expression';
ENDIF;
