**FREE
// Test 94: Operation extenders on EVAL and EVALR
// EVAL takes (H), (M) and (R); EVALR takes (M) and (R). Only (H) rounds:
// (M) and (R) choose the precision rules for intermediate results. Other
// extenders are rejected, as on IBM i (RNF5049); tests 278-279 cover that.
DCL-S a PACKED(7:1) INZ(7.0);
DCL-S b PACKED(7:0) INZ(2);
DCL-S result INT(10);
DCL-S result2 INT(10);
DCL-S result3 INT(10);
DCL-S rTarget CHAR(10) INZ(*BLANKS);

// (H): half-adjust rounds 3.5 to 4
EVAL(H) result = a / b;
IF result = 4;
  DSPLY 'EXTENDER H OK';
ELSE;
  DSPLY 'EXTENDER H FAIL';
ENDIF;

// (R): result-decimal-position precision; the 3.5 is truncated to 3
EVAL(R) result2 = a / b;
IF result2 = 3;
  DSPLY 'EXTENDER R OK';
ELSE;
  DSPLY 'EXTENDER R FAIL';
ENDIF;

// (MH): extenders combine; H still rounds
EVAL(MH) result3 = a / b;
IF result3 = 4;
  DSPLY 'COMBO MH OK';
ELSE;
  DSPLY 'COMBO MH FAIL';
ENDIF;

// EVALR(M): right-adjusts the value in the character target
EVALR(M) rTarget = 'ABC';
IF rTarget = '       ABC';
  DSPLY 'EVALR M OK';
ELSE;
  DSPLY 'EVALR M FAIL';
ENDIF;

*INLR = *ON;
